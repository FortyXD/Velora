use crate::subprocess::{interruptible, run};
use anyhow::{ensure, Context, Result};
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::ExitCode, time::Duration};
use tokio::process::Command;
pub fn select(files: Vec<String>) -> Result<()> {
    let paths = files
        .iter()
        .take(100)
        .map(std::path::absolute)
        .collect::<std::io::Result<Vec<_>>>()?;
    let status = std::process::Command::new("qs")
        .args([
            "-c",
            "ii",
            "ipc",
            "call",
            "assistant",
            "select",
            &serde_json::to_string(&paths)?,
        ])
        .status()?;
    ensure!(status.success(), "Could not send selection to the shell");
    Ok(())
}
async fn archive(args: &[String]) -> Result<PathBuf> {
    let (format, paths) = args
        .split_first()
        .context("Select files or folders to archive")?;
    ensure!(
        matches!(format.as_str(), "zip" | "tar.gz") && !paths.is_empty(),
        "Select files or folders to archive"
    );
    let paths = paths
        .iter()
        .map(std::path::absolute)
        .collect::<std::io::Result<Vec<_>>>()?;
    let first = &paths[0];
    let dir = first
        .parent()
        .context("Select files from the same folder")?;
    ensure!(
        paths
            .iter()
            .all(|p| p.parent() == Some(dir) && p.symlink_metadata().is_ok()),
        "Select existing files from the same folder"
    );
    let base = if paths.len() > 1 {
        "Archive"
    } else if first.is_dir() {
        first
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("Archive")
    } else {
        first
            .file_stem()
            .and_then(|n| n.to_str())
            .unwrap_or("Archive")
    };
    let temp = tempfile::Builder::new()
        .prefix(".folis-archive-")
        .suffix(&format!(".{format}"))
        .tempfile_in(dir)?;
    // libarchive preserves symbolic links and empty directories in both formats.
    run(Command::new("bsdtar")
        .current_dir(dir)
        .args(["-a", "-cf"])
        .arg(temp.path())
        .arg("--")
        .args(paths.iter().map(|p| p.file_name().unwrap())))
    .await?;
    temp.as_file()
        .set_permissions(fs::Permissions::from_mode(0o644))?;
    for n in 1..10000 {
        let suffix = if n == 1 {
            String::new()
        } else {
            format!(" ({n})")
        };
        let path = dir.join(format!("{base}{suffix}.{format}"));
        match fs::hard_link(temp.path(), &path) {
            Ok(()) => return Ok(path),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(e) => return Err(e.into()),
        }
    }
    anyhow::bail!("Could not choose a free archive name")
}
pub fn compress(args: Vec<String>) -> Result<ExitCode> {
    interruptible(
        async {
            let result = archive(&args).await;
            let (title, body) = match &result {
                Ok(p) => (
                    "Archive created",
                    p.file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .into_owned(),
                ),
                Err(e) => ("Archive creation failed", e.to_string()),
            };
            let _ = tokio::time::timeout(
                Duration::from_secs(3),
                run(Command::new("notify-send").args([title, &body])),
            )
            .await;
            println!("{}", result?.display());
            Ok(ExitCode::SUCCESS)
        },
        || {},
    )
}
