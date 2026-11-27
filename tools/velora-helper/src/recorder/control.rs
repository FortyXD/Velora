use super::{audio, default_directory, identity, read_state, status};
use crate::{apps::which, args::Args, subprocess};
use anyhow::{anyhow, bail, ensure, Context, Result};
use rustix::{
    fs::{flock, FlockOperation},
    io::Errno,
    process::{pidfd_open, pidfd_send_signal, Pid, PidfdFlags, Signal},
};
use serde_json::{json, Value};
use std::{
    fs::{self, OpenOptions},
    io::{Read, Seek},
    os::{
        fd::OwnedFd,
        unix::{
            fs::DirBuilderExt,
            process::{CommandExt, ExitStatusExt},
        },
    },
    path::{Path, PathBuf},
    process::{ExitCode, ExitStatus, Stdio},
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{
    io::{unix::AsyncFd, AsyncReadExt, AsyncWriteExt},
    process::{Child, Command},
    signal::unix::{signal, SignalKind},
    sync::watch,
    time::timeout,
};

pub(super) async fn command(program: &str, args: &[&str]) -> Result<String> {
    Ok(timeout(
        Duration::from_secs(5),
        subprocess::output(Command::new(program).args(args)),
    )
    .await
    .context("Command timed out")??
    .trim()
    .into())
}

async fn hot_corners(action: &str) {
    let config = std::env::var("qsConfig")
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "ii".into());
    let mut ipc = Command::new("qs");
    ipc.args(["-c", &config, "ipc", "call", "hotCorners", action])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    let _ = timeout(Duration::from_secs(3), ipc.status()).await;
}

pub(super) struct Options {
    mode: String,
    audio: String,
    pub system: String,
    pub mic: String,
    quality: String,
    format: String,
    fps: u32,
    delay: u32,
    folder: PathBuf,
}
impl Options {
    async fn read(path: &Path) -> Result<Self> {
        let config: Value = match fs::read(path) {
            Ok(s) => serde_json::from_slice(&s).context("Invalid recording configuration")?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => json!({}),
            Err(e) => return Err(e.into()),
        };
        let data = config.get("screenRecord");
        ensure!(
            config.is_object() && data.is_none_or(Value::is_object),
            "Invalid recording configuration: screenRecord must be an object"
        );
        let data = &config["screenRecord"];
        let string = |k: &str, default: &str| -> Result<String> {
            let s = if data[k].is_null() {
                default
            } else {
                data[k]
                    .as_str()
                    .with_context(|| format!("Invalid recording setting: {k}"))?
            };
            ensure!(!s.contains('\0'), "Invalid recording setting: {k}");
            Ok(s.into())
        };
        let choice = |k: &str, choices: &[&str]| -> Result<String> {
            let s = string(k, choices[0])?;
            ensure!(
                choices.contains(&s.as_str()),
                "Invalid recording setting: {k}"
            );
            Ok(s)
        };
        let number = |k: &str, values: &[u64]| -> Result<u32> {
            let n = if data[k].is_null() {
                Some(values[0])
            } else {
                data[k].as_u64()
            };
            Ok(n.filter(|v| values.contains(v))
                .with_context(|| format!("Invalid recording setting: {k}"))? as u32)
        };
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        let folder = string("savePath", "")?;
        let folder = if folder.is_empty() {
            command("xdg-user-dir", &["VIDEOS"])
                .await
                .ok()
                .map(PathBuf::from)
                .filter(|p| p.is_absolute() && *p != home)
                .unwrap_or_else(|| home.join("Videos"))
        } else if let Some(rest) = folder.strip_prefix("~/") {
            home.join(rest)
        } else if folder == "~" {
            home
        } else {
            folder.into()
        };
        ensure!(
            folder.is_absolute(),
            "Recording folder must be an absolute path"
        );
        Ok(Self {
            mode: choice("mode", &["region", "screen"])?,
            audio: choice("audio", &["system", "none", "microphone", "both"])?,
            quality: choice("quality", &["balanced", "high", "small"])?,
            format: choice("format", &["mp4", "mkv"])?,
            fps: number("fps", &[30, 60])?,
            delay: number("delay", &[0, 3, 5, 10])?,
            folder,
            system: string("systemSource", "")?,
            mic: string("microphoneSource", "")?,
        })
    }
}

