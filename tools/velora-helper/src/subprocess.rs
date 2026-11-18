//! Cancellable desktop jobs. Dropping a pending command stops its entire process group.
use anyhow::{bail, Context, Result};
use std::future::Future;
use std::process::{ExitCode, Stdio};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::signal::unix::{signal, SignalKind};

pub fn interruptible(
    job: impl Future<Output = Result<ExitCode>>,
    cancelled: impl FnOnce(),
) -> Result<ExitCode> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let result = runtime.block_on(async {
        let mut term = signal(SignalKind::terminate())?;
        let mut interrupt = signal(SignalKind::interrupt())?;
        tokio::select! {
            biased;
            _ = term.recv() => {}
            _ = interrupt.recv() => {}
            result = job => return result,
        }
        cancelled();
        Ok(ExitCode::from(130))
    });
    // A cancelled stdin reader can still be blocked waiting for its QML writer.
    runtime.shutdown_background();
    result
}

pub struct ChildGroup(pub Child);

impl ChildGroup {
    pub fn spawn(cmd: &mut Command) -> Result<Self> {
        let child = cmd
            .process_group(0)
            .kill_on_drop(true)
            .spawn()
            .with_context(|| {
                format!(
                    "Could not start {}",
                    cmd.as_std().get_program().to_string_lossy()
                )
            })?;
        Ok(Self(child))
    }
}

impl Drop for ChildGroup {
    fn drop(&mut self) {
        if let Some(pid) = self.0.id() {
            // SAFETY: this child heads the private group created by spawn and hasn't been reaped.
            unsafe {
                libc::kill(-(pid as i32), libc::SIGKILL);
            }
        }
    }
}

/// Deliver complete lines as they arrive. Keep only the last diagnostic on failure.
pub async fn stream(cmd: &mut Command, mut line: impl FnMut(bool, &str)) -> Result<()> {
    let program = cmd.as_std().get_program().to_string_lossy().into_owned();
    let mut child = ChildGroup::spawn(
        cmd.stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped()),
    )?;
    let mut stdout = BufReader::new(child.0.stdout.take().unwrap()).split(b'\n');
    let mut stderr = BufReader::new(child.0.stderr.take().unwrap()).split(b'\n');
    let (mut out, mut err) = (true, true);
    let mut diagnostic = String::new();
    while out || err {
        let (is_err, bytes) = tokio::select! {
            item = stdout.next_segment(), if out => (false, item?),
            item = stderr.next_segment(), if err => (true, item?),
        };
        if let Some(bytes) = bytes {
            let text = String::from_utf8_lossy(&bytes);
            let text = text.trim_end_matches('\r');
            if is_err && !text.is_empty() {
                diagnostic.clear();
                diagnostic.push_str(text);
            }
            line(is_err, text);
        } else if is_err {
            err = false;
        } else {
            out = false;
        }
    }
    let status = child.0.wait().await?;
    if !status.success() {
        if diagnostic.is_empty() {
            bail!("{program} failed ({status})");
        }
        bail!("{diagnostic}");
    }
    Ok(())
}

pub async fn run(cmd: &mut Command) -> Result<()> {
    stream(cmd, |_, _| {}).await
}

pub async fn output(cmd: &mut Command) -> Result<String> {
    let mut result = String::new();
    stream(cmd, |err, line| {
        if !err {
            result.push_str(line);
            result.push('\n');
        }
    })
    .await?;
    Ok(result)
}
