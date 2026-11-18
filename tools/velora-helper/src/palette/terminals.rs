use super::*;
use rustix::process::{getuid, kill_process, Pid, Signal};
use std::{
    collections::BTreeSet,
    os::unix::fs::{FileTypeExt, MetadataExt, OpenOptionsExt},
    process::Command,
};
const ROLES: &str = include_str!("roles.txt");
type Colors = BTreeMap<String, String>;
fn luminance(hex: &str) -> f64 {
    [1, 3, 5]
        .into_iter()
        .zip([0.2126, 0.7152, 0.0722])
        .map(|(i, w)| {
            let v = f64::from(u8::from_str_radix(&hex[i..i + 2], 16).unwrap()) / 255.;
            w * if v <= 0.04045 {
                v / 12.92
            } else {
                ((v + 0.055) / 1.055).powf(2.4)
            }
        })
        .sum()
}
fn ink(bg: &str, preferred: Option<&String>) -> String {
    let bg = luminance(bg);
    if let Some(v) = preferred {
        let l = luminance(v);
        if (bg.max(l) + 0.05) / (bg.min(l) + 0.05) >= 4.5 {
            return v.clone();
        }
    }
    if bg > 0.179 {
        "#000000".into()
    } else {
        "#ffffff".into()
    }
}
fn build(dir: &Path, config: &Value) -> Result<Colors> {
    let theme = &config["appearance"]["wallpaperTheming"];
    if theme["enableTerminal"] == false {
        return Ok(Colors::new());
    }
    let dark = theme["terminalGenerationProps"]["forceDarkMode"] == true;
    let source = dir.join("material_colors.scss");
    let mut colors = if source.is_file() {
        let values = scss(&source)?;
        ensure!(
            (0..16).all(|i| values.contains_key(&format!("term{i}"))),
            "Incomplete terminal colors"
        );
        values
    } else {
        let data = optional(&dir.join("colors.json"))?;
        let mut values = Colors::new();
        if !data.is_empty() {
            let json: Value = serde_json::from_slice(&data)?;
            for (role, value) in json
                .as_object()
                .ok_or_else(|| anyhow::anyhow!("Invalid colors"))?
            {
                let Some(v) = value.as_str().filter(|v| hex(v)) else {
                    continue;
                };
                let mut pieces = role.split('_');
                let mut key = pieces.next().unwrap_or("").to_owned();
                for piece in pieces {
                    let mut letters = piece.chars();
                    if let Some(first) = letters.next() {
                        key.extend(first.to_uppercase());
                        key.push_str(letters.as_str());
                    }
                }
                values.insert(key, v.into());
            }
        }
        if !dark
            || values
                .get("surfaceContainer")
                .is_none_or(|c| luminance(c) < 0.5)
        {
            for (key, dest) in [("surfaceContainer", "term0"), ("onSurface", "term7")] {
                if let Some(v) = values.get(key).cloned() {
                    values.insert(dest.into(), v);
                }
            }
        }
        values
    };
    let overrides = &config["appearance"]["palette"]["roleOverrides"];
    for (key, dest, foreground) in [
        ("primary", "primary", "onPrimary"),
        ("secondary", "secondary", "onSecondary"),
        ("tertiary", "tertiary", "onTertiary"),
        ("surface_container", "term0", ""),
        ("on_surface", "term7", ""),
    ] {
        let Some(v) = overrides[key].as_str().filter(|v| hex(v)) else {
            continue;
        };
        if dest == "term0" && dark && luminance(v) >= 0.5 {
            continue;
        }
        let mut color = v.to_owned();
        if !foreground.is_empty() {
            colors.insert(foreground.into(), ink(v, colors.get(foreground)));
        } else if dest == "term7" && dark {
            color = ink(
                colors.get("term0").map(String::as_str).unwrap_or("#000000"),
                Some(&color),
            );
        }
        colors.insert(dest.into(), color);
    }
    Ok(colors)
}
fn sequence(key: &str, color: Option<&str>) -> String {
    let seq = if let Some(n) = key.strip_prefix("color").and_then(|v| v.parse::<u8>().ok()) {
        color.map_or_else(|| format!("104;{n}"), |c| format!("4;{n};{c}"))
    } else {
        let code = match key {
            "foreground" => 10,
            "background" => 11,
            "cursor" => 12,
            "selection_background" => 17,
            "selection_foreground" => 19,
            _ => return String::new(),
        };
        color.map_or_else(|| (100 + code).to_string(), |c| format!("{code};{c}"))
    };
    format!("\x1b]{seq}\x1b\\")
}
fn refresh(update: &str, kitty_reset: &str) -> Result<()> {
    if !["DISPLAY", "WAYLAND_DISPLAY"]
        .iter()
        .any(|k| std::env::var_os(k).is_some_and(|v| !v.is_empty()))
    {
        return Ok(());
    }
    let uid = getuid();
    let ps = Command::new("ps")
        .args([
            "-u",
            &uid.as_raw().to_string(),
            "-o",
            "pid=,ppid=,sid=,tty=,comm=",
        ])
        .output()?;
    ensure!(ps.status.success(), "Could not enumerate terminals");
    let listing = String::from_utf8_lossy(&ps.stdout);
    let mut parents = BTreeMap::new();
    let mut sessions = BTreeMap::new();
    for line in listing.lines() {
        let fields = line.split_whitespace().collect::<Vec<_>>();
        if let [pid, ppid, sid, tty, name, ..] = fields.as_slice() {
            parents.insert(*pid, *name);
            if pid == sid
                && tty
                    .strip_prefix("pts/")
                    .is_some_and(|id| !id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()))
            {
                sessions.insert(*tty, *ppid);
            }
        }
    }
    let mut signalled = BTreeSet::new();
    for (tty, ppid) in sessions {
        let data = match parents.get(ppid).copied() {
            Some("kitty") => {
                if signalled.insert(ppid) {
                    if let Some(pid) = ppid.parse().ok().and_then(Pid::from_raw) {
                        let _ = kill_process(pid, Signal::USR1);
                    }
                }
                kitty_reset
            }
            Some(
                "foot"
                | "alacritty"
                | "wezterm-gui"
                | "wezterm-mux-ser"
                | "wezterm-mux-server"
                | "konsole"
                | "kgx"
                | "gnome-terminal-"
                | "gnome-terminal-server"
                | "xterm"
                | "uxterm",
            ) => update,
            _ => continue,
        };
        if data.is_empty() {
            continue;
        }
        if let Ok(mut file) = OpenOptions::new()
            .write(true)
            .custom_flags(libc::O_NOCTTY | libc::O_NOFOLLOW | libc::O_NONBLOCK)
            .open(Path::new("/dev").join(tty))
        {
            if file
                .metadata()
                .is_ok_and(|m| m.uid() == uid.as_raw() && m.file_type().is_char_device())
            {
                let _ = file.write_all(data.as_bytes());
            }
        }
    }
    Ok(())
}
pub fn apply() -> Result<()> {
    let generated = generated();
    let dir = generated.join("terminal");
    let _lock = lock(&dir, ".palette.lock")?;
    let colors = build(&generated, &settings()?)?;
    let mut conf = String::new();
    let mut osc = String::new();
    let mut options = BTreeSet::new();
    for fields in ROLES
        .lines()
        .filter(|line| !line.starts_with('#'))
        .map(str::split_whitespace)
    {
        let mut fields = fields;
        let Some((key, value)) = fields
            .next()
            .zip(fields.next().and_then(|role| colors.get(role)))
        else {
            continue;
        };
        let value = value.to_ascii_lowercase();
        options.insert(key);
        conf.push_str(&format!("{key} {value}\n"));
        osc.push_str(&sequence(key, Some(&value)));
    }
    let theme = dir.join("kitty-theme.conf");
    let sequences = dir.join("sequences.txt");
    let old = optional(&theme)?;
    let previous = optional(&sequences)?;
    if old == conf.as_bytes() && previous == osc.as_bytes() {
        return Ok(());
    }
    let mut reset = String::new();
    let mut removed = String::new();
    for line in String::from_utf8_lossy(&old).lines() {
        let mut parts = line.split_whitespace();
        if let Some(key) = parts.next() {
            if parts.next().is_some_and(hex) {
                let s = sequence(key, None);
                reset.push_str(&s);
                if !options.contains(key) {
                    removed.push_str(&s);
                }
            }
        }
    }
    publish(&theme, conf.as_bytes())?;
    publish(&sequences, osc.as_bytes())?;
    removed.push_str(&osc);
    refresh(
        &removed,
        if previous.windows(6).any(|w| w == b"\x1b]708;") {
            &reset
        } else {
            ""
        },
    )
}
