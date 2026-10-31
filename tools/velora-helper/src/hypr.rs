//! Port of hyprland/scripts/zoom.sh and workspace_action.sh: the zoom keys, and Win+number going by the monitor
//! under the pointer.

use anyhow::{anyhow, bail, Context, Result};
use serde_json::Value;
use std::fs;
use std::os::unix::fs::PermissionsExt as _;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};

const ZOOM_MIN: f64 = 1.0;
const ZOOM_MAX: f64 = 3.0;

fn hyprctl_json(arguments: &[&str]) -> Result<Value> {
    let output = Command::new("hyprctl").args(arguments).output().context("couldn't run hyprctl")?;
    Ok(serde_json::from_slice(&output.stdout)?)
}

/// As few digits as it takes, up to six significant ones: `1.3`, not `1.3000000000000000444`.
fn short_number(value: f64) -> String {
    let rounded = format!("{value:.5}");
    rounded.trim_end_matches('0').trim_end_matches('.').to_string()
}

pub fn clamp_zoom(value: f64) -> f64 {
    value.clamp(ZOOM_MIN, ZOOM_MAX)
}

fn set_zoom(value: f64) -> Result<()> {
    let expression = format!("hl.config({{ cursor = {{ zoom_factor = {} }} }})", short_number(clamp_zoom(value)));
    Command::new("hyprctl").args(["eval", &expression]).status()?;
    Ok(())
}

pub fn zoom(argv: Vec<String>) -> Result<()> {
    let usage = "usage: velora-helper zoom {reset|increase STEP|decrease STEP}";
    let step = |value: Option<&String>| value.ok_or_else(|| anyhow!(usage)).and_then(|text| text.parse::<f64>().with_context(|| usage));
    let current = || -> Result<f64> { hyprctl_json(&["getoption", "-j", "cursor:zoom_factor"])?["float"].as_f64().ok_or_else(|| anyhow!("hyprctl didn't report the zoom")) };
    match argv.first().map(String::as_str) {
        Some("reset") => set_zoom(1.0),
        Some("increase") => set_zoom(current()? + step(argv.get(1))?),
        Some("decrease") => set_zoom(current()? - step(argv.get(1))?),
        _ => bail!(usage),
    }
}

fn logical_size(monitor: &Value) -> (f64, f64) {
    let (width, height, scale) = (monitor["width"].as_f64().unwrap_or(0.0), monitor["height"].as_f64().unwrap_or(0.0), monitor["scale"].as_f64().unwrap_or(1.0));
    if monitor["transform"].as_i64().unwrap_or(0) % 2 == 1 {
        (height / scale, width / scale)
    } else {
        (width / scale, height / scale)
    }
}

/// The monitor under the pointer, else the focused one, else the first: its name and workspace.
pub fn monitor_at(monitors: &[Value], x: f64, y: f64) -> Option<(String, i64)> {
    let under = monitors.iter().find(|monitor| {
        let (left, top) = (monitor["x"].as_f64().unwrap_or(0.0), monitor["y"].as_f64().unwrap_or(0.0));
        let (width, height) = logical_size(monitor);
        x >= left && x < left + width && y >= top && y < top + height
    });
    let chosen = under.or_else(|| monitors.iter().find(|monitor| monitor["focused"] == true)).or_else(|| monitors.first())?;
    Some((chosen["name"].as_str()?.to_string(), chosen["activeWorkspace"]["id"].as_i64()?))
}

/// Number keys pick within the current group of ten: from workspace 14, key 3 means 13.
pub fn workspace_target(target: &str, current: i64) -> String {
    if target.contains('+') || target.contains('-') {
        return target.to_string();
    }
    match target.parse::<i64>() {
        Ok(number) if !target.is_empty() && target.bytes().all(|byte| byte.is_ascii_digit()) => (((current - 1) / 10) * 10 + number).to_string(),
        _ => target.to_string(),
    }
}

fn active_workspace() -> Result<i64> {
    hyprctl_json(&["activeworkspace", "-j"])?["id"].as_i64().ok_or_else(|| anyhow!("hyprctl didn't report the workspace"))
}

