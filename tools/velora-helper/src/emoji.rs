//! Port of hyprland/scripts/fuzzel-emoji.sh: picks an emoji with fuzzel, then types or copies it.

use anyhow::{bail, Result};
use std::io::Write;
use std::process::{Command, ExitCode, Stdio};

/// Also read by services/Emojis.qml, for the launcher.
const DATA: &str = include_str!("../../../dots/.config/hypr/hyprland/data/emoji.txt");

/// The emoji itself: what comes before the first space of a line.
fn picked_emoji(line: &str) -> &str {
    line.trim_end_matches('\n').split(' ').next().unwrap_or_default()
}

fn copy(emoji: &str) -> Result<()> {
    Command::new("wl-copy").arg(emoji).status()?;
    Ok(())
}

pub fn run(argv: Vec<String>) -> Result<ExitCode> {
    let mode = argv.first().map_or("type", String::as_str);
    if !matches!(mode, "type" | "copy") {
        bail!("usage: velora-helper emoji [type|copy]");
    }
    let mut fuzzel = Command::new("fuzzel").args(["--match-mode", "fzf", "--dmenu"]).stdin(Stdio::piped()).stdout(Stdio::piped()).spawn()?;
    fuzzel.stdin.take().expect("stdin is piped").write_all(DATA.as_bytes())?;
    let output = fuzzel.wait_with_output()?;
    let text = String::from_utf8_lossy(&output.stdout);
    let emoji = picked_emoji(&text);
    if emoji.is_empty() {
        return Ok(ExitCode::SUCCESS);
    }
    if mode == "type" {
        let typed = Command::new("wtype").arg(emoji).status();
        if !typed.is_ok_and(|status| status.success()) {
            copy(emoji)?;
        }
    } else {
        copy(emoji)?;
    }
    Ok(ExitCode::SUCCESS)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_emoji_is_the_first_word() {
        assert_eq!(picked_emoji("😀 grinning face smile\n"), "😀");
        assert_eq!(picked_emoji(""), "");
    }

    #[test]
    fn the_data_is_there() {
        assert!(DATA.lines().count() > 1000);
        assert!(DATA.starts_with("😀 "));
    }
}
