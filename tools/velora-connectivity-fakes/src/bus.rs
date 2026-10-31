//! A private message bus for one test.

use anyhow::{anyhow, Context};
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::sync::OnceLock;
use std::process::{Child, Command, Stdio};
use zbus::Connection;

const CONFIG: &str = r#"<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
"#;

/// Written once per test process, since tests start buses side by side.
fn private_config() -> anyhow::Result<String> {
    static WRITTEN: OnceLock<PathBuf> = OnceLock::new();
    if let Some(path) = WRITTEN.get() {
        return Ok(path.display().to_string());
    }
    let path = std::env::temp_dir().join(format!("velora-test-bus-{}.conf", std::process::id()));
    let staged = path.with_extension(format!("{:?}", std::thread::current().id()).replace(|c: char| !c.is_alphanumeric(), ""));
    std::fs::write(&staged, CONFIG)?;
    std::fs::rename(&staged, &path)?;
    Ok(WRITTEN.get_or_init(|| path).display().to_string())
}

/// Lives as long as the value; dropping it stops the bus.
pub struct TestBus {
    daemon: Child,
    pub address: String,
}

impl TestBus {
    pub fn start() -> anyhow::Result<Self> {
        // The fixed path skips other installs in PATH, which may lack a usable session configuration
        let program = if std::path::Path::new("/usr/bin/dbus-daemon").exists() { "/usr/bin/dbus-daemon" } else { "dbus-daemon" };
        // A configuration of its own: the standard ones also start real services on demand
        let mut daemon = Command::new(program)
            .args([&format!("--config-file={}", private_config()?), "--nofork", "--print-address"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .with_context(|| format!("couldn't start {program}"))?;
        let stdout = daemon.stdout.take().ok_or_else(|| anyhow!("no stdout from dbus-daemon"))?;
        let mut address = String::new();
        BufReader::new(stdout).read_line(&mut address)?;
        let address = address.trim().to_string();
        if address.is_empty() {
            return Err(anyhow!("dbus-daemon gave no address"));
        }
        Ok(Self { daemon, address })
    }

    pub async fn connect(&self) -> anyhow::Result<Connection> {
        Ok(zbus::conn::Builder::address(self.address.as_str()).build().await?)
    }
}

impl Drop for TestBus {
    fn drop(&mut self) {
        let _ = self.daemon.kill();
        let _ = self.daemon.wait();
    }
}
