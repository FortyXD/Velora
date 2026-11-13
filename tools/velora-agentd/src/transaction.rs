//! Deterministic write-ahead journal; model output cannot approve or bypass it.
use crate::process;
use anyhow::{Context, Result};
use serde_json::{json, Value};

pub async fn call(operation: &str, mut params: Value) -> Result<Value> {
    params["operation"] = json!(operation);
    let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("python/transactions.py");
    let script = if source.is_file() {
        source
    } else {
        std::path::PathBuf::from("/usr/share/velora/tools/velora-agentd/python/transactions.py")
    };
    let bytes = process::output(
        "/usr/bin/python3",
        &["-I".into(), script.to_string_lossy().into_owned()],
        &serde_json::to_vec(&params)?,
        300,
        2 * 1024 * 1024,
    )
    .await?;
    let result: Value = serde_json::from_slice(&bytes).context("Invalid transaction response")?;
    if let Some(error) = result["error"].as_str() {
        anyhow::bail!("{error}");
    }
    Ok(result)
}

pub async fn check(path: &std::path::Path, directory: bool) -> Result<()> {
    call("check", json!({"path":path,"directory":directory})).await?;
    Ok(())
}

/// One executor owns the journal; startup recovery cannot undo another live daemon.
pub async fn lease() -> Result<std::fs::File> {
    use std::os::{fd::AsRawFd, unix::fs::OpenOptionsExt};
    let initialized = call("initialize", json!({})).await?;
    let path = std::path::Path::new(
        initialized["root"]
            .as_str()
            .context("No transaction directory")?,
    )
    .join("service.lock");
    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)?;
    anyhow::ensure!(
        unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0,
        "Another assistant executor is already active"
    );
    Ok(file)
}
