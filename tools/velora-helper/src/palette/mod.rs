//! Apply generated desktop colors, avoiding redundant writes and terminal notifications.
mod kde;
mod programs;
mod terminals;
use crate::apps::{config_home, shell_config_path, state_home};
use anyhow::{ensure, Result};
use regex::Regex;
use rustix::fs::{flock, FlockOperation};
use serde_json::Value;
use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io::{ErrorKind, Write},
    path::{Path, PathBuf},
};

fn generated() -> PathBuf {
    state_home().join("quickshell/user/generated")
}
fn settings() -> Result<Value> {
    match fs::read(shell_config_path()) {
        Ok(text) => {
            let value: Value = serde_json::from_slice(&text)?;
            ensure!(value.is_object(), "Settings must be an object");
            Ok(value)
        }
        Err(e) if e.kind() == ErrorKind::NotFound => Ok(Value::Null),
        Err(e) => Err(e.into()),
    }
}
fn optional(path: &Path) -> Result<Vec<u8>> {
    match fs::read(path) {
        Ok(b) => Ok(b),
        Err(e) if e.kind() == ErrorKind::NotFound => Ok(vec![]),
        Err(e) => Err(e.into()),
    }
}
fn publish(path: &Path, new: &[u8]) -> Result<bool> {
    if optional(path)? == new {
        return Ok(false);
    }
    if new.is_empty() {
        fs::remove_file(path)?;
    } else {
        let mut tmp = tempfile::NamedTempFile::new_in(path.parent().unwrap())?;
        tmp.write_all(new)?;
        tmp.persist(path)?;
    }
    Ok(true)
}
fn lock(dir: &Path, name: &str) -> Result<File> {
    fs::create_dir_all(dir)?;
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join(name))?;
    flock(&file, FlockOperation::LockExclusive)?;
    Ok(file)
}
fn hex(v: &str) -> bool {
    v.len() == 7 && v.starts_with('#') && v.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit)
}
fn scss(path: &Path) -> Result<BTreeMap<String, String>> {
    let pattern = Regex::new(r"(?m)^\$(\w+):\s*(#[0-9a-fA-F]{6});[ \t]*$")?;
    Ok(pattern
        .captures_iter(&fs::read_to_string(path)?)
        .map(|c| (c[1].into(), c[2].into()))
        .collect())
}
pub use kde::apply as kde;
pub use terminals::apply as terminals;

pub fn kvantum(mode: &str) -> Result<()> {
    let colors = scss(&generated().join("material_colors.scss"))?;
    let shades: &[(&str, &str)] = match mode {
        "light" => &[
            ("#3c84f7", "primary"),
            ("#000000", "shadow"),
            ("#f04a50", "error"),
            ("#4285f4", "primaryFixedDim"),
            ("#f2f2f2", "background"),
            ("#ffffff", "background"),
            ("#1e1e1e", "onPrimaryFixed"),
            ("#333", "inverseSurface"),
            ("#212121", "onSecondaryFixed"),
            ("#5b9bf8", "secondaryContainer"),
            ("#26272a", "term7"),
            ("#444444", "onBackground"),
            ("#333333", "onPrimaryFixed"),
        ],
        "dark" => &[
            ("#31363b", "background"),
            ("#000000", "shadow"),
            ("#5b9bf8", "primary"),
            ("#93cee9", "onSecondaryContainer"),
            ("#3daee9", "secondary"),
            ("#ffffff", "term11"),
            ("#5a616e", "surfaceVariant"),
            ("#f04a50", "error"),
            ("#4285f4", "secondary"),
            ("#242424", "background"),
            ("#2c2c2c", "background"),
            ("#1e1e1e", "background"),
            ("#3c3c3c", "background"),
            ("#26272a", "surfaceBright"),
            ("#000000", "shadow"),
            ("#b74aff", "tertiary"),
            ("#1a1a1a", "background"),
            ("#333", "term0"),
            ("#212121", "background"),
        ],
        _ => anyhow::bail!("Unknown Kvantum variant"),
    };
    let home = config_home().join("Kvantum");
    let mut svg = fs::read_to_string(home.join(if mode == "dark" {
        "Colloid/ColloidDark.svg"
    } else {
        "Colloid/Colloid.svg"
    }))?;
    // Match whole CSS hex literals in a single pass; never recolor a replacement value.
    let palette = shades
        .iter()
        .map(|(old, new)| {
            Ok((
                *old,
                colors
                    .get(*new)
                    .ok_or_else(|| anyhow::anyhow!("Missing color {new}"))?,
            ))
        })
        .collect::<Result<BTreeMap<_, _>>>()?;
    let literals = Regex::new(r"(?i)#[0-9a-f]{6}\b|#[0-9a-f]{3}\b")?;
    svg = literals
        .replace_all(&svg, |m: &regex::Captures| {
            palette
                .get(m[0].to_ascii_lowercase().as_str())
                .map_or_else(|| m[0].to_owned(), |c| (*c).clone())
        })
        .into_owned();
    publish(&home.join("MaterialAdw/MaterialAdw.svg"), svg.as_bytes())?;
    Ok(())
}

/// Apply the named SCSS roles to an existing MaterialAdw Kvantum configuration.
pub fn kvantum_config() -> Result<()> {
    let dir = config_home().join("Kvantum/MaterialAdw");
    let path = dir.join("MaterialAdw.kvconfig");
    let colors = scss(&generated().join("material_colors.scss"))?;
    let mappings = [
        ("window.color", "background"),
        ("base.color", "background"),
        ("alt.base.color", "background"),
        ("button.color", "surfaceContainer"),
        ("light.color", "surfaceContainerLow"),
        ("mid.light.color", "surfaceContainer"),
        ("dark.color", "surfaceContainerHighest"),
        ("mid.color", "surfaceContainerHigh"),
        ("highlight.color", "primary"),
        ("inactive.highlight.color", "primary"),
        ("text.color", "onBackground"),
        ("window.text.color", "onBackground"),
        ("button.text.color", "onBackground"),
        ("disabled.text.color", "onBackground"),
        ("tooltip.text.color", "onBackground"),
        ("highlight.text.color", "onSurface"),
        ("link.color", "tertiary"),
        ("link.visited.color", "tertiaryFixed"),
        ("progress.indicator.text.color", "onBackground"),
        ("text.normal.color", "onBackground"),
        ("text.focus.color", "onBackground"),
        ("text.press.color", "onsecondarycontainer"),
        ("text.toggle.color", "onsecondarycontainer"),
        ("text.disabled.color", "surfaceDim"),
    ];
    let mut lines: Vec<String> = fs::read_to_string(&path)?
        .lines()
        .map(str::to_owned)
        .collect();
    for (key, role) in mappings {
        let Some(color) = colors.get(role) else {
            continue;
        };
        let prefix = format!("{key}=");
        let value = format!("{prefix}{color}");
        let mut found = false;
        for line in &mut lines {
            if line.starts_with(&prefix) {
                line.clone_from(&value);
                found = true;
            }
        }
        if !found {
            lines.push(value);
        }
    }
    publish(&path, format!("{}\n", lines.join("\n")).as_bytes())?;
    Ok(())
}
