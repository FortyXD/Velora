//! Runs the real daemon against stand-in services on a private bus.
#![allow(dead_code)]

use serde_json::{json, Value};
use std::process::Stdio;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, Lines};
use tokio::process::{Child, ChildStdin, ChildStdout, Command};
use velora_connectivity_fakes::bus::TestBus;

const WAIT: Duration = Duration::from_secs(10);

/// PATH with programs that act on this computer stood in for: the daemon turns the radio on with `rfkill`,
/// and a test has no business touching the real one. It logs its arguments next to itself.
pub fn safe_path() -> String {
    use std::os::unix::fs::PermissionsExt;
    static DIRECTORY: std::sync::OnceLock<std::path::PathBuf> = std::sync::OnceLock::new();
    let directory = DIRECTORY.get_or_init(|| {
        let directory = std::env::temp_dir().join(format!("velora-test-tools-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let rfkill = directory.join("rfkill");
        std::fs::write(&rfkill, format!("#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{}/rfkill.log'\n", directory.display())).unwrap();
        std::fs::set_permissions(&rfkill, std::fs::Permissions::from_mode(0o755)).unwrap();
        directory
    });
    format!("{}:{}", directory.display(), std::env::var("PATH").unwrap_or_default())
}

pub struct Daemon {
    pub child: Child,
    stdin: ChildStdin,
    lines: Lines<BufReader<ChildStdout>>,
    next_id: u64,
    /// Everything that came out, for checking what was and wasn't said
    pub transcript: Vec<String>,
    pub last_network: Value,
    events: Vec<Value>,
}

impl Daemon {
    pub async fn start(bus: &TestBus, arguments: &[&str]) -> Self {
        let mut child = Command::new(env!("CARGO_BIN_EXE_velora-connectivityd"))
            .args(arguments)
            .env("DBUS_SYSTEM_BUS_ADDRESS", &bus.address)
            .env("DBUS_SESSION_BUS_ADDRESS", &bus.address)
            .env("VELORA_NM_VPN_DIRS", "/nonexistent")
            .env("PATH", safe_path())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("the daemon starts");
        let stdin = child.stdin.take().expect("piped");
        let lines = BufReader::new(child.stdout.take().expect("piped")).lines();
        Self { child, stdin, lines, next_id: 0, transcript: Vec::new(), last_network: Value::Null, events: Vec::new() }
    }

    async fn next_message(&mut self) -> Value {
        let line = tokio::time::timeout(WAIT, self.lines.next_line())
            .await
            .expect("the daemon said something in time")
            .expect("its stdout stayed readable")
            .expect("it didn't exit");
        self.transcript.push(line.clone());
        let message: Value = serde_json::from_str(&line).expect("each line is JSON");
        if message["type"] == "snapshot" && message["domain"] == "network" {
            self.last_network = message["data"].clone();
        }
        message
    }

    pub async fn write_raw(&mut self, line: &str) {
        self.stdin.write_all(line.as_bytes()).await.unwrap();
        self.stdin.flush().await.unwrap();
    }

    pub async fn send(&mut self, method: &str, params: Value) -> u64 {
        self.next_id += 1;
        let id = self.next_id;
        let line = format!("{}\n", json!({ "id": id, "method": method, "params": params }));
        self.write_raw(&line).await;
        id
    }

    pub async fn wait_response(&mut self, id: u64) -> Value {
        loop {
            let message = self.next_message().await;
            if message["type"] == "response" && message["id"] == id {
                return message;
            }
        }
    }

    pub async fn call(&mut self, method: &str, params: Value) -> Value {
        let id = self.send(method, params).await;
        self.wait_response(id).await
    }

    /// Reads messages until `check` accepts the network state, whichever message that takes.
    pub async fn wait_network(&mut self, what: &str, check: impl Fn(&Value) -> bool) -> Value {
        let deadline = tokio::time::Instant::now() + WAIT;
        loop {
            if check(&self.last_network) {
                return self.last_network.clone();
            }
            assert!(tokio::time::Instant::now() < deadline, "timed out waiting for: {what}\nlast state: {:#}", self.last_network);
            let _ = tokio::time::timeout(Duration::from_millis(500), self.next_message()).await;
        }
    }

    pub async fn wait_message(&mut self, what: &str, check: impl Fn(&Value) -> bool) -> Value {
        let deadline = tokio::time::Instant::now() + WAIT;
        loop {
            assert!(tokio::time::Instant::now() < deadline, "timed out waiting for: {what}");
            if let Ok(message) = tokio::time::timeout(Duration::from_millis(500), self.next_message()).await {
                if check(&message) {
                    return message;
                }
            }
        }
    }

    pub async fn close_stdin(self) -> (std::process::ExitStatus, Vec<String>) {
        let Daemon { mut child, stdin, transcript, .. } = self;
        drop(stdin);
        let status = tokio::time::timeout(WAIT, child.wait()).await.expect("it exits when stdin closes").unwrap();
        (status, transcript)
    }
}

/// A fake program that records its arguments and stdin, for checking what the daemon hands to helpers.
pub struct FakeTools {
    pub directory: std::path::PathBuf,
}

impl FakeTools {
    pub fn new(names: &[&str]) -> Self {
        use std::os::unix::fs::PermissionsExt;
        let directory = std::env::temp_dir().join(format!("velora-fake-tools-{}-{:?}", std::process::id(), std::thread::current().id()));
        std::fs::create_dir_all(&directory).unwrap();
        for name in names {
            let path = directory.join(name);
            std::fs::write(&path, format!("#!/bin/sh\nprintf '%s\\n' \"$@\" > '{0}/{1}.args'\ncat > '{0}/{1}.stdin'\nprintf 'PNGDATA'\n", directory.display(), name)).unwrap();
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        Self { directory }
    }

    /// Replaces a tool with one that prints this and exits with this code.
    pub fn with_output(self, name: &str, stdout: &str, code: i32) -> Self {
        use std::os::unix::fs::PermissionsExt;
        let path = self.directory.join(name);
        std::fs::write(&path, format!("#!/bin/sh\nprintf '%s\\n' \"$@\" > '{0}/{1}.args'\nprintf '%s\\n' '{2}'\nprintf '%s\\n' '{2}' >&2\nexit {3}\n", self.directory.display(), name, stdout, code)).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        self
    }

    pub fn args(&self, name: &str) -> String {
        std::fs::read_to_string(self.directory.join(format!("{name}.args"))).unwrap()
    }

    pub fn stdin(&self, name: &str) -> String {
        std::fs::read_to_string(self.directory.join(format!("{name}.stdin"))).unwrap()
    }
}

impl Drop for FakeTools {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.directory);
    }
}

impl Daemon {
    /// Starts it with these programs found first, in place of the real ones.
    pub async fn start_with_tools(bus: &TestBus, tools: &FakeTools) -> Self {
        let path = format!("{}:{}", tools.directory.display(), safe_path());
        let mut child = Command::new(env!("CARGO_BIN_EXE_velora-connectivityd"))
            .env("DBUS_SYSTEM_BUS_ADDRESS", &bus.address)
            .env("DBUS_SESSION_BUS_ADDRESS", &bus.address)
            .env("VELORA_NM_VPN_DIRS", "/nonexistent")
            .env("PATH", path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("the daemon starts");
        let stdin = child.stdin.take().expect("piped");
        let lines = BufReader::new(child.stdout.take().expect("piped")).lines();
        Self { child, stdin, lines, next_id: 0, transcript: Vec::new(), last_network: Value::Null, events: Vec::new() }
    }
}

impl Daemon {
    /// Reads messages until `check` accepts the Bluetooth state.
    pub async fn wait_bluetooth(&mut self, what: &str, check: impl Fn(&Value) -> bool) -> Value {
        let deadline = tokio::time::Instant::now() + WAIT;
        let mut latest = Value::Null;
        loop {
            if check(&latest) {
                return latest;
            }
            assert!(tokio::time::Instant::now() < deadline, "timed out waiting for: {what}\nlast state: {latest:#}");
            if let Ok(message) = tokio::time::timeout(Duration::from_millis(500), self.next_message()).await {
                if message["type"] == "snapshot" && message["domain"] == "bluetooth" {
                    latest = message["data"].clone();
                }
            }
        }
    }

    /// Starts it with its state directory and home in the given place.
    pub async fn start_in(bus: &TestBus, home: &std::path::Path, arguments: &[&str], rfkill: Option<&std::path::Path>) -> Self {
        let mut command = Command::new(env!("CARGO_BIN_EXE_velora-connectivityd"));
        command
            .args(arguments)
            .env("DBUS_SYSTEM_BUS_ADDRESS", &bus.address)
            .env("DBUS_SESSION_BUS_ADDRESS", &bus.address)
            .env("VELORA_NM_VPN_DIRS", "/nonexistent")
            .env("PATH", safe_path())
            .env("HOME", home)
            .env("XDG_STATE_HOME", home.join("state"))
            .env("XDG_CACHE_HOME", home.join("cache"))
            .env("XDG_DATA_HOME", home.join("data"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if let Some(rfkill) = rfkill {
            command.env("VELORA_RFKILL_DIR", rfkill);
        }
        let mut child = command.spawn().expect("the daemon starts");
        let stdin = child.stdin.take().expect("piped");
        let lines = BufReader::new(child.stdout.take().expect("piped")).lines();
        Self { child, stdin, lines, next_id: 0, transcript: Vec::new(), last_network: Value::Null, events: Vec::new() }
    }
}

/// An empty directory for one test, removed afterwards.
pub struct TempHome {
    pub path: std::path::PathBuf,
}

impl TempHome {
    pub fn new(name: &str) -> Self {
        let path = std::env::temp_dir().join(format!("velora-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).unwrap();
        Self { path }
    }
}

impl Drop for TempHome {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}
