//! Port of scripts/hardware/backlight.py: finds the backlight belonging to a DRM output, including on hybrid
//! laptops, where a backlight's GPU may not be the one driving the panel.

use anyhow::{anyhow, bail, Result};
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};

struct Connector {
    name: String,
    resolved: PathBuf,
    status: String,
}

fn connectors(drm: &Path) -> Vec<Connector> {
    let Ok(entries) = fs::read_dir(drm) else { return Vec::new() };
    let mut found = Vec::new();
    for entry in entries.filter_map(Result::ok) {
        let name = entry.file_name().to_string_lossy().into_owned();
        // `card0-eDP-1`, not `card0` or `renderD128`
        let is_connector = name.strip_prefix("card").is_some_and(|rest| rest.contains('-'));
        let Ok(status) = fs::read_to_string(entry.path().join("status")) else { continue };
        if is_connector {
            found.push(Connector { resolved: fs::canonicalize(entry.path()).unwrap_or_else(|_| entry.path()), name, status: status.trim().to_string() });
        }
    }
    found
}

fn kind_rank(kind: &str) -> u8 {
    match kind {
        "firmware" => 0,
        "platform" => 1,
        "raw" => 2,
        _ => 3,
    }
}

fn read_number(path: &Path) -> Result<i64> {
    Ok(fs::read_to_string(path)?.trim().parse()?)
}

pub fn for_output(output: &str, backlights: &Path, drm: &Path) -> Result<(String, i64, i64)> {
    let connectors = connectors(drm);
    let output_of = |connector: &Connector| connector.name.split_once('-').map(|(_, rest)| rest.to_string()).unwrap_or_default();
    let is_active = |connector: &Connector| output_of(connector) == output && connector.status == "connected";
    let any_active = connectors.iter().any(is_active);
    let internal = ["eDP-", "LVDS-", "DSI-"].iter().any(|prefix| output.starts_with(prefix));

    let mut candidates: Vec<(u8, u8, String, PathBuf)> = Vec::new();
    for entry in fs::read_dir(backlights)?.filter_map(Result::ok) {
        let device = entry.path();
        let path = fs::canonicalize(&device)?;
        let owner = fs::canonicalize(device.join("device")).unwrap_or_default();
        // Native backlights can sit below their connector; NVIDIA's can sit directly below the GPU even
        // when that GPU has no connected panel.
        let direct: Vec<&Connector> = connectors.iter().filter(|connector| path.ancestors().skip(1).any(|parent| parent == connector.resolved)).collect();
        let rank = if !direct.is_empty() {
            if !direct.iter().any(|connector| is_active(connector)) {
                continue;
            }
            0
        } else {
            let on_gpu: Vec<&Connector> = connectors
                .iter()
                .filter(|connector| connector.resolved.parent().and_then(|card| fs::canonicalize(card.join("device")).ok()).is_some_and(|gpu| gpu == owner))
                .collect();
            if !on_gpu.is_empty() {
                if !internal || !on_gpu.iter().any(|connector| is_active(connector)) {
                    continue;
                }
                1
            } else if internal && any_active {
                // ACPI and vendor backlights need not have a DRM parent
                2
            } else {
                continue;
            }
        };
        let kind = fs::read_to_string(device.join("type"))?;
        candidates.push((rank, kind_rank(kind.trim()), entry.file_name().to_string_lossy().into_owned(), device));
    }
    candidates.sort();
    let (_, _, name, device) = candidates.into_iter().next().ok_or_else(|| anyhow!("No backlight for {output}"))?;
    let current = read_number(&device.join("brightness"))?;
    let maximum = read_number(&device.join("max_brightness"))?;
    if maximum <= 0 || !(0..=maximum).contains(&current) {
        bail!("Invalid brightness reported by {name}");
    }
    Ok((name, current, maximum))
}

pub fn run(argv: Vec<String>) -> Result<()> {
    let output = argv.first().ok_or_else(|| anyhow!("usage: velora-helper backlight <output>"))?;
    let root = |name: &str, default: &str| std::env::var_os(name).map_or_else(|| PathBuf::from(default), PathBuf::from);
    let (device, current, maximum) = for_output(output, &root("VELORA_SYS_BACKLIGHT", "/sys/class/backlight"), &root("VELORA_SYS_DRM", "/sys/class/drm"))?;
    println!("{}", json!({ "device": device, "current": current, "max": maximum }));
    Ok(())
}
