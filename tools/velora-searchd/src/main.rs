use anyhow::{Context, Result};
use serde_json::{json, Value};
use std::{
    io::Read,
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Duration,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::mpsc,
};
use velora_searchd::{
    config::Config,
    engine::{self, Engine},
};

fn private_directory(path: &Path) -> Result<()> {
    std::fs::create_dir_all(path)?;
    let metadata = std::fs::symlink_metadata(path)?;
    anyhow::ensure!(
        metadata.is_dir() && !metadata.file_type().is_symlink(),
        "Unsafe Lens directory"
    );
    let uid = std::fs::metadata("/proc/self")?.uid();
    anyhow::ensure!(
        metadata.uid() == uid,
        "Lens directory belongs to another user"
    );
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))?;
    Ok(())
}

fn socket_path() -> Result<PathBuf> {
    let runtime =
        PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR").context("XDG_RUNTIME_DIR is required")?);
    anyhow::ensure!(runtime.is_absolute(), "Invalid runtime directory");
    let dir = runtime.join("velora-lens");
    private_directory(&dir)?;
    Ok(dir.join("search.sock"))
}

async fn request(
    engine: &Arc<Engine>,
    method: &str,
    params: Value,
    controller: bool,
) -> Result<Value> {
    match method {
        "status" => Ok(engine.status()),
        "apps" => {
            anyhow::ensure!(controller, "Only the shell supplies desktop entries");
            engine.apps(
                &params["items"],
                params["begin"].as_bool().unwrap_or(false),
                params["end"].as_bool().unwrap_or(false),
            )?;
            Ok(json!({}))
        }
        "configure" => engine.configure(serde_json::from_value::<Config>(params)?),
        "review_source" => engine.review_source(
            Path::new(params["path"].as_str().context("Missing folder path")?),
            params["include"]
                .as_bool()
                .context("Choose whether to include the folder")?,
        ),
        "search" => {
            engine
                .search_explained(
                    params["query"].as_str().unwrap_or(""),
                    params["semantic"].as_bool().unwrap_or(false),
                    params["explain"].as_bool().unwrap_or(false),
                )
                .await
        }
        "cancel" => Ok(json!({})),
        "unlock" => {
            let generation = {
                let s = engine.state.lock().unwrap();
                anyhow::ensure!(!s.session_locked, "Unlock the desktop session first");
                s.generation
            };
            velora_searchd::secret::request_unlock().await?;
            {
                let s = engine.state.lock().unwrap();
                anyhow::ensure!(
                    !s.session_locked && s.generation == generation,
                    "Session changed during unlock"
                );
            }
            engine.schedule_unlock();
            Ok(engine.status())
        }
        "context" => {
            anyhow::ensure!(controller, "Only the attached shell controls session state");
            if params["locked"].as_bool().unwrap_or(true) {
                engine.lock();
            } else {
                {
                    let mut s = engine.state.lock().unwrap();
                    s.session_locked = false;
                    let battery = params["on_battery"].as_bool().unwrap_or(true);
                    let idle = params["idle"].as_bool().unwrap_or(false);
                    if s.config.indexing_allowed(s.battery, s.idle)
                        && !s.config.indexing_allowed(battery, idle)
                    {
                        s.generation += 1;
                        engine.cancel.send_replace(s.generation);
                    }
                    s.battery = battery;
                    s.idle = idle;
                    let busy = params["assistant_busy"].as_bool().unwrap_or(false);
                    if busy && !s.assistant_busy && s.active_searches == 0 {
                        s.generation += 1;
                        engine.cancel.send_replace(s.generation);
                    }
                    s.assistant_busy = busy;
                }
                engine.schedule_unlock();
            }
            engine.wake.notify_one();
            Ok(engine.status())
        }
        "record" => {
            let path = Path::new(params["path"].as_str().unwrap_or(""));
            engine.record(
                path,
                params["app"].as_str().unwrap_or(""),
                params["source"].as_str().unwrap_or(""),
            )?;
            Ok(json!({}))
        }
        "resolve" => Ok(serde_json::to_value(
            engine.validate_hit(params["id"].as_i64().context("Missing result ID")?)?,
        )?),
        "rescan" => {
            let mut s = engine.state.lock().unwrap();
            s.generation += 1;
            engine.cancel.send_replace(s.generation);
            s.budget_blocked = false;
            s.problem.clear();
            s.current_file = None;
            let config = s.config.clone();
            s.pending.extend(config.roots.clone());
            s.ann.clear();
            if let Some(db) = s.store.as_mut() {
                db.prune_excluded(&config)?;
                engine::refresh_model_revision(db)?;
                db.db.execute(
                    "UPDATE files SET state='pending',fingerprint='',offset=0",
                    [],
                )?;
            }
            drop(s);
            engine.wake.notify_one();
            Ok(json!({}))
        }
        _ => anyhow::bail!("Unknown Lens method"),
    }
}

