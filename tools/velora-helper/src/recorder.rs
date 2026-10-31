//! The read-only half of scripts/videos/recorder.py: what the recorder is doing. The shell asks every
//! second, all the time, so this mustn't start an interpreter. Recording itself stays in the script,
//! which spends its life waiting for wf-recorder.

use anyhow::Result;
use serde_json::{json, Map, Value};
use std::fs;
use std::io::Read as _;
use std::os::fd::AsRawFd as _;
use std::path::{Path, PathBuf};

pub fn run(argv: Vec<String>) -> Result<()> {
    let args = crate::args::Args::parse(argv, &[])?;
    args.reject_unknown(&["runtime-dir"])?;
    let directory = args.value("runtime-dir").map_or_else(default_directory, PathBuf::from);
    println!("{}", Value::Object(status(&directory)));
    Ok(())
}

fn default_directory() -> PathBuf {
    if let Some(path) = std::env::var_os("VELORA_RECORDER_RUNTIME") {
        return PathBuf::from(path);
    }
    // SAFETY: getuid has no preconditions and can't fail.
    let uid = unsafe { libc::getuid() };
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map_or_else(|| PathBuf::from(format!("/run/user/{uid}")), PathBuf::from);
    runtime.join("velora-recorder")
}

/// A process's start time, or None if it's gone or a zombie: unlike its number, this is never reused.
fn identity(pid: &Value) -> Option<String> {
    let pid = pid.as_u64()?;
    let text = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let fields: Vec<&str> = text.rsplit_once(')')?.1.split_whitespace().collect();
    if *fields.first()? == "Z" {
        return None;
    }
    fields.get(19).map(|field| field.to_string())
}

fn read_state(directory: &Path) -> Map<String, Value> {
    fs::read_to_string(directory.join("state.json")).ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_default()
}

fn truthy(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(value) => *value,
        Value::Number(value) => value.as_f64() != Some(0.0),
        Value::String(value) => !value.is_empty(),
        Value::Array(value) => !value.is_empty(),
        Value::Object(value) => !value.is_empty(),
    }
}

fn get<'a>(state: &'a Map<String, Value>, key: &str) -> &'a Value {
    state.get(key).unwrap_or(&Value::Null)
}

/// Whether the same process that took the lock published this state.
fn same_owner(state: &Map<String, Value>, owner: &Map<String, Value>) -> bool {
    get(state, "pid") == get(owner, "pid") && get(state, "identity") == get(owner, "identity")
}

pub fn status(directory: &Path) -> Map<String, Value> {
    let mut state = read_state(directory);
    let mut alive = false;
    if let Ok(mut lock) = fs::File::open(directory.join("owner.lock")) {
        // SAFETY: the descriptor stays open for the call, and closing it below lets the lock go.
        alive = unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0;
        let mut text = String::new();
        let owner: Map<String, Value> = lock.read_to_string(&mut text).ok().and_then(|_| serde_json::from_str(&text).ok()).unwrap_or_default();
        if alive && !same_owner(&state, &owner) {
            return json!({ "state": "starting" }).as_object().cloned().unwrap_or_default();
        }
    }
    let owner_running = identity(get(&state, "pid")).map_or(Value::Null, Value::String) == *get(&state, "identity");
    if !alive || !owner_running {
        let child = get(&state, "childIdentity");
        let child_alive = truthy(child) && identity(get(&state, "childPid")).map_or(Value::Null, Value::String) == *child;
        if child_alive {
            let phase = if truthy(get(&state, "error")) {
                "stopping"
            } else if get(&state, "childKind") == "recorder" {
                "recording"
            } else {
                "selecting"
            };
            state.insert("state".into(), json!(phase));
            state.insert("orphaned".into(), json!(true));
        } else if truthy(get(&state, "mixerSink")) {
            state.insert("state".into(), json!("stopping"));
            state.insert("orphaned".into(), json!(true));
        } else {
            let phase = if get(&state, "state") == "error" { "error" } else { "idle" };
            state.insert("state".into(), json!(phase));
        }
        if alive {
            state.insert("state".into(), json!("starting")); // The owner is publishing its initial state
        }
    }
    if state.is_empty() {
        state.insert("state".into(), json!("idle"));
    }
    state
}