async fn monitor(output: Option<&str>) -> Result<Option<String>> {
    let data: Value = serde_json::from_str(&command("hyprctl", &["monitors", "-j"]).await?)?;
    let monitors: Vec<_> = data
        .as_array()
        .context("Missing monitor information")?
        .iter()
        .filter(|m| m["disabled"] != true)
        .collect();
    ensure!(
        !monitors.iter().any(|m| m["solitaryBlockedBy"]
            .as_array()
            .is_some_and(|a| a.iter().any(|p| p == "LOCK"))),
        "Screen is locked; unlock before recording"
    );
    let selected: Vec<_> = monitors
        .iter()
        .filter(|m| output.is_none_or(|s| m["name"] == s))
        .collect();
    ensure!(
        selected.is_empty() || selected.iter().any(|m| m["dpmsStatus"] != false),
        "Recording monitor is powered off (DPMS); wake it before recording"
    );
    Ok(monitors
        .iter()
        .find(|m| m["focused"] == true)
        .and_then(|m| m["name"].as_str())
        .map(str::to_owned))
}

pub(super) fn matching_pid(pid: &Value, token: &Value) -> Result<Option<AsyncFd<OwnedFd>>> {
    let Some(pid_number) = pid
        .as_i64()
        .and_then(|p| i32::try_from(p).ok())
        .and_then(Pid::from_raw)
    else {
        return Ok(None);
    };
    let fd = match pidfd_open(pid_number, PidfdFlags::empty()) {
        Ok(fd) => fd,
        Err(Errno::SRCH) => return Ok(None),
        Err(e) => return Err(e.into()),
    };
    if token.is_null() || identity(pid).as_deref() != token.as_str() {
        return Ok(None);
    }
    // SAFETY: the owned pidfd stays open for the entire registration and is used only for readiness.
    Ok(Some(unsafe { AsyncFd::register(fd) }?))
}
async fn stop_owner(dir: &Path) -> Result<bool> {
    let current = Value::Object(status(dir));
    if current["orphaned"] == true
        || !matches!(
            current["state"].as_str(),
            Some("countdown" | "selecting" | "starting" | "recording" | "stopping")
        )
    {
        return Ok(false);
    }
    if let Some(fd) = matching_pid(&current["pid"], &current["identity"])? {
        return match pidfd_send_signal(fd.get_ref(), Signal::TERM) {
            Ok(()) => Ok(true),
            Err(Errno::SRCH) => Ok(false),
            Err(e) => Err(e.into()),
        };
    }
    Ok(false)
}

fn death_guard(parent: i32, sig: i32) -> std::io::Result<()> {
    // Only async-signal-safe system calls run between fork and exec.
    unsafe {
        if libc::prctl(libc::PR_SET_PDEATHSIG, sig) < 0 {
            return Err(std::io::Error::last_os_error());
        }
        if libc::getppid() != parent {
            libc::_exit(1);
        }
    }
    Ok(())
}
pub fn gate(args: Vec<String>) -> Result<()> {
    ensure!(args.len() >= 3, "invalid recorder gate");
    let parent = args[0].parse::<i32>()?;
    let sig = if args[1] == "recorder" {
        libc::SIGINT
    } else {
        libc::SIGTERM
    };
    let mut byte = [0];
    std::io::stdin().read_exact(&mut byte)?;
    ensure!(byte == *b"G", "gate closed");
    unsafe {
        libc::signal(sig, libc::SIG_DFL);
    }
    death_guard(parent, sig)?;
    Err(std::process::Command::new(&args[2])
        .args(&args[3..])
        .exec()
        .into())
}

#[derive(Default)]
struct Logs {
    tail: Vec<u8>,
    ready: bool,
}
pub(super) struct Owner {
    pub dir: PathBuf,
    pub state: Value,
    child: Option<Child>,
    logs: Arc<Mutex<Logs>>,
    saved: String,
    cancel: watch::Receiver<bool>,
}

impl Owner {
    pub fn persist(&self) -> Result<()> {
        let mut tmp = tempfile::Builder::new()
            .prefix(".state-")
            .tempfile_in(&self.dir)?;
        serde_json::to_writer(&mut tmp, &self.state)?;
        tmp.persist(self.dir.join("state.json"))?;
        Ok(())
    }
    fn publish(&mut self, phase: &str) -> Result<()> {
        self.state["state"] = json!(phase);
        self.persist()
    }