pub fn workspace(argv: Vec<String>) -> Result<ExitCode> {
    let (Some(dispatcher), Some(target)) = (argv.first(), argv.get(1)) else {
        eprintln!("usage: velora-helper workspace <dispatcher> <target>");
        return Ok(ExitCode::FAILURE);
    };
    match dispatcher.as_str() {
        "workspace" => {
            let under = (|| {
                let cursor = hyprctl_json(&["cursorpos", "-j"]).ok()?;
                let monitors = hyprctl_json(&["monitors", "-j"]).ok()?;
                monitor_at(monitors.as_array()?, cursor["x"].as_f64()?, cursor["y"].as_f64()?)
            })();
            let current = match &under {
                Some((_, workspace)) => *workspace,
                None => active_workspace()?,
            };
            // Hyprland creates a previously unused workspace on the focused monitor. Focus the monitor under the
            // pointer first, so Win+number follows the mouse instead of stale keyboard focus from the other display.
            if let Some((monitor, _)) = &under {
                Command::new("hyprctl").args(["dispatch", &format!(r#"hl.dsp.focus({{ monitor = "{monitor}" }})"#)]).stdout(Stdio::null()).status()?;
            }
            let destination = workspace_target(target, current);
            Command::new("hyprctl").args(["dispatch", &format!(r#"hl.dsp.focus({{ workspace = "{destination}" }})"#)]).status()?;
        }
        "movetoworkspacesilent" => {
            let destination = workspace_target(target, active_workspace()?);
            Command::new("hyprctl").args(["dispatch", &format!(r#"hl.dsp.window.move({{ workspace = "{destination}", follow = false }})"#)]).status()?;
        }
        other => {
            eprintln!("Unsupported dispatcher for Lua config: {other}");
            return Ok(ExitCode::FAILURE);
        }
    }
    Ok(ExitCode::SUCCESS)
}

// hypr-config ------------------------------------------------------------------------------------------
// Port of scripts/hyprland/hyprconfigurator.py: edits the Lua overrides the shell keeps for Hyprland.
// Subkeys use a colon for nesting: `decoration:blur:size` is hl.config({decoration={blur={size=...}}}).

fn format_value(value: &str) -> String {
    let number = value.trim().parse::<f64>().is_ok();
    if value == "true" || value == "false" || number { value.to_string() } else { format!("\"{value}\"") }
}

fn config_line(key: &str, value: &str) -> String {
    let parts: Vec<&str> = key.split(':').collect();
    let mut nested = format!("{}={}", parts[parts.len() - 1], format_value(value));
    for part in parts[..parts.len() - 1].iter().rev() {
        nested = format!("{part}={{{nested}}}");
    }
    format!("hl.config({{{nested}}})\n")
}

/// Whether a line of the file sets this key.
fn sets_key(line: &str, key: &str) -> bool {
    let Some(mut rest) = line.trim_start().strip_prefix("hl.config({") else { return false };
    let parts: Vec<&str> = key.split(':').collect();
    for (position, part) in parts.iter().enumerate() {
        let Some(after) = rest.trim_start().strip_prefix(part) else { return false };
        let Some(after) = after.trim_start().strip_prefix('=') else { return false };
        rest = after;
        if position + 1 < parts.len() {
            let Some(after) = rest.strip_prefix('{') else { return false };
            rest = after;
        }
    }
    true
}

pub fn config(argv: Vec<String>) -> Result<()> {
    let mut file = "~/.config/hypr/hyprland/shellOverrides/main.lua".to_string();
    let mut set: Vec<(String, String)> = Vec::new();
    let mut reset: Vec<String> = Vec::new();
    let mut arguments = argv.into_iter();
    while let Some(argument) = arguments.next() {
        let mut next = || arguments.next().ok_or_else(|| anyhow!("{argument} needs a value"));
        match argument.as_str() {
            "--file" => file = next()?,
            "--reset" => {
                let key = next()?;
                if !reset.contains(&key) {
                    reset.push(key);
                }
            }
            "--set" => {
                let (key, value) = (next()?, next()?);
                if value == "[[EMPTY]]" {
                    if !reset.contains(&key) {
                        reset.push(key);
                    }
                } else if let Some(entry) = set.iter_mut().find(|(known, _)| *known == key) {
                    entry.1 = value;
                } else {
                    set.push((key, value));
                }
            }
            other => bail!("unknown option {other}"),
        }
    }
    if set.is_empty() && reset.is_empty() {
        println!("Error: Must specify at least one key to set or reset.");
        return Ok(());
    }
    let path = match file.strip_prefix("~/") {
        Some(rest) => PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(rest),
        None => PathBuf::from(&file),
    };
    let text = match fs::read_to_string(&path) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(error) => return Err(error).with_context(|| format!("can't read {}", path.display())),
    };
    let mut lines: Vec<String> = Vec::new();
    let mut found: Vec<&str> = Vec::new();
    for line in text.split_inclusive('\n') {
        if reset.iter().any(|key| sets_key(line, key)) {
            continue;
        }
        if let Some((key, value)) = set.iter().find(|(key, _)| sets_key(line, key)) {
            lines.push(config_line(key, value));
            found.push(key);
        } else {
            lines.push(line.to_string());
        }
    }
    for (key, value) in &set {
        if !found.contains(&key.as_str()) {
            if let Some(last) = lines.last_mut().filter(|last| !last.ends_with('\n')) {
                last.push('\n');
            }
            lines.push(config_line(key, value));
        }
    }
    if let Err(error) = replace_file(&path, &lines.concat()) {
        println!("Error saving file: {error}");
        return Ok(());
    }
    for key in &reset {
        println!("Removed '{key}' from '{}'", path.display());
    }
    for (key, value) in &set {
        println!("Updated '{}' with {}", path.display(), config_line(key, value).trim());
    }
    Ok(())
}

/// Through a temporary file beside it, keeping its permissions.
fn replace_file(path: &Path, text: &str) -> Result<()> {
    let absolute = std::path::absolute(path)?;
    let directory = absolute.parent().context("the file has no directory")?;
    fs::create_dir_all(directory)?;
    let temporary = directory.join(format!(".hypr-config-{}", std::process::id()));
    let mode = fs::metadata(&absolute).map_or(0o644, |meta| meta.permissions().mode());
    let result = fs::write(&temporary, text)
        .and_then(|()| fs::set_permissions(&temporary, fs::Permissions::from_mode(mode)))
        .and_then(|()| fs::rename(&temporary, &absolute));
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    Ok(result?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn zoom_stays_in_range_and_prints_short() {
        assert_eq!(clamp_zoom(0.5), 1.0);
        assert_eq!(clamp_zoom(5.0), 3.0);
        assert_eq!(clamp_zoom(1.7), 1.7);
        assert_eq!(short_number(1.0), "1");
        assert_eq!(short_number(1.0 + 0.3), "1.3");
        assert_eq!(short_number(1.3 - 0.1), "1.2");
        assert_eq!(short_number(3.0), "3");
    }

    #[test]
    fn number_keys_stay_in_the_group_of_ten() {
        assert_eq!(workspace_target("3", 1), "3");
        assert_eq!(workspace_target("3", 10), "3");
        assert_eq!(workspace_target("3", 11), "13");
        assert_eq!(workspace_target("10", 14), "20");
        assert_eq!(workspace_target("r+1", 14), "r+1");
        assert_eq!(workspace_target("-1", 14), "-1");
        assert_eq!(workspace_target("special:music", 14), "special:music");
    }

    fn monitor(name: &str, x: i64, width: i64, scale: f64, transform: i64, focused: bool, workspace: i64) -> Value {
        json!({ "name": name, "x": x, "y": 0, "width": width, "height": 1000, "scale": scale, "transform": transform, "focused": focused, "activeWorkspace": { "id": workspace } })
    }

    #[test]
    fn the_monitor_under_the_pointer_wins() {
        let monitors = [monitor("A", 0, 2000, 2.0, 0, true, 1), monitor("B", 1000, 1000, 1.0, 0, false, 11)];
        assert_eq!(monitor_at(&monitors, 500.0, 10.0), Some(("A".to_string(), 1)));
        assert_eq!(monitor_at(&monitors, 1500.0, 10.0), Some(("B".to_string(), 11)));
    }

    #[test]
    fn a_rotated_monitor_swaps_its_sides() {
        let monitors = [monitor("R", 0, 2000, 1.0, 1, false, 5)];
        assert_eq!(monitor_at(&monitors, 900.0, 1500.0), Some(("R".to_string(), 5)));
        // Outside it, nothing matches and the first one stands in
        assert_eq!(monitor_at(&monitors, 1500.0, 10.0), Some(("R".to_string(), 5)));
    }

    #[test]
    fn outside_all_of_them_the_focused_one_stands_in() {
        let monitors = [monitor("A", 0, 100, 1.0, 0, false, 1), monitor("B", 100, 100, 1.0, 0, true, 2)];
        assert_eq!(monitor_at(&monitors, 9999.0, 10.0), Some(("B".to_string(), 2)));
        assert_eq!(monitor_at(&[], 0.0, 0.0), None);
    }

    #[test]
    fn config_lines_nest_and_quote() {
        assert_eq!(config_line("decoration:blur:size", "8"), "hl.config({decoration={blur={size=8}}})\n");
        assert_eq!(config_line("a", "true"), "hl.config({a=true})\n");
        assert_eq!(config_line("a:b", "some text"), "hl.config({a={b=\"some text\"}})\n");
    }

    #[test]
    fn config_keys_match_whole_names_only() {
        assert!(sets_key("  hl.config({ decoration ={blur={ size=8}}})\n", "decoration:blur:size"));
        assert!(!sets_key("hl.config({a = {b=1}})\n", "a:b"));
        assert!(sets_key("hl.config({a=1})\n", "a"));
        assert!(!sets_key("hl.config({ab=1})\n", "a"));
        assert!(!sets_key("hl.config({a={b=1}})\n", "a:c"));
        assert!(!sets_key("-- hl.config({a=1})\n", "a"));
    }
}
