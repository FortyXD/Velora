//! Port of scripts/colors/pick-color.sh: picks a color on screen with hyprpicker, copies it, and remembers it for
//! the toolbox's Colors tab.

use anyhow::Result;
use serde_json::Value;
use std::path::PathBuf;
use std::process::{Command, ExitCode, Stdio};

const REMEMBERED: usize = 50;

/// `#RRGGBB`, or nothing for anything else.
fn normalized(picked: &str) -> Option<String> {
    let color = picked.trim().to_uppercase();
    (color.len() == 7 && color.starts_with('#') && color[1..].bytes().all(|byte| byte.is_ascii_hexdigit())).then_some(color)
}

/// The newest first, without repeats, up to a limit.
fn remember(history: &str, color: &str) -> String {
    let previous: Vec<Value> = serde_json::from_str(history).unwrap_or_default();
    let mut colors = vec![Value::String(color.to_string())];
    colors.extend(previous.into_iter().filter(|entry| entry.as_str() != Some(color)));
    colors.truncate(REMEMBERED);
    Value::Array(colors).to_string()
}

pub fn run() -> Result<ExitCode> {
    let output = Command::new("hyprpicker").args(["-a", "-f", "hex"]).stderr(Stdio::null()).output();
    let Some(color) = output.ok().filter(|output| output.status.success()).and_then(|output| normalized(&String::from_utf8_lossy(&output.stdout))) else {
        return Ok(ExitCode::FAILURE);
    };
    let state = std::env::var_os("XDG_STATE_HOME").map_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state"), PathBuf::from);
    let file = state.join("quickshell/user/color_history.json");
    if let Some(parent) = file.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let history = std::fs::read_to_string(&file).unwrap_or_default();
    let staged = file.with_extension("json.tmp");
    std::fs::write(&staged, remember(&history, &color))?;
    std::fs::rename(&staged, &file)?;
    println!("{color}");
    Ok(ExitCode::SUCCESS)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_full_hex_color_counts() {
        assert_eq!(normalized("#ab12cd\n").as_deref(), Some("#AB12CD"));
        assert_eq!(normalized("ab12cd"), None);
        assert_eq!(normalized("#ab12c"), None);
        assert_eq!(normalized("#gg12cd"), None);
        assert_eq!(normalized(""), None);
    }

    #[test]
    fn the_newest_goes_first_without_repeats_and_the_oldest_drop_off() {
        assert_eq!(remember("", "#000000"), r##"["#000000"]"##);
        assert_eq!(remember(r##"["#111111","#000000"]"##, "#000000"), r##"["#000000","#111111"]"##);
        let full: Vec<String> = (0..50).map(|index| format!("#{index:06}")).collect();
        let kept: Vec<String> = serde_json::from_str(&remember(&serde_json::to_string(&full).unwrap(), "#ABCDEF")).unwrap();
        assert_eq!(kept.len(), 50);
        assert_eq!(kept[0], "#ABCDEF");
        assert_eq!(kept[49], "#000048");
    }
}