    async fn launch(&mut self, cmd: &[String], kind: &str, out: Stdio, err: Stdio) -> Result<()> {
        let parent = std::process::id() as i32;
        let mut gate = Command::new(std::env::current_exe()?);
        gate.args(["recorder-child-gate", &parent.to_string(), kind])
            .args(cmd)
            .stdin(Stdio::piped())
            .stdout(out)
            .stderr(err);
        unsafe {
            gate.pre_exec(move || death_guard(parent, libc::SIGKILL));
        }
        let child = gate.spawn()?;
        let pid = json!(child.id().context("missing child PID")?);
        self.child = Some(child);
        self.state["childIdentity"] = json!(identity(&pid).context("child gate exited")?);
        self.state["childPid"] = pid;
        self.state["childKind"] = json!(kind);
        self.persist()?;
        self.child
            .as_mut()
            .unwrap()
            .stdin
            .take()
            .unwrap()
            .write_all(b"G")
            .await?;
        Ok(())
    }

    async fn terminate(&mut self, owned: bool) -> Result<()> {
        let Some(fd) = matching_pid(&self.state["childPid"], &self.state["childIdentity"])? else {
            return Ok(());
        };
        let recorder = self.state["childKind"] == "recorder";
        let initialized = || {
            self.logs.lock().unwrap().ready
                || self.state["encoderInitialized"] == true
                || self.state["startedAt"].as_f64().unwrap_or_default() > 0.
                || self.state["file"]
                    .as_str()
                    .is_some_and(|p| fs::metadata(p).is_ok_and(|m| m.len() > 0))
        };
        for (n, sig) in [
            if recorder { Signal::INT } else { Signal::TERM },
            Signal::TERM,
            Signal::KILL,
        ]
        .into_iter()
        .enumerate()
        {
            if n == 2 && recorder && (!owned || initialized()) {
                bail!("Recorder is not responding; initialization is uncertain, file and ownership retained. Press Stop to retry");
            }
            match pidfd_send_signal(fd.get_ref(), sig) {
                Ok(()) => {}
                Err(Errno::SRCH) => return Ok(()),
                Err(e) => return Err(e.into()),
            }
            if timeout(Duration::from_secs(2), fd.readable())
                .await
                .ok()
                .transpose()?
                .is_some()
            {
                return Ok(());
            }
            if recorder && n == 0 && initialized() {
                ensure!(timeout(Duration::from_secs(13),fd.readable()).await.ok().transpose()?.is_some(),"Recorder is still finalizing/not responding; file and ownership retained. Press Stop to retry");
                return Ok(());
            }
        }
        bail!("Recorder could not be stopped; ownership retained. Press Stop to retry")
    }

    async fn select(&mut self) -> Result<Option<String>> {
        self.publish("selecting")?;
        hot_corners("block").await;
        let result = self.select_region().await;
        hot_corners("unblock").await;
        result
    }

    async fn select_region(&mut self) -> Result<Option<String>> {
        self.launch(
            &["slurp".into()],
            "selector",
            Stdio::piped(),
            Stdio::piped(),
        )
        .await?;
        let child = self.child.as_mut().unwrap();
        let (mut out, mut err) = (child.stdout.take().unwrap(), child.stderr.take().unwrap());
        let (mut geom, mut message) = (String::new(), String::new());
        let result = tokio::select! {
            r=async{let (status,_,_)=tokio::try_join!(child.wait(),out.read_to_string(&mut geom),err.read_to_string(&mut message))?;Ok::<_,std::io::Error>(status)}=>Some(r?),
            _=cancelled(&mut self.cancel)=>None,
        };
        if let Some(s) = result {
            ensure!(
                s.success() || message.trim().is_empty(),
                "Region selection failed: {}",
                message.trim()
            );
            return Ok(s
                .success()
                .then(|| geom.trim().to_owned())
                .filter(|s| !s.is_empty()));
        }
        self.terminate(true).await?;
        self.child.as_mut().unwrap().wait().await?;
        Ok(None)
    }

