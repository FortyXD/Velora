use anyhow::{Context, Result};
use serde_json::Value;
use std::{
    path::{Path, PathBuf},
    process::Stdio,
    time::Duration,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    process::{Child, ChildStdin, ChildStdout, Command},
    sync::watch,
};

pub fn script() -> PathBuf {
    if let Some(path) = std::env::var_os("VELORA_LENS_WORKER") {
        return path.into();
    }
    let installed = PathBuf::from("/usr/share/velora/tools/velora-searchd/python/worker.py");
    if installed.is_file() {
        installed
    } else {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("python/worker.py")
    }
}

pub fn python() -> PathBuf {
    std::env::var_os("VELORA_LENS_PYTHON")
        .map(PathBuf::from)
        .unwrap_or_else(|| crate::data_dir().join("venv/bin/python"))
}

pub fn available_threads() -> usize {
    std::thread::available_parallelism().map_or(2, usize::from)
}

pub fn inference_threads(fast: bool, all_in: bool) -> usize {
    let available = available_threads();
    if all_in {
        available
    } else if fast {
        (available / 2).clamp(2, 8).min(available)
    } else {
        available.min(2)
    }
}

pub fn sandbox(mode: &str, file: Option<&Path>, threads: usize) -> Result<Command> {
    let threads = threads.clamp(1, available_threads()).to_string();
    let script = script()
        .canonicalize()
        .context("Lens worker is not installed")?;
    let py = python();
    anyhow::ensure!(py.is_file(), "Install the Lens model environment first");
    let mut cmd = Command::new("bwrap");
    cmd.args([
        "--die-with-parent",
        "--unshare-all",
        "--new-session",
        "--clearenv",
        "--proc",
        "/proc",
        "--dev",
        "/dev",
        "--tmpfs",
        "/tmp",
    ]);
    for path in ["/usr", "/lib", "/lib64", "/bin", "/etc/ld.so.cache"] {
        if Path::new(path).exists() {
            cmd.args(["--ro-bind", path, path]);
        }
    }
    // The private venv and models are the only home data exposed to inference.
    let environment = py
        .parent()
        .and_then(Path::parent)
        .context("Invalid Python environment")?;
    cmd.arg("--ro-bind").arg(environment).arg(environment);
    let models = crate::data_dir().join("models");
    if models.exists() {
        cmd.arg("--ro-bind").arg(&models).arg("/models");
    }
    cmd.arg("--ro-bind").arg(&script).arg("/worker.py");
    if let Some(file) = file {
        cmd.arg("--ro-bind").arg(file).arg("/input");
    }
    cmd.args([
        "--setenv",
        "PATH",
        "/usr/bin",
        "--setenv",
        "HOME",
        "/tmp",
        "--setenv",
        "HF_HUB_OFFLINE",
        "1",
        "--setenv",
        "OMP_NUM_THREADS",
        &threads,
        "--setenv",
        "VELORA_LENS_THREADS",
        &threads,
        "--setenv",
        "OPENBLAS_NUM_THREADS",
        "1",
        "--setenv",
        "PYTHONDONTWRITEBYTECODE",
        "1",
    ]);
    cmd.arg(py).args(["-I", "/worker.py", mode]);
    cmd.stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    Ok(cmd)
}

pub struct Worker {
    child: Child,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
    threads: usize,
}

impl Worker {
    pub fn start(threads: usize) -> Result<Self> {
        let mut child = sandbox("serve", None, threads)?
            .spawn()
            .context("Cannot start isolated Lens worker")?;
        Ok(Self {
            input: child.stdin.take().unwrap(),
            output: BufReader::new(child.stdout.take().unwrap()),
            child,
            threads,
        })
    }
    pub fn threads(&self) -> usize {
        self.threads
    }
    pub async fn call(
        &mut self,
        request: &Value,
        mut cancel: watch::Receiver<u64>,
    ) -> Result<Value> {
        let run = async {
            self.input
                .write_all(format!("{}\n", serde_json::to_string(request)?).as_bytes())
                .await?;
            let mut line = String::new();
            (&mut self.output)
                .take(32 * 1024 * 1024 + 1)
                .read_line(&mut line)
                .await?;
            anyhow::ensure!(
                line.len() <= 32 * 1024 * 1024,
                "Worker output exceeds limit"
            );
            let value: Value = serde_json::from_str(&line).context("Lens worker stopped")?;
            anyhow::ensure!(
                value.get("error").is_none(),
                "{}",
                value["error"].as_str().unwrap_or("Model failed")
            );
            Ok(value)
        };
        tokio::select! {
            result=tokio::time::timeout(Duration::from_secs(60),run)=>match result {Ok(result)=>result,Err(_)=>{let _=self.child.kill().await;anyhow::bail!("Model timeout")}},
            _=cancel.changed()=>{let _=self.child.kill().await;anyhow::bail!("Cancelled")}
        }
    }
}

pub async fn extract(
    path: &Path,
    kind: &str,
    offset: i64,
    threads: usize,
    mut cancel: watch::Receiver<u64>,
) -> Result<Value> {
    let mut child = sandbox("extract", Some(path), threads)?
        .arg(kind)
        .arg(offset.to_string())
        .spawn()?;
    child.stdin.take();
    let mut stdout = child.stdout.take().context("Missing extractor output")?;
    let run = async {
        let mut bytes = Vec::new();
        (&mut stdout)
            .take(32 * 1024 * 1024 + 1)
            .read_to_end(&mut bytes)
            .await?;
        anyhow::ensure!(
            bytes.len() <= 32 * 1024 * 1024,
            "Extraction output exceeds limit"
        );
        anyhow::ensure!(child.wait().await?.success(), "Extraction failed");
        Ok::<_, anyhow::Error>(bytes)
    };
    let bytes = tokio::select! {
        r=tokio::time::timeout(Duration::from_secs(120),run)=>r.context("Extraction timeout")??,
        _=cancel.changed()=>anyhow::bail!("Cancelled")
    };
    let result: Value = serde_json::from_slice(&bytes)?;
    anyhow::ensure!(result.get("error").is_none(), "Extraction failed");
    Ok(result)
}
