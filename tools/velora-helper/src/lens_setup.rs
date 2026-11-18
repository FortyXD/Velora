//! Read the optional Lens installer's published state without loading its model environment.
use anyhow::Result;
use gio::{glib, prelude::*};
use serde_json::{json, Value};
use std::{
    cell::RefCell,
    fs::{self, File},
    io::{Read, Seek, SeekFrom},
    os::unix::fs::DirBuilderExt,
    path::{Path, PathBuf},
    process::ExitCode,
    rc::Rc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

struct Paths {
    state: PathBuf,
    binaries: [PathBuf; 2],
    manifest: PathBuf,
    python: PathBuf,
}

impl Paths {
    fn snapshot(&self) -> Value {
        let mut state: Value = fs::read(self.state.join("setup.json"))
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .filter(Value::is_object)
            .unwrap_or_else(|| json!({}));
        let claimed = state["running"].as_bool() == Some(true);
        let start_ticks = claimed
            .then(|| crate::platform::identity(&state["pid"]))
            .flatten();
        let active = start_ticks.is_some() && start_ticks.as_deref() == state["identity"].as_str();
        if claimed && !active {
            state["stage"] = json!("interrupted");
        }
        state["running"] = json!(active);
        state["installed"] = json!(self
            .binaries
            .iter()
            .any(|p| p.is_file() && rustix::fs::access(p, rustix::fs::Access::EXEC_OK).is_ok()));
        state["models"] = json!(self.manifest.is_file() && self.python.is_file());
        state["cancelling"] = json!(active && self.state.join("cancel").exists());
        let stage = state["stage"].as_str().unwrap_or("");
        let done = stage == "done";
        let failed = stage == "failed";
        let stage_step = match stage {
            "building" | "service" => 2,
            "runtime" | "export-tools" => 3,
            "models" => 4,
            "verifying" | "done" => 5,
            _ => 1,
        };
        let total = state["steps_total"].as_i64().unwrap_or(5);
        let step = state["step"].as_i64().unwrap_or(stage_step);
        state["steps_total"] = json!(total);
        state["step"] = json!(step);
        if state["steps_done"].is_null() {
            state["steps_done"] = json!(if done { total } else { step - 1 });
        }
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs_f64();
        let started = state["started_at"].as_f64().or_else(|| {
            // Old installers only recorded the process start time in clock ticks since boot.
            if !active {
                return None;
            }
            let ticks: f64 = start_ticks?.parse().ok()?;
            let uptime: f64 = fs::read_to_string("/proc/uptime")
                .ok()?
                .split_whitespace()
                .next()?
                .parse()
                .ok()?;
            // SAFETY: _SC_CLK_TCK takes no arguments and does not modify process state.
            let rate = unsafe { libc::sysconf(libc::_SC_CLK_TCK) };
            (rate > 0).then(|| now - uptime + ticks / rate as f64)
        });
        if let Some(started) = started {
            state["elapsed_seconds"] =
                json!((state["finished_at"].as_f64().unwrap_or(now) - started).max(0.) as u64);
        }
        if failed {
            if let Ok(mut log) = File::open(self.state.join("setup.log")) {
                if let Ok(len) = log.metadata().map(|s| s.len()) {
                    let mut detail = Vec::new();
                    if log.seek(SeekFrom::Start(len.saturating_sub(6000))).is_ok()
                        && log.take(6000).read_to_end(&mut detail).is_ok()
                    {
                        state["detail"] = json!(String::from_utf8_lossy(&detail));
                    }
                }
            }
        }
        state
    }
}

struct Observer {
    paths: Paths,
    previous: Value,
    timer: Option<glib::SourceId>,
}

fn publish(observer: &Rc<RefCell<Observer>>) {
    let mut status = observer.borrow_mut();
    let value = status.paths.snapshot();
    let active = value["running"] == true;
    if value != status.previous {
        println!("{value}");
        status.previous = value;
    }
    if active && status.timer.is_none() {
        let observer = Rc::clone(observer);
        // The elapsed-time label and interrupted installs only need ticks during an active job.
        status.timer = Some(glib::timeout_add_local_once(
            Duration::from_millis(1500),
            move || {
                observer.borrow_mut().timer.take();
                publish(&observer);
            },
        ));
    } else if !active {
        if let Some(timer) = status.timer.take() {
            timer.remove();
        }
    }
}

pub fn run(watch: bool) -> Result<ExitCode> {
    if let Err(error) = observe(watch) {
        println!(
            "{}",
            json!({"running":false, "stage":"failed", "detail":error.to_string()})
        );
        return Ok(ExitCode::FAILURE);
    }
    Ok(ExitCode::SUCCESS)
}

fn observe(watch: bool) -> Result<()> {
    let state = crate::platform::state_home().join("velora-lens");
    let data = crate::platform::data_home().join("velora-lens");
    let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
    let paths = Paths {
        state,
        binaries: [
            home.join(".local/bin/velora-searchd"),
            Path::new("/usr/bin/velora-searchd").into(),
        ],
        manifest: data.join("models/manifest.json"),
        python: data.join("venv/bin/python"),
    };
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&paths.state)?;
    if !watch {
        println!("{}", paths.snapshot());
        return Ok(());
    }
    let files = [
        paths.state.join("setup.json"),
        paths.state.join("cancel"),
        paths.binaries[0].clone(),
        paths.binaries[1].clone(),
        paths.manifest.clone(),
        paths.python.clone(),
    ];
    let observer = Rc::new(RefCell::new(Observer {
        paths,
        previous: Value::Null,
        timer: None,
    }));
    let mut monitors = Vec::new();
    for path in files {
        let monitor = gio::File::for_path(path)
            .monitor_file(gio::FileMonitorFlags::NONE, None::<&gio::Cancellable>)?;
        let observer = Rc::clone(&observer);
        monitor.connect_changed(move |_, _, _, _| publish(&observer));
        monitors.push(monitor);
    }
    publish(&observer);
    glib::MainLoop::new(None, false).run();
    Ok(())
}