    async fn record(&mut self, mut opts: Options, args: &Args) -> Result<()> {
        ensure!(
            which("wf-recorder").is_some(),
            "wf-recorder is not installed"
        );
        ensure!(
            which("ffprobe").is_some(),
            "ffprobe is not installed (install ffmpeg)"
        );
        if args.flag("fullscreen") {
            opts.mode = "screen".into();
        } else if args.value("region").is_some() || args.flag("select-region") {
            opts.mode = "region".into();
        }
        if args.flag("mic") {
            opts.audio = "both".into();
        } else if args.flag("sound") {
            opts.audio = "system".into();
        } else if args.flag("silent") {
            opts.audio = "none".into();
        }
        if opts.audio == "both" {
            audio::source(&opts, "system").await?;
            audio::source(&opts, "microphone").await?;
        } else {
            audio::source(&opts, &opts.audio).await?;
        }
        let focused = monitor(None).await?;
        let mut region = args.value("region").map(str::to_owned);
        let mut output = None;
        if opts.mode == "screen" {
            let name = focused.context("No focused monitor is available")?;
            monitor(Some(&name)).await?;
            output = Some(name);
        } else if region.is_none() {
            region = self.select().await?;
            if region.is_none() {
                return Ok(());
            }
        }
        if let Some(g) = &region {
            ensure!(
                regex::Regex::new(r"^-?[0-9]+,-?[0-9]+ [1-9][0-9]*x[1-9][0-9]*$")?.is_match(g),
                "Invalid recording region"
            );
        }
        fs::create_dir_all(&opts.folder)?;
        let prefix = chrono::Local::now()
            .format("recording_%Y-%m-%d_%H.%M.%S_")
            .to_string();
        let (_, file) = tempfile::Builder::new()
            .prefix(&prefix)
            .suffix(&format!(".{}", opts.format))
            .tempfile_in(&opts.folder)?
            .keep()?;
        self.state["file"] = json!(file);
        self.state["remaining"] = json!(opts.delay);
        self.publish("countdown")?;
        if opts.delay > 0 {
            notify(
                "Recording countdown",
                &format!(
                    "{} s — press the recording button again to cancel",
                    opts.delay
                ),
                opts.delay * 1000,
            )
            .await;
        }
        for left in (1..=opts.delay).rev() {
            self.state["remaining"] = json!(left);
            self.persist()?;
            tokio::select! {_=cancelled(&mut self.cancel)=>return Ok(()),_=tokio::time::sleep(Duration::from_secs(1))=>{}}
        }
        tokio::select! {_=cancelled(&mut self.cancel)=>return Ok(()),_=tokio::time::sleep(Duration::from_millis(250))=>{}}
        monitor(output.as_deref()).await?;
        let source = if opts.audio == "both" {
            Some(self.mix(&opts).await?)
        } else {
            audio::source(&opts, &opts.audio).await?
        };
        if *self.cancel.borrow() {
            return Ok(());
        }
        let crf = match opts.quality.as_str() {
            "high" => "crf=18",
            "small" => "crf=28",
            _ => "crf=23",
        };
        let mut cmd: Vec<String> = [
            "wf-recorder",
            "-y",
            "--no-damage",
            "--pixel-format",
            "yuv420p",
            "-c",
            "libx264",
            "-p",
            "preset=veryfast",
            "-p",
            crf,
            "-r",
            &opts.fps.to_string(),
            "-F",
            "pad=ceil(iw/2)*2:ceil(ih/2)*2",
            "-f",
            file.to_str().context("invalid path")?,
        ]
        .map(str::to_owned)
        .into();
        if let Some(name) = output {
            cmd.extend(["-o".into(), name]);
        } else {
            cmd.extend(["--geometry".into(), region.unwrap()]);
        }
        if let Some(src) = source {
            cmd.extend([format!("--audio={src}"), "-C".into(), "aac".into()]);
        }
        self.state["remaining"] = json!(0);
        self.publish("starting")?;
        let (mut reader, writer) = std::io::pipe()?;
        self.launch(&cmd, "recorder", writer.try_clone()?.into(), writer.into())
            .await?;
        let logs = self.logs.clone();
        let (ready_tx, mut ready) = watch::channel(false);
        std::thread::spawn(move || {
            let mut buf = [0; 4096];
            let video = regex::bytes::Regex::new(r"Stream #0:[0-9]+[^\n]*Video:").unwrap();
            while let Ok(n) = reader.read(&mut buf) {
                if n == 0 {
                    break;
                }
                let mut l = logs.lock().unwrap();
                l.tail.extend_from_slice(&buf[..n]);
                if !l.ready
                    && l.tail.windows(10).any(|w| w == b"Output #0,")
                    && video.is_match(&l.tail)
                {
                    l.ready = true;
                    let _ = ready_tx.send(true);
                }
                let trim = l.tail.len().saturating_sub(16384);
                l.tail.drain(..trim);
            }
        });
        let startup = tokio::time::sleep(Duration::from_secs(15));
        tokio::pin!(startup);
        let mut initialized = false;
        let mut read_logs = true;
        let status: Option<ExitStatus> = loop {
            tokio::select! {biased;
                _=cancelled(&mut self.cancel)=>break None,
                r=ready.changed(),if !initialized&&read_logs=>{
                    if r.is_err(){read_logs=false;}else if *ready.borrow(){initialized=true;self.state["startedAt"]=json!(SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis() as u64);self.state["encoderInitialized"]=json!(true);self.publish("recording")?;}
                }
                status=self.child.as_mut().unwrap().wait()=>break Some(status?),
                _=&mut startup,if !initialized=>bail!("Recorder did not initialize within 15 seconds (screen may be locked or powered off)"),
            }
        };
        if let Some(s) = status {
            bail!("Recorder exited unexpectedly (exit {s})");
        }
        self.publish("stopping")?;
        self.terminate(true).await?;
        let status = self.child.as_mut().unwrap().wait().await?;
        ensure!(
            status.success() || status.signal() == Some(libc::SIGINT),
            "Recorder exited unexpectedly ({status})"
        );
        self.verify("Recorded").await
    }

