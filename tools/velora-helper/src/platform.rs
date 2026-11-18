//! Filesystem and process state shared by the two desktop executables.
use serde_json::Value;
use std::{env, fs, path::PathBuf};

fn user_directory(variable: &str, default: &str) -> PathBuf {
    env::var_os(variable)
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(default))
}

pub(crate) fn data_home() -> PathBuf {
    user_directory("XDG_DATA_HOME", ".local/share")
}
pub(crate) fn state_home() -> PathBuf {
    user_directory("XDG_STATE_HOME", ".local/state")
}

pub(crate) fn identity(pid: &Value) -> Option<String> {
    let pid = pid.as_u64()?;
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let mut fields = stat.rsplit_once(')')?.1.split_whitespace();
    if fields.next()? == "Z" {
        return None;
    }
    fields.nth(18).map(str::to_owned)
}
