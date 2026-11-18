use super::*;
use crate::apps::{data_home, read_ini};
use anyhow::Context;
use std::process::Command;

pub fn apply() -> Result<()> {
    if settings()?.pointer("/appearance/wallpaperTheming/enableQtApps") == Some(&Value::Bool(false))
    {
        return Ok(());
    }
    let dir = data_home().join("color-schemes");
    let _lock = lock(&dir, ".velora.lock")?;
    let colors: Value = serde_json::from_slice(&fs::read(generated().join("colors.json"))?)?;
    let get = |key: &str, fallback: &str| -> Result<&str> {
        colors
            .get(key)
            .or_else(|| colors.get(fallback))
            .and_then(Value::as_str)
            .filter(|s| hex(s))
            .with_context(|| format!("Invalid palette color: {key}"))
    };
    let mut groups = Vec::new();
    for (name, bg, fg) in [
        ("Window", "surface_container_low", "on_surface"),
        ("View", "surface_container_lowest", "on_surface"),
        ("Button", "surface_container_high", "on_surface"),
        ("Header", "surface_container", "on_surface"),
        ("Complementary", "surface_container", "on_surface"),
        ("Selection", "primary", "on_primary"),
        ("Tooltip", "inverse_surface", "inverse_on_surface"),
    ] {
        let special = matches!(name, "Selection" | "Tooltip");
        let mut keys = Vec::new();
        for (key, role, fallback) in [
            ("BackgroundNormal", bg, "background"),
            (
                "BackgroundAlternate",
                if special { bg } else { "surface_container" },
                "background",
            ),
            ("ForegroundNormal", fg, ""),
            ("ForegroundActive", if special { fg } else { "primary" }, ""),
            (
                "ForegroundInactive",
                if special { fg } else { "on_surface_variant" },
                "",
            ),
            ("ForegroundLink", "primary", ""),
            ("ForegroundVisited", "tertiary", ""),
            ("ForegroundNegative", "error", ""),
            ("ForegroundNeutral", "secondary", ""),
            ("ForegroundPositive", "tertiary", ""),
            ("DecorationFocus", "primary", ""),
            ("DecorationHover", "primary", ""),
        ] {
            keys.push((key, get(role, fallback)?));
        }
        groups.push((format!("Colors:{name}"), keys));
    }
    groups.push(("ColorEffects:Inactive".into(), vec![("Enable", "false")]));
    groups.push((
        "General".into(),
        vec![("Name", "Velora"), ("ColorScheme", "Velora")],
    ));
    let globals = config_home().join("kdeglobals");
    let stored = read_ini(&globals)?;
    let mut file = String::new();
    let mut edits = Vec::new();
    for (group, entries) in &groups {
        file.push_str(&format!("[{group}]\n"));
        let current = stored
            .iter()
            .filter(|(s, _)| s == group)
            .flat_map(|(_, lines)| lines.iter().filter_map(|l| l.split_once('=')))
            .collect::<BTreeMap<_, _>>();
        for &(key, value) in entries {
            file.push_str(&format!("{key}={value}\n"));
            if !(group == "General" && key == "Name") && current.get(key).copied() != Some(value) {
                edits.push((group, key, value));
            }
        }
        file.push('\n');
    }
    let changed = publish(&dir.join("Velora.colors"), file.as_bytes())?;
    if !changed && edits.is_empty() {
        return Ok(());
    }
    // KConfig merges individual keys and honors immutable settings.
    for (group, key, value) in edits {
        ensure!(
            Command::new("kwriteconfig6")
                .arg("--file")
                .arg(&globals)
                .args(["--group", group, "--key", key, value])
                .status()?
                .success(),
            "Could not set KDE color {key}"
        );
    }
    ensure!(
        Command::new("dbus-send")
            .args([
                "--session",
                "--type=signal",
                "/KGlobalSettings",
                "org.kde.KGlobalSettings.notifyChange",
                "int32:0",
                "int32:0"
            ])
            .status()?
            .success(),
        "Could not notify KDE"
    );
    Ok(())
}
