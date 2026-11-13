use serde_json::{json, Value};
use std::{path::Path, time::Duration};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::{
        unix::{OwnedReadHalf, OwnedWriteHalf},
        UnixStream,
    },
};
use velora_connectivity_fakes::{bus::TestBus, secrets::FakeSecrets};

struct Client {
    reader: BufReader<OwnedReadHalf>,
    writer: OwnedWriteHalf,
    next: u64,
}
impl Client {
    async fn connect(path: &Path) -> Self {
        let stream = tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                if let Ok(stream) = UnixStream::connect(path).await {
                    break stream;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .unwrap();
        let (read, write) = stream.into_split();
        let mut reader = BufReader::new(read);
        let mut hello = String::new();
        reader.read_line(&mut hello).await.unwrap();
        assert_eq!(
            serde_json::from_str::<Value>(&hello).unwrap()["protocol"],
            1
        );
        Self {
            reader,
            writer: write,
            next: 0,
        }
    }
    async fn call(&mut self, method: &str, params: Value) -> Value {
        let wait_open = method == "unlock" || (method == "context" && params["locked"] == false);
        let mut response = self.raw_call(method, params).await;
        if wait_open && response["ok"] == true {
            tokio::time::timeout(Duration::from_secs(15), async {
                while response["result"]["opening"] == true {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                    response = self.raw_call("status", json!({})).await;
                }
            })
            .await
            .unwrap();
        }
        response
    }

    // Control responsiveness tests intentionally bypass readiness waiting.
    async fn raw_call(&mut self, method: &str, params: Value) -> Value {
        self.next += 1;
        self.writer
            .write_all(
                format!(
                    "{}\n",
                    json!({"id":self.next,"method":method,"params":params})
                )
                .as_bytes(),
            )
            .await
            .unwrap();
        tokio::time::timeout(Duration::from_secs(15), async {
            loop {
                let mut line = String::new();
                assert!(self.reader.read_line(&mut line).await.unwrap() > 0);
                let v: Value = serde_json::from_str(&line).unwrap();
                if v["id"] == self.next {
                    return v;
                }
            }
        })
        .await
        .unwrap()
    }
    async fn wait_index(&mut self, ready: bool) {
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let s = self.call("status", json!({})).await;
                if s["result"]["files"].as_i64().unwrap_or(0) >= 3
                    && s["result"]["scanning"] == false
                    && (!ready || s["result"]["pending"] == 0)
                {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(30)).await;
            }
        })
        .await
        .unwrap();
    }
}

#[tokio::test]
async fn bridge_exits_when_service_disconnects_with_stdin_still_open() {
    let tmp = tempfile::tempdir().unwrap();
    let directory = tmp.path().join("velora-lens");
    std::fs::create_dir(&directory).unwrap();
    let listener = tokio::net::UnixListener::bind(directory.join("search.sock")).unwrap();
    let mut child = tokio::process::Command::new(env!("CARGO_BIN_EXE_velora-searchd"))
        .arg("bridge")
        .env("XDG_RUNTIME_DIR", tmp.path())
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let _stdin = child.stdin.take().unwrap();
    let (mut stream, _) = tokio::time::timeout(Duration::from_secs(3), listener.accept())
        .await
        .unwrap()
        .unwrap();
    stream.write_all(b"service connected\n").await.unwrap();
    let mut output = BufReader::new(child.stdout.take().unwrap());
    let mut line = String::new();
    tokio::time::timeout(Duration::from_secs(3), output.read_line(&mut line))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(line, "service connected\n");
    drop(stream);
    let result = tokio::time::timeout(Duration::from_secs(3), child.wait())
        .await
        .expect("bridge must exit on server EOF so the shell can reconnect")
        .unwrap();
    assert!(result.success());
}

