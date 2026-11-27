use super::{config_home, publish, terminals::ink};
use anyhow::Result;
use rustix::process::getuid;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    io::ErrorKind,
    os::unix::fs::{FileTypeExt, MetadataExt},
    path::Path,
    process::Command,
};

type Colors = BTreeMap<String, String>;

fn reload_tmux(directory: &Path) {
    let Ok(entries) = fs::read_dir(directory.join("tmux-servers")) else {
        return;
    };
    let mut sockets = BTreeSet::new();
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(socket) = fs::read_link(&path) else {
            continue;
        };
        // A dead server can leave its socket behind or another server can reuse the name.
        let pid = entry.file_name();
        if pid.to_string_lossy().parse::<u32>().is_err() {
            continue;
        }
        if !Path::new("/proc").join(pid).is_dir() || !socket.exists() {
            let _ = fs::remove_file(path);
            continue;
        }
        if fs::symlink_metadata(&socket)
            .is_ok_and(|m| m.file_type().is_socket() && m.uid() == getuid().as_raw())
        {
            sockets.insert(socket);
        }
    }
    for socket in sockets {
        let _ = Command::new("timeout")
            .args(["2s", "tmux", "-N", "-S"])
            .arg(socket)
            .args([
                "if-shell",
                "-F",
                "#{@velora_palette_dir}",
                "source-file -qF '#{@velora_palette_dir}/tmux.conf'",
            ])
            .output();
    }
}

fn update_tmux(directory: &Path, colors: &Colors, fg: &str) -> Result<()> {
    let bg = colors.get("term0").map_or("default", String::as_str);
    let border = colors.get("outline").map_or("colour8", String::as_str);
    let primary = colors.get("primary");
    let accent = primary.map_or("cyan", String::as_str);
    let on_accent = primary
        .map(|p| ink(p, colors.get("onPrimary")))
        .unwrap_or_else(|| "black".into());
    let label = colors
        .get("term0")
        .map(|bg| ink(bg, primary))
        .unwrap_or_else(|| accent.to_owned());
    let theme = format!(
        "set -g status-style 'fg={fg},bg={bg}'\n\
         set -g status-left-style 'fg={label},bg={bg},bold'\n\
         set -g window-status-current-style 'fg={on_accent},bg={accent},bold'\n\
         set -g pane-border-style 'fg={border}'\n\
         set -g pane-active-border-style 'fg={accent}'\n\
         set -g message-style 'fg={on_accent},bg={accent}'\n\
         set -g mode-style 'fg={on_accent},bg={accent}'\n"
    );
    if publish(&directory.join("tmux.conf"), theme.as_bytes())? {
        reload_tmux(directory);
    }
    Ok(())
}

fn reload_btop(directory: &Path) {
    let Ok(config) = fs::read_to_string(directory.join("btop.conf")) else {
        return;
    };
    let selected = config
        .lines()
        .rev()
        .filter_map(|line| line.split_once('='))
        .find(|(key, _)| key.trim() == "color_theme")
        .map(|(_, value)| value.trim().trim_matches('"'));
    if !matches!(
        selected.and_then(|s| s.rsplit('/').next()),
        Some("Velora" | "Velora.theme")
    ) {
        return;
    }
    let Some(home) = std::env::var_os("HOME") else {
        return;
    };
    // Older releases and processes still starting may have no reload handler.
    let config = config_home();
    let environment = if config == Path::new(&home).join(".config") {
        format!("HOME={}", home.to_string_lossy())
    } else {
        format!("XDG_CONFIG_HOME={}", config.display())
    };
    let _ = Command::new("pkill")
        .args([
            "--signal",
            "USR2",
            "--require-handler",
            "--euid",
            &getuid().as_raw().to_string(),
            "--env",
        ])
        .arg(environment)
        .args(["--exact", "btop"])
        .output();
}

fn update_btop(colors: &Colors, fg: &str) -> Result<()> {
    let config = config_home();
    let template = match fs::read_to_string(config.join("matugen/templates/btop/Velora.theme")) {
        Ok(text) => text,
        Err(e) if e.kind() == ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e.into()),
    };
    let mut output = String::new();
    let mut color = None;
    for line in template.lines() {
        if let Some(role) = line.strip_prefix("# @") {
            color = colors.get(role).map(String::as_str);
            if role == "term7" && colors.contains_key("term0") {
                color = Some(fg);
            }
        }
        if let Some((key, replacement)) = line.split_once('=').map(|(key, _)| key).zip(color) {
            output.push_str(&format!("{key}=\"{replacement}\"\n"));
        } else {
            output.push_str(line);
            output.push('\n');
        }
    }
    let directory = config.join("btop");
    fs::create_dir_all(directory.join("themes"))?;
    if publish(&directory.join("themes/Velora.theme"), output.as_bytes())? {
        reload_btop(&directory);
    }
    Ok(())
}

pub(super) fn apply(directory: &Path, colors: &Colors) -> Result<()> {
    let foreground = colors
        .get("term0")
        .map(|bg| ink(bg, colors.get("term7")))
        .unwrap_or_else(|| {
            colors
                .get("term7")
                .cloned()
                .unwrap_or_else(|| "default".into())
        });
    let tmux = update_tmux(directory, colors, &foreground);
    let btop = update_btop(colors, &foreground);
    tmux.and(btop)
}