    async fn verify(&mut self, which: &str) -> Result<()> {
        let path = self.state["file"].as_str().unwrap_or("");
        if fs::metadata(path).is_ok_and(|m| m.len() > 0) {
            ensure!(
                command(
                    "ffprobe",
                    &[
                        "-v",
                        "error",
                        "-select_streams",
                        "v:0",
                        "-show_entries",
                        "stream=codec_type",
                        "-of",
                        "csv=p=0",
                        path
                    ]
                )
                .await?
                    == "video",
                "{which} file has no valid video stream: {path}"
            );
            self.saved = path.into();
        }
        Ok(())
    }
}

async fn cancelled(rx: &mut watch::Receiver<bool>) {
    if !*rx.borrow() {
        let _ = rx.changed().await;
    }
}
async fn notify(title: &str, body: &str, expiry: u32) {
    let _ = timeout(
        Duration::from_secs(3),
        subprocess::run(Command::new("notify-send").args([
            "-a",
            "Recorder",
            "-t",
            &expiry.to_string(),
            title,
            body,
        ])),
    )
    .await;
}

async fn execute(args: &Args) -> Result<ExitCode> {
    let dir = args
        .value("runtime-dir")
        .map_or_else(default_directory, PathBuf::from);
    let action = args.positional.first().map_or("toggle", String::as_str);
    ensure!(
        args.positional.len() <= 1
            && matches!(action, "toggle" | "stop" | "status" | "watch" | "sources"),
        "Unknown recorder action"
    );
    if action == "watch" {
        return super::watch::run(&dir).await;
    }
    if action == "sources" {
        return match audio::sources().await {
            Ok(s) => {
                println!("{}", json!(s));
                Ok(ExitCode::SUCCESS)
            }
            Err(_) => {
                println!("[]");
                Ok(ExitCode::FAILURE)
            }
        };
    }
    if action == "status" {
        println!("{}", Value::Object(status(&dir)));
        return Ok(ExitCode::SUCCESS);
    }
    if action == "stop" && status(&dir).get("orphaned") != Some(&Value::Bool(true)) {
        stop_owner(&dir).await?;
        return Ok(ExitCode::SUCCESS);
    }
    unsafe {
        libc::umask(0o077);
    }
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&dir)?;
    let mut lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(dir.join("owner.lock"))?;
    match flock(&lock, FlockOperation::NonBlockingLockExclusive) {
        Ok(()) => {}
        Err(Errno::WOULDBLOCK) => {
            for _ in 0..30 {
                if stop_owner(&dir).await? {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            return Ok(ExitCode::SUCCESS);
        }
        Err(e) => return Err(e.into()),
    }
    let old = Value::Object(read_state(&dir));
    let pid = json!(std::process::id());
    let token = identity(&pid);
    let mut term = signal(SignalKind::terminate())?;
    let mut int = signal(SignalKind::interrupt())?;
    let (tx, rx) = watch::channel(false);
    tokio::spawn(async move {
        tokio::select! {_=term.recv()=>{},_=int.recv()=>{}}
        let _ = tx.send(true);
    });
    lock.rewind()?;
    lock.set_len(0)?;
    serde_json::to_writer(&lock, &json!({"pid":pid,"identity":token}))?;
    let orphan = matching_pid(&old["childPid"], &old["childIdentity"])?.is_some()
        || old["mixerSink"].as_str().is_some_and(|s| !s.is_empty());
    let mut owner = Owner {
        dir: dir.clone(),
        state: if orphan {
            old
        } else {
            json!({"startedAt":0,"file":"","error":""})
        },
        child: None,
        logs: Default::default(),
        saved: String::new(),
        cancel: rx,
    };
    owner.state["pid"] = pid;
    owner.state["identity"] = json!(token);
    let mut result = if orphan {
        async {
            owner.publish("stopping")?;
            owner.terminate(false).await?;
            owner.cleanup_audio().await?;
            owner.verify("Recovered").await
        }
        .await
    } else if action != "stop" {
        let config = args
            .value("config")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("VELORA_RECORDER_CONFIG").map(PathBuf::from))
            .unwrap_or_else(crate::apps::shell_config_path);
        async {
            owner.publish("starting")?;
            owner.record(Options::read(&config).await?, args).await
        }
        .await
    } else {
        Ok(())
    };
    if result.is_err()
        && owner.state["state"] != "stopping"
        && owner
            .child
            .as_mut()
            .is_some_and(|c| c.try_wait().ok() == Some(None))
    {
        owner.publish("stopping")?;
        if let Err(error) = owner.terminate(true).await {
            result = Err(error);
        }
    }
    let child_alive =
        matching_pid(&owner.state["childPid"], &owner.state["childIdentity"])?.is_some();
    if !child_alive {
        if let Some(p) = owner.state["file"]
            .as_str()
            .filter(|p| fs::metadata(p).is_ok_and(|m| m.len() == 0))
        {
            let _ = fs::remove_file(p);
        }
        if let Err(e) = owner.cleanup_audio().await {
            result = Err(anyhow!(
                "{}Audio cleanup failed (press Stop again to retry): {e}",
                result.err().map(|e| format!("{e}\n")).unwrap_or_default()
            ));
        }
    }
    if let Err(e) = result {
        let mut msg = e.to_string();
        {
            let l = owner.logs.lock().unwrap();
            if !l.tail.is_empty() {
                msg.push('\n');
                msg.push_str(&String::from_utf8_lossy(
                    &l.tail[l.tail.len().saturating_sub(3000)..],
                ));
            }
        }
        if !owner.saved.is_empty() {
            msg.push_str(&format!("\nVideo file retained: {}", owner.saved));
        }
        owner.state["error"] = json!(msg);
        owner.publish("error")?;
        fs::write(dir.join("error.log"), format!("{msg}\n"))?;
        notify(
            "Recording failed",
            &msg.chars().take(500).collect::<String>(),
            5000,
        )
        .await;
        bail!("{msg}");
    }
    owner.state["childPid"] = Value::Null;
    owner.state["childIdentity"] = Value::Null;
    owner.state["error"] = json!("");
    owner.state["file"] = json!(owner.saved);
    owner.publish("idle")?;
    if !owner.saved.is_empty() {
        notify("Recording saved", &owner.saved, 5000).await;
    }
    Ok(ExitCode::SUCCESS)
}

pub fn run(argv: Vec<String>) -> Result<ExitCode> {
    let args = Args::parse(
        argv,
        &["fullscreen", "select-region", "sound", "silent", "mic"],
    )?;
    args.reject_unknown(&[
        "fullscreen",
        "select-region",
        "sound",
        "silent",
        "mic",
        "config",
        "runtime-dir",
        "region",
    ])?;
    ensure!(
        !args.flag("silent") || !(args.flag("sound") || args.flag("mic")),
        "--silent cannot be combined with --sound or --mic"
    );
    ensure!(
        ["region", "fullscreen", "select-region"]
            .iter()
            .filter(|k| args.flag(k))
            .count()
            <= 1,
        "Choose one recording mode"
    );
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?
        .block_on(execute(&args))
}