#[tokio::test]
async fn migration_keeps_same_connection_responsive_and_discards_stale_generations() {
    let bus = TestBus::start().unwrap();
    let secrets = FakeSecrets::start(&bus).await.unwrap();
    let connection = bus.connect().await.unwrap();
    let collection = zbus::Proxy::new(
        &connection,
        "org.freedesktop.secrets",
        "/org/freedesktop/secrets/aliases/default",
        "org.freedesktop.Secret.Collection",
    )
    .await
    .unwrap();
    let attrs = std::collections::HashMap::from([
        ("application", "velora-lens"),
        ("purpose", "index-key-v1"),
    ]);
    let props = std::collections::HashMap::from([
        (
            "org.freedesktop.Secret.Item.Label",
            zbus::Variant::from("Synthetic Lens test key"),
        ),
        (
            "org.freedesktop.Secret.Item.Attributes",
            zbus::Variant::from(attrs),
        ),
    ]);
    let secret = (
        zbus::OwnedObjectPath::try_from("/org/freedesktop/secrets/session/1").unwrap(),
        Vec::<u8>::new(),
        vec![83_u8; 32],
        "application/octet-stream",
    );
    let _: (zbus::OwnedObjectPath, zbus::OwnedObjectPath) = collection
        .call("CreateItem", &(props, secret, true))
        .await
        .unwrap();
    let tmp = tempfile::tempdir().unwrap();
    let runtime = tmp.path().join("runtime");
    let data = tmp.path().join("data");
    let root = tmp.path().join("documents");
    std::fs::create_dir(&runtime).unwrap();
    std::fs::create_dir_all(data.join("velora-lens")).unwrap();
    std::fs::create_dir(&root).unwrap();
    let note = root.join("note.md");
    std::fs::write(&note, "preserve this document").unwrap();
    let mut store =
        velora_searchd::store::Store::open(&data.join("velora-lens/index.db"), &[83; 32]).unwrap();
    store
        .set_config(&velora_searchd::config::Config {
            roots: vec![root],
            ..Default::default()
        })
        .unwrap();
    store.upsert(&note, "file", "note.md", 1, 22, 1, 1).unwrap();
    // A competing writer deterministically holds schema preparation long enough
    // to exercise responsiveness without a CPU-heavy corpus or test-only sleeps
    // inside production code. Everything lives in this private temporary index.
    store
        .db
        .execute_batch("PRAGMA user_version=2; BEGIN IMMEDIATE;")
        .unwrap();
    let mut child = tokio::process::Command::new(env!("CARGO_BIN_EXE_velora-searchd"))
        .arg("serve")
        .env("DBUS_SESSION_BUS_ADDRESS", &bus.address)
        .env("XDG_RUNTIME_DIR", &runtime)
        .env("XDG_DATA_HOME", &data)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let mut shell = Client::connect(&runtime.join("velora-lens/search.sock")).await;
    assert_eq!(shell.raw_call("attach", json!({})).await["ok"], true);
    let opened = tokio::time::timeout(
        Duration::from_millis(750),
        shell.raw_call("context", json!({"locked":false,"on_battery":true})),
    )
    .await
    .expect("context must acknowledge before migration finishes");
    assert_eq!(opened["result"]["opening"], true, "{opened}");
    tokio::time::sleep(Duration::from_millis(50)).await;
    for _ in 0..3 {
        let status = tokio::time::timeout(
            Duration::from_millis(750),
            shell.raw_call("status", json!({})),
        )
        .await
        .expect("same-connection status must remain responsive");
        assert_eq!(status["result"]["opening"], true, "{status}");
        assert_eq!(
            shell
                .raw_call("context", json!({"locked":false,"on_battery":true}))
                .await["result"]["opening"],
            true
        );
    }
    // A generation change unrelated to screen locking must not leave a stale
    // opening flag that prevents retries forever.
    let changed = shell
        .raw_call(
            "context",
            json!({"locked":false,"on_battery":true,"assistant_busy":true}),
        )
        .await;
    assert_eq!(changed["result"]["opening"], true, "{changed}");
    let locked = tokio::time::timeout(
        Duration::from_millis(750),
        shell.raw_call("context", json!({"locked":true})),
    )
    .await
    .expect("lock must not wait for migration");
    assert_eq!(locked["result"]["opening"], false);
    assert_eq!(locked["result"]["locked"], true);
    store.db.execute_batch("ROLLBACK;").unwrap();
    tokio::time::sleep(Duration::from_millis(100)).await;
    let stale = shell.raw_call("status", json!({})).await;
    assert_eq!(
        stale["result"]["locked"], true,
        "stale preparation must not reopen the index: {stale}"
    );
    assert_eq!(stale["result"]["opening"], false);
    let reopened = shell
        .call("context", json!({"locked":false,"on_battery":true}))
        .await;
    assert_eq!(reopened["result"]["locked"], false, "{reopened}");
    assert_eq!(reopened["result"]["opening"], false);
    assert_eq!(
        store
            .db
            .pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))
            .unwrap(),
        3
    );
    assert_eq!(
        secrets.count(),
        1,
        "repeated opens must reuse the index key"
    );
    assert_eq!(
        std::fs::read_to_string(note).unwrap(),
        "preserve this document"
    );
    child.kill().await.unwrap();
}

