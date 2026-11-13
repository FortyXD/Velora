//! Every subprocess belongs to a task and dies with its future, including grandchildren.
use anyhow::{Context, Result};
use std::{process::Stdio, time::Duration};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    process::{Child, Command},
};

#[derive(Debug)]
pub struct ProcessExit(pub std::process::ExitStatus);
impl std::fmt::Display for ProcessExit {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Tool failed (exit {})", self.0.code().unwrap_or(-1))
    }
}
impl std::error::Error for ProcessExit {}

pub struct Running(Option<Child>);
impl std::ops::Deref for Running {
    type Target = Child;
    fn deref(&self) -> &Child {
        self.0.as_ref().unwrap()
    }
}
impl std::ops::DerefMut for Running {
    fn deref_mut(&mut self) -> &mut Child {
        self.0.as_mut().unwrap()
    }
}
impl Drop for Running {
    fn drop(&mut self) {
        if let Some(mut child) = self.0.take() {
            if let Some(pid) = child.id() {
                unsafe {
                    libc::kill(-(pid as i32), libc::SIGKILL);
                }
                let _ = child.start_kill();
                if let Ok(runtime) = tokio::runtime::Handle::try_current() {
                    runtime.spawn(async move {
                        let _ = child.wait().await;
                    });
                }
            }
        }
    }
}

pub fn spawn(command: &mut Command) -> Result<Running> {
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    // A private process group lets cancellation also stop shells, curl and their children.
    unsafe {
        command.pre_exec(|| {
            if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL) == -1 || libc::setpgid(0, 0) == -1
            {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    Ok(Running(Some(
        command
            .spawn()
            .context("Could not start the required desktop tool")?,
    )))
}

pub async fn output(
    program: &str,
    args: &[String],
    input: &[u8],
    seconds: u64,
    limit: usize,
) -> Result<Vec<u8>> {
    let mut cmd = Command::new(program);
    cmd.args(args);
    let mut child = spawn(&mut cmd)?;
    let mut stdin = child.stdin.take().context("Missing stdin")?;
    let mut stdout = child.stdout.take().context("Missing stdout")?;
    let run = async {
        let send = async move {
            stdin.write_all(input).await?;
            stdin.shutdown().await?;
            drop(stdin);
            Ok::<_, std::io::Error>(())
        };
        let read = async {
            let mut data = Vec::new();
            (&mut stdout)
                .take(limit as u64 + 1)
                .read_to_end(&mut data)
                .await?;
            anyhow::ensure!(data.len() <= limit, "Tool output exceeded its limit");
            Ok::<_, anyhow::Error>(data)
        };
        let (_, data) = tokio::try_join!(async { send.await.map_err(anyhow::Error::from) }, read)?;
        let status = child.wait().await?;
        if !status.success() {
            return Err(ProcessExit(status).into());
        }
        Ok(data)
    };
    tokio::time::timeout(Duration::from_secs(seconds), run)
        .await
        .context("Tool timed out")?
}

pub async fn json(
    program: &str,
    args: &[String],
    input: &serde_json::Value,
) -> Result<serde_json::Value> {
    let data = output(
        program,
        args,
        &serde_json::to_vec(input)?,
        60,
        2 * 1024 * 1024,
    )
    .await?;
    serde_json::from_slice(&data).context("Tool returned invalid data")
}

pub fn args(values: &[&str]) -> Vec<String> {
    values.iter().map(|s| (*s).into()).collect()
}

/// Bounded lines, including peers that never send a newline.
pub async fn line<R: tokio::io::AsyncBufRead + Unpin>(
    reader: &mut R,
    limit: usize,
) -> Result<Option<String>> {
    use tokio::io::AsyncBufReadExt;
    let mut value = String::new();
    let count = reader.take(limit as u64 + 1).read_line(&mut value).await?;
    anyhow::ensure!(count <= limit, "Protocol line exceeded its limit");
    Ok((count > 0).then_some(value))
}