async fn connection(
    stream: UnixStream,
    engine: Arc<Engine>,
    owner: Arc<AtomicU64>,
    connection_id: u64,
) -> Result<()> {
    let uid = std::fs::metadata("/proc/self")?.uid();
    anyhow::ensure!(
        stream.peer_cred()?.uid() == uid,
        "Peer is not the current user"
    );
    let (reader, mut writer) = stream.into_split();
    let (send, mut receive) = mpsc::channel::<Value>(32);
    let output = tokio::spawn(async move {
        while let Some(v) = receive.recv().await {
            if writer.write_all(format!("{v}\n").as_bytes()).await.is_err() {
                break;
            }
        }
    });
    send.send(json!({"type":"hello","protocol":1})).await?;
    let mut reader = BufReader::new(reader);
    let latest = Arc::new(AtomicU64::new(0));
    struct Disconnect {
        engine: Arc<Engine>,
        owner: Arc<AtomicU64>,
        latest: Arc<AtomicU64>,
        id: u64,
    }
    impl Drop for Disconnect {
        fn drop(&mut self) {
            self.latest.store(u64::MAX, Ordering::SeqCst);
            if self
                .owner
                .compare_exchange(self.id, 0, Ordering::SeqCst, Ordering::SeqCst)
                .is_ok()
            {
                self.engine.lock();
            }
        }
    }
    let _disconnect = Disconnect {
        engine: engine.clone(),
        owner: owner.clone(),
        latest: latest.clone(),
        id: connection_id,
    };
    let mut controller = false;
    let mut search_job: Option<tokio::task::JoinHandle<()>> = None;
    loop {
        let mut line = String::new();
        // Bound before allocating: a hostile same-user client must not grow daemon memory indefinitely.
        use tokio::io::AsyncReadExt;
        let n = (&mut reader).take(65537).read_line(&mut line).await?;
        if n == 0 || n > 65536 {
            break;
        }
        let Ok(v) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let id = v["id"].as_u64().unwrap_or(0);
        let method = v["method"].as_str().unwrap_or("").to_owned();
        if method == "attach" {
            controller = owner
                .compare_exchange(0, connection_id, Ordering::SeqCst, Ordering::SeqCst)
                .is_ok()
                || owner.load(Ordering::SeqCst) == connection_id;
            send.send(json!({"type":"response","id":id,"ok":controller,"result":{},"error":{"message":"A shell is already attached"}})).await?;
            continue;
        }
        if method == "search" || method == "cancel" {
            latest.store(id, Ordering::SeqCst);
            if let Some(job) = search_job.take() {
                job.abort();
            }
        }
        // Control requests are ordered on the connection. Searches may finish out of order.
        if method != "search" {
            let result = request(&engine, &method, v["params"].clone(), controller).await;
            let reply = match result {
                Ok(value) => json!({"type":"response","id":id,"ok":true,"result":value}),
                Err(e) => {
                    json!({"type":"response","id":id,"ok":false,"error":{"message":e.to_string()}})
                }
            };
            if send.send(reply).await.is_err() {
                break;
            }
            continue;
        }
        let e = engine.clone();
        let tx = send.clone();
        let current = latest.clone();
        search_job = Some(tokio::spawn(async move {
            if current.load(Ordering::SeqCst) != id {
                return;
            }
            let result = request(&e, &method, v["params"].clone(), false).await;
            if current.load(Ordering::SeqCst) != id {
                return;
            }
            let reply = match result {
                Ok(value) => json!({"type":"response","id":id,"ok":true,"result":value}),
                Err(_) => {
                    json!({"type":"response","id":id,"ok":false,"error":{"message":"Search unavailable"}})
                }
            };
            let _ = tx.send(reply).await;
        }));
    }
    latest.store(u64::MAX, Ordering::SeqCst);
    if let Some(job) = search_job {
        job.abort();
    }
    if owner
        .compare_exchange(connection_id, 0, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
    {
        engine.lock();
    }
    output.abort();
    Ok(())
}

async fn connect(autostart: bool) -> Result<UnixStream> {
    let socket = socket_path()?;
    if let Ok(stream) = UnixStream::connect(&socket).await {
        return Ok(stream);
    }
    anyhow::ensure!(autostart, "Lens is not running");
    let _ = tokio::process::Command::new("systemctl")
        .args(["--user", "start", "velora-searchd.service"])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .await;
    if let Ok(stream) = UnixStream::connect(&socket).await {
        return Ok(stream);
    }
    tokio::process::Command::new(std::env::current_exe()?)
        .arg("serve")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()?;
    for _ in 0..30 {
        tokio::time::sleep(Duration::from_millis(100)).await;
        if let Ok(stream) = UnixStream::connect(&socket).await {
            return Ok(stream);
        }
    }
    anyhow::bail!("Cannot start Lens service")
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let limit = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    // SAFETY: setrlimit reads this valid pointer and only changes the current process's core limit.
    anyhow::ensure!(
        unsafe { libc::setrlimit(libc::RLIMIT_CORE, &limit) } == 0,
        "Cannot disable core dumps"
    );
    let args: Vec<_> = std::env::args().collect();
    match args.get(1).map(String::as_str).unwrap_or("help") {
        "serve" => {
            private_directory(&velora_searchd::data_dir())?;
            let socket = socket_path()?;
            if socket.exists() {
                if UnixStream::connect(&socket).await.is_ok() {
                    return Ok(());
                }
                std::fs::remove_file(&socket)?;
            }
            let listener = UnixListener::bind(&socket)?;
            std::fs::set_permissions(&socket, std::fs::Permissions::from_mode(0o600))?;
            let engine = Engine::new();
            tokio::spawn(engine::background(engine.clone()));
            let owner = Arc::new(AtomicU64::new(0));
            let mut id = 0;
            loop {
                let (stream, _) = listener.accept().await?;
                id += 1;
                let e = engine.clone();
                let o = owner.clone();
                tokio::spawn(async move {
                    let _ = connection(stream, e, o, id).await;
                });
            }
        }
        "bridge" => {
            let stream = connect(true).await?;
            let (mut read, mut write) = stream.into_split();
            // Tokio stdin uses an uncancellable runtime worker. If the service
            // disconnects while QML keeps stdin open, runtime shutdown waits for
            // that worker forever and QML never receives onExited to reconnect.
            // A dedicated detached reader does not hold up process shutdown.
            let (sender, mut input) = mpsc::channel::<std::io::Result<Vec<u8>>>(8);
            std::thread::spawn(move || {
                let mut stdin = std::io::stdin().lock();
                let mut buffer = [0; 8192];
                loop {
                    match stdin.read(&mut buffer) {
                        Ok(0) => break,
                        Ok(n) => {
                            if sender.blocking_send(Ok(buffer[..n].to_vec())).is_err() {
                                break;
                            }
                        }
                        Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
                        Err(error) => {
                            let _ = sender.blocking_send(Err(error));
                            break;
                        }
                    }
                }
            });
            let mut output = tokio::io::stdout();
            let result = tokio::select! {
                result = async {
                    while let Some(chunk) = input.recv().await {
                        write.write_all(&chunk?).await?;
                    }
                    Ok::<_, std::io::Error>(())
                } => result,
                result = tokio::io::copy(&mut read, &mut output) => result.map(|_| ()),
            };
            output.flush().await?;
            result?;
            Ok(())
        }
        "record" => {
            // Shell hooks never start a daemon and never delay the prompt waiting for indexing.
            let Ok(mut stream) = connect(false).await else {
                return Ok(());
            };
            let path = std::env::current_dir()?;
            let message = json!({"id":1,"method":"record","params":{"path":path,"app":args.get(2).map(String::as_str).unwrap_or("terminal"),"source":"terminal"}});
            stream.write_all(format!("{message}\n").as_bytes()).await?;
            Ok(())
        }
        "status" => {
            let mut stream = connect(false).await?;
            stream
                .write_all(b"{\"id\":1,\"method\":\"status\",\"params\":{}}\n")
                .await?;
            let mut lines = BufReader::new(stream).lines();
            while let Some(line) = lines.next_line().await? {
                let v: Value = serde_json::from_str(&line)?;
                if v["id"] == 1 {
                    println!("{}", serde_json::to_string_pretty(&v["result"])?);
                    break;
                }
            }
            Ok(())
        }
        "install-models" => {
            let script = velora_searchd::worker::script().with_file_name("install.py");
            let status = tokio::process::Command::new("/usr/bin/python3")
                .arg(script)
                .status()
                .await?;
            anyhow::ensure!(status.success(), "Lens model installation failed");
            Ok(())
        }
        "check-models" => {
            let mut worker = velora_searchd::worker::Worker::start(
                velora_searchd::worker::inference_threads(false, false),
            )?;
            let (_cancel, receiver) = tokio::sync::watch::channel(0);
            let result = worker
                .call(
                    &json!({"method":"query","text":"папка с глубоким обучением","visual":true}),
                    receiver.clone(),
                )
                .await?;
            anyhow::ensure!(
                result["text"].as_array().is_some_and(|v| v.len() == 384),
                "Invalid text embedding"
            );
            anyhow::ensure!(
                result["visual"].as_array().is_some_and(|v| v.len() == 768),
                "Invalid visual embedding"
            );
            let ranked = worker.call(&json!({"method":"rerank", "text":"keyboard configuration",
                "documents":["Keyboard configuration: key bindings and input layout.", "A recipe for apple pie."]}), receiver).await?;
            anyhow::ensure!(
                ranked["available"] == true
                    && ranked["scores"].as_array().is_some_and(|s| s.len() == 2
                        && s[0].as_f64().zip(s[1].as_f64()).is_some_and(|(a, b)| a > b)),
                "Invalid reranker output"
            );
            println!("Offline model check passed: text=384, visual=768, reranker=ready");
            Ok(())
        }
        _ => {
            println!("Velora Lens\n  serve    Run the private search service\n  bridge   JSON-lines connection for Quickshell\n  status   Inspect search status\n  record   Record the current terminal directory\n\nEnable and configure Lens in Settings → Search. See docs/lens.md for model setup.");
            Ok(())
        }
    }
}