#[tokio::test]
async fn unlock_prunes_newly_excluded_environments_before_reporting_counts() {
    let bus = TestBus::start().unwrap();
    let _secrets = FakeSecrets::start(&bus).await.unwrap();
    let tmp = tempfile::tempdir().unwrap();
    let runtime = tmp.path().join("runtime");
    let data = tmp.path().join("data");
    let root = tmp.path().join("documents");
    let environment = root.join("python-tools");
    std::fs::create_dir_all(&environment).unwrap();
    std::fs::create_dir(&runtime).unwrap();
    std::fs::write(root.join("notes.md"), "useful notes").unwrap();
    std::fs::write(environment.join("package.py"), "package source").unwrap();
    let mut child = tokio::process::Command::new(env!("CARGO_BIN_EXE_velora-searchd"))
        .arg("serve")
        .env("DBUS_SESSION_BUS_ADDRESS", &bus.address)
        .env("XDG_RUNTIME_DIR", &runtime)
        .env("XDG_DATA_HOME", &data)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let mut shell = Client::connect(&runtime.join("velora-lens/search.sock")).await;
    assert_eq!(shell.call("attach", json!({})).await["ok"], true);
    shell
        .call("context", json!({"locked":false,"on_battery":true}))
        .await;
    assert_eq!(
        shell
            .call("configure", json!({"roots":[root],"media":false}))
            .await["ok"],
        true
    );
    shell.wait_index(false).await;
    assert_eq!(shell.call("status", json!({})).await["result"]["files"], 4);
    shell.call("context", json!({"locked":true})).await;
    std::fs::write(environment.join("pyvenv.cfg"), "home = /usr/bin").unwrap();
    let unlocked = shell
        .call("context", json!({"locked":false,"on_battery":true}))
        .await;
    assert_eq!(unlocked["result"]["files"], 2, "{unlocked}");
    assert_eq!(
        unlocked["result"]["pending"], 1,
        "excluded entries leave the extraction queue"
    );
    child.kill().await.unwrap();
}

#[tokio::test]
async fn fast_indexing_runs_during_activity_but_respects_battery_pause_and_lock() {
    accelerated_mode_checks("fast_indexing").await;
}

#[tokio::test]
async fn all_in_runs_during_activity_but_respects_battery_pause_and_lock() {
    accelerated_mode_checks("all_in").await;
}

