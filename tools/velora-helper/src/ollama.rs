//! Own the local model server and release its model runners when the sidebar stops it.
use crate::subprocess::ChildGroup;
use anyhow::Result;
use std::{
    path::PathBuf,
    process::{ExitCode, Stdio},
    time::Duration,
};
use tokio::{
    process::Command,
    signal::unix::{signal, SignalKind},
};

pub fn run(args: Vec<String>) -> Result<ExitCode> {
    if crate::apps::which("ollama").is_none() {
        return Ok(ExitCode::from(127));
    }
    let gpu = args == ["gpu"];
    let mut cmd = Command::new("bwrap");
    cmd.args(["--die-with-parent", "--unshare-pid", "--bind", "/", "/", "--proc", "/proc"]);
    if gpu { cmd.args(["--dev-bind", "/dev", "/dev"]); }
    else { cmd.args(["--dev", "/dev"]); }
    cmd.args(["--", "ollama"]);
    cmd.arg("serve").envs([
        ("OLLAMA_HOST", if gpu { "127.0.0.1:11434" } else { "127.0.0.1:11435" }),
        ("OLLAMA_NO_CLOUD", "1"),
        ("OLLAMA_NOPRUNE", "1"),
        ("OLLAMA_NUM_PARALLEL", "1"),
        ("OLLAMA_MAX_LOADED_MODELS", "1"),
    ]);
    if args != ["gpu"] {
        cmd.envs([
            ("CUDA_VISIBLE_DEVICES", "-1"),
            ("ROCR_VISIBLE_DEVICES", "-1"),
            ("OLLAMA_VULKAN", "0"),
        ]);
    }
    if std::env::var_os("OLLAMA_MODELS").is_none_or(|s| s.is_empty()) {
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        if let Some(p) = [
            home.join(".ollama/models"),
            "/var/lib/ollama".into(),
            "/usr/share/ollama/.ollama/models".into(),
        ]
        .into_iter()
        .find(|p| p.join("manifests").is_dir())
        {
            cmd.env("OLLAMA_MODELS", p);
        }
    }
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(serve(cmd))
}

async fn serve(mut cmd: Command) -> Result<ExitCode> {
    let mut terminate = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut child = ChildGroup::spawn(
        cmd.stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null()),
    )?;
    tokio::select! {
        _ = terminate.recv() => {}
        _ = interrupt.recv() => {}
        status = child.0.wait() => return Ok(ExitCode::from(status?.code().unwrap_or(1) as u8)),
    }
    if let Some(pid) = child.0.id() {
        // SAFETY: the live child is the leader of the private group created above.
        unsafe { libc::kill(-(pid as i32), libc::SIGTERM) };
    }
    let _ = tokio::time::timeout(Duration::from_secs(3), child.0.wait()).await;
    Ok(ExitCode::SUCCESS)
}
