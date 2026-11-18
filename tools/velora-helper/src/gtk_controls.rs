//! Only manage GTK window controls while the user's own button layout is unset.
use anyhow::Result;
use gio::{prelude::*, Settings, SettingsSchemaSource};
use rustix::fs::{flock, FlockOperation};
use std::fs::{self, OpenOptions};

pub fn run(mode: &str) -> Result<()> {
    const KEY: &str = "button-layout";
    let enable = matches!(mode, "floating" | "canvas");
    let dir = crate::platform::state_home().join("velora");
    let marker = dir.join("gtk-window-controls.json");
    if !enable && !marker.exists() {
        return Ok(());
    }
    let Some(schema) = SettingsSchemaSource::default()
        .and_then(|s| s.lookup("org.gnome.desktop.wm.preferences", true))
        .filter(|s| s.has_key(KEY))
    else {
        return Ok(());
    };
    let prefs = Settings::new_full(&schema, None::<&gio::SettingsBackend>, None);
    fs::create_dir_all(&dir)?;
    let lock = OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join("gtk-window-controls.lock"))?;
    flock(&lock, FlockOperation::LockExclusive)?;
    let layout = prefs.string(KEY);
    if !enable {
        let installed = fs::read(&marker)
            .ok()
            .and_then(|b| serde_json::from_slice::<String>(&b).ok());
        if installed.as_deref() == Some(layout.as_str()) {
            prefs.reset(KEY);
            Settings::sync();
        }
        if marker.exists() {
            fs::remove_file(marker)?;
        }
    } else if prefs.user_value(KEY).is_none() && prefs.is_writable(KEY) {
        let (left, right) = layout.split_once(':').unwrap_or((layout.as_str(), ""));
        let mut buttons: Vec<_> = right.split(',').filter(|b| !b.is_empty()).collect();
        let mut index = buttons
            .iter()
            .position(|&b| b == "close")
            .unwrap_or(buttons.len());
        for button in ["minimize", "maximize"] {
            if !buttons.contains(&button) && !left.split(',').any(|b| b == button) {
                buttons.insert(index, button);
                index += 1;
            }
        }
        let managed = format!("{left}:{}", buttons.join(","));
        if managed != layout.as_str() {
            let mut temporary = tempfile::NamedTempFile::new_in(&dir)?;
            serde_json::to_writer(&mut temporary, &managed)?;
            temporary.persist(&marker)?;
            if let Err(e) = prefs.set_string(KEY, &managed) {
                fs::remove_file(marker)?;
                return Err(e.into());
            }
            Settings::sync();
        }
    }
    Ok(())
}