async fn accelerated_mode_checks(mode: &str) {
    let bus = TestBus::start().unwrap();
    let _secrets = FakeSecrets::start(&bus).await.unwrap();
    let tmp = tempfile::tempdir().unwrap();
    let runtime = tmp.path().join("runtime");
    let data = tmp.path().join("data");
    let root = tmp.path().join("documents");
    std::fs::create_dir_all(&root).unwrap();
    std::fs::create_dir(&runtime).unwrap();
    std::fs::write(root.join("first.txt"), "first document").unwrap();
    std::fs::write(root.join("second.txt"), "second document").unwrap();
    let mut child = tokio::process::Command::new(env!("CARGO_BIN_EXE_velora-searchd"))
        .arg("serve")
        .env("DBUS_SESSION_BUS_ADDRESS", &bus.address)
        .env("XDG_RUNTIME_DIR", &runtime)
        .env("XDG_DATA_HOME", &data)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let mut shell = Client::connect(&runtime.join("velora-lens/search.sock")).await;
    assert_eq!(shell.call("attach", json!({})).await["ok"], true);
    shell
        .call(
            "context",
            json!({"locked":false,"on_battery":false,"idle":false}),
        )
        .await;
    let mut config = json!({"roots":[root],"media":false});
    assert_eq!(shell.call("configure", config.clone()).await["ok"], true);
    shell.wait_index(false).await;
    let normal = shell.call("status", json!({})).await["result"].clone();
    assert_eq!(
        normal["config"][mode], false,
        "old configs default to normal mode"
    );
    assert_eq!(
        normal["pending"], 2,
        "normal mode waits during user activity"
    );

    config[mode] = json!(true);
    config["paused"] = json!(true);
    assert_eq!(shell.call("configure", config.clone()).await["ok"], true);
    shell.wait_index(false).await;
    assert_eq!(
        shell.call("status", json!({})).await["result"]["pending"],
        2,
        "manual pause wins over fast mode"
    );

    shell
        .call(
            "context",
            json!({"locked":false,"on_battery":true,"idle":false}),
        )
        .await;
    config["paused"] = json!(false);
    shell.call("configure", config.clone()).await;
    shell.wait_index(false).await;
    assert_eq!(
        shell.call("status", json!({})).await["result"]["pending"],
        2,
        "fast mode still waits on battery"
    );
    shell.call("context", json!({"locked":true})).await;
    assert_eq!(
        shell.call("status", json!({})).await["result"]["locked"],
        true
    );
    let restored = shell
        .call(
            "context",
            json!({"locked":false,"on_battery":true,"idle":false}),
        )
        .await;
    assert_eq!(
        restored["result"]["config"][mode], true,
        "choice survives closing and reopening the encrypted store"
    );

    shell
        .call(
            "context",
            json!({"locked":false,"on_battery":false,"idle":false}),
        )
        .await;
    shell.wait_index(true).await;
    let fast = shell.call("status", json!({})).await["result"].clone();
    assert_eq!(fast["ready"], 3);
    assert_eq!(
        fast["idle"], false,
        "fast mode completes without an idle period"
    );
    assert_eq!(fast["failed"], 0);

    config[mode] = json!(false);
    shell.call("configure", config).await;
    shell.call("rescan", json!({})).await;
    shell.wait_index(false).await;
    assert_eq!(
        shell.call("status", json!({})).await["result"]["pending"],
        2,
        "turning fast mode off restores idle-only work"
    );
    shell
        .call(
            "context",
            json!({"locked":false,"on_battery":false,"idle":true}),
        )
        .await;
    shell.wait_index(true).await;
    child.kill().await.unwrap();
}

#[tokio::test]
async fn private_service_search_power_history_rename_exclude_and_lock() {
    let bus = TestBus::start().unwrap();
    let _secrets = FakeSecrets::start(&bus).await.unwrap();
    let tmp = tempfile::tempdir().unwrap();
    let runtime = tmp.path().join("runtime");
    let data = tmp.path().join("data");
    let root = tmp.path().join("documents");
    let project = root.join("SHAD");
    std::fs::create_dir_all(&project).unwrap();
    std::fs::create_dir(&runtime).unwrap();
    std::fs::write(
        project.join("notes.md"),
        "deep learning and neural networks privatecanary42",
    )
    .unwrap();
    std::fs::write(
        project.join("settings.yaml"),
        "bind: SUPER A\napi_key: do-not-index-this-secret",
    )
    .unwrap();
    std::fs::write(project.join(".env"), "private env credentials").unwrap();
    let mut child = tokio::process::Command::new(env!("CARGO_BIN_EXE_velora-searchd"))
        .arg("serve")
        .env("DBUS_SESSION_BUS_ADDRESS", &bus.address)
        .env("XDG_RUNTIME_DIR", &runtime)
        .env("XDG_DATA_HOME", &data)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let path = runtime.join("velora-lens/search.sock");
    let mut shell = Client::connect(&path).await;
    assert_eq!(
        shell.call("search", json!({"query":"private"})).await["ok"],
        false
    );
    assert_eq!(shell.call("unlock", json!({})).await["ok"], false);
    assert_eq!(shell.call("attach", json!({})).await["ok"], true);
    let unlocked = shell
        .call(
            "context",
            json!({"locked":false,"on_battery":true,"idle":true}),
        )
        .await;
    assert_eq!(unlocked["result"]["locked"], false, "{unlocked}");
    assert_eq!(shell.call("unlock", json!({})).await["ok"], true);
    let config = json!({"roots":[root],"activity":true,"media":false});
    assert_eq!(shell.call("configure", config.clone()).await["ok"], true);
    shell.wait_index(false).await;
    let progress = shell.call("status", json!({})).await["result"].clone();
    assert_eq!(progress["total_known"], true);
    assert!(progress["pending"].as_i64().unwrap() > 0);
    assert_eq!(
        progress["completed"].as_i64().unwrap() + progress["pending"].as_i64().unwrap(),
        progress["files"].as_i64().unwrap()
    );
    assert!(progress["current"].is_null(), "battery pauses content work");
    let names = shell.call("search", json!({"query":"шаад"})).await;
    assert_eq!(names["result"]["results"][0]["name"], "SHAD", "{names}");
    assert!(shell
        .call("search", json!({"query":"privatecanary42"}))
        .await["result"]["results"]
        .as_array()
        .unwrap()
        .is_empty());
    shell
        .call(
            "context",
            json!({"locked":false,"on_battery":false,"idle":true}),
        )
        .await;
    shell.wait_index(true).await;
    let progress = shell.call("status", json!({})).await["result"].clone();
    assert_eq!(progress["completed"], progress["files"]);
    assert_eq!(
        progress["ready"].as_i64().unwrap() + progress["failed"].as_i64().unwrap(),
        progress["completed"].as_i64().unwrap()
    );
    let semantic = shell.call("search", json!({"query":"папка DL"})).await;
    assert_eq!(
        semantic["result"]["results"][0]["name"], "SHAD",
        "{semantic}"
    );
    let query = json!({"query":"папка где я делал DL сегодня"});
    assert!(
        shell.call("search", query.clone()).await["result"]["results"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    shell
        .call(
            "record",
            json!({"path":project,"app":"terminal","source":"terminal"}),
        )
        .await;
    assert_eq!(
        shell.call("search", query.clone()).await["result"]["results"][0]["name"],
        "SHAD"
    );
    assert!(shell
        .call("search", json!({"query":"do not index this secret"}))
        .await["result"]["results"]
        .as_array()
        .unwrap()
        .is_empty());
    let moved = root.join("School");
    std::fs::rename(&project, &moved).unwrap();
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let found = shell.call("search", query.clone()).await;
            if found["result"]["results"][0]["name"] == "School" {
                break;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .unwrap();
    let mut excluded = config;
    excluded["excludes"] = json!([moved]);
    shell.call("configure", excluded).await;
    assert!(shell
        .call("search", json!({"query":"privatecanary42"}))
        .await["result"]["results"]
        .as_array()
        .unwrap()
        .is_empty());
    shell.call("apps", json!({"begin":true,"end":true,"items":[{"id":"paint-fixture.desktop","name":"Canvas","comment":"рисование карандашом"}]})).await;
    let apps = shell
        .call("search", json!({"query":"приложение карандашом"}))
        .await;
    assert_eq!(apps["result"]["results"][0]["name"], "Canvas", "{apps}");
    let progress = shell.call("status", json!({})).await["result"].clone();
    assert_eq!(progress["applications"], 1);
    assert_eq!(
        progress["files"].as_i64().unwrap(),
        progress["folder_stats"]["total"].as_i64().unwrap() + 1
    );
    shell
        .call(
            "configure",
            json!({"roots":[],"activity":true,"media":false}),
        )
        .await;
    let progress = shell.call("status", json!({})).await["result"].clone();
    assert_eq!(
        progress["applications"], 1,
        "apps remain searchable without folder access"
    );
    assert_eq!(
        progress["folder_stats"],
        json!({"total":0,"pending":0,"failed":0})
    );
    shell
        .call("apps", json!({"begin":true,"end":true,"items":[]}))
        .await;
    assert!(shell
        .call("search", json!({"query":"приложение карандашом"}))
        .await["result"]["results"]
        .as_array()
        .unwrap()
        .is_empty());
    shell.call("context", json!({"locked":true})).await;
    let progress = shell.call("status", json!({})).await["result"].clone();
    assert_eq!(progress["files"], 0);
    assert_eq!(progress["applications"], 0);
    assert_eq!(progress["folder_stats"]["total"], 0);
    assert!(
        progress["current"].is_null(),
        "lock clears the current filename"
    );
    assert_eq!(
        shell.call("search", json!({"query":"School"})).await["ok"],
        false
    );
    let mut other = Client::connect(&path).await;
    assert_eq!(
        other.call("context", json!({"locked":false})).await["ok"],
        false
    );
    shell.call("context", json!({"locked":false})).await;
    drop(shell);
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(
        other.call("status", json!({})).await["result"]["locked"],
        true
    );
    child.kill().await.unwrap();
    for entry in std::fs::read_dir(data.join("velora-lens"))
        .unwrap()
        .flatten()
    {
        if entry.path().is_file() {
            let bytes = std::fs::read(entry.path()).unwrap();
            assert!(!bytes
                .windows(b"privatecanary42".len())
                .any(|w| w == b"privatecanary42"));
        }
    }
}
