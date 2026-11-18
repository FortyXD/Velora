//! Opt-in battery telemetry. Preserve the existing little-endian VPWR0001 ring.
mod chart;
mod storage;

use crate::args::Args;
use anyhow::{bail, ensure, Result};
use serde_json::{json, Value};
use std::{
    fs,
    path::Path,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const METRICS: [&str; 5] = [
    "battery_power_w",
    "percentage",
    "voltage_v",
    "energy_wh",
    "temperature_c",
];
const STATUSES: [&str; 6] = [
    "unknown",
    "charging",
    "discharging",
    "full",
    "not-charging",
    "mixed",
];
const RETENTION: f64 = 28800.;
const GAP: f64 = 6.;

#[derive(Clone, Default)]
struct Sample {
    time: f64,
    metrics: [Option<f64>; 5],
    status: u8,
    ac: Option<bool>,
    gap: bool,
    error: String,
}

impl Sample {
    fn json(&self) -> Value {
        let mut v = json!({"timestamp":self.time,"status":STATUSES[self.status as usize],"ac_online":self.ac});
        for (k, val) in METRICS.iter().zip(self.metrics) {
            v[k] = json!(val);
        }
        if self.gap {
            v["gap_before"] = json!(true);
        }
        if !self.error.is_empty() {
            v["error"] = json!(self.error);
        }
        v
    }
}

fn sample(root: &Path, time: f64) -> Result<(Sample, Vec<String>)> {
    let mut s = Sample {
        time,
        ..Sample::default()
    };
    let mut paths = fs::read_dir(root)?
        .map(|e| e.map(|e| e.path()))
        .collect::<std::io::Result<Vec<_>>>()?;
    paths.sort();
    let mut packs = Vec::new();
    let mut names = Vec::new();
    let mut online = Vec::new();
    for path in paths {
        let text = |key: &str| {
            fs::read_to_string(path.join(key))
                .ok()
                .map(|s| s.trim().to_owned())
        };
        let number = |key: &str| text(key)?.parse::<f64>().ok().filter(|v| v.is_finite());
        let micro = |key: &str| number(key).map(|n| n / 1e6);
        let scope = text("scope");
        if scope
            .as_deref()
            .is_some_and(|s| s.eq_ignore_ascii_case("device"))
        {
            continue;
        }
        match text("type").as_deref() {
            Some("Mains" | "USB" | "USB_C" | "USB_PD" | "USB_PD_DRP" | "Wireless") => {
                online.push(number("online").and_then(|v| match v {
                    0. => Some(false),
                    1. => Some(true),
                    _ => None,
                }));
                continue;
            }
            Some("Battery") => {}
            _ => continue,
        }
        let name = path.file_name().unwrap_or_default().to_string_lossy();
        if !(scope.as_deref() == Some("System")
            || matches!(scope.as_deref(), None | Some("Unknown")) && name.starts_with("BAT"))
            || number("present") == Some(0.)
        {
            continue;
        }
        names.push(name.into_owned());
        let state = text("status")
            .unwrap_or_default()
            .to_lowercase()
            .replace(' ', "-");
        let state = STATUSES[..5].iter().position(|s| *s == state).unwrap_or(0) as u8;
        let voltage = micro("voltage_now").filter(|v| *v > 0.);
        let energy = |energy, charge| {
            micro(energy)
                .filter(|v| *v >= 0.)
                .or_else(|| Some(micro(charge).filter(|v| *v >= 0.)? * voltage?))
        };
        let now = energy("energy_now", "charge_now");
        let full = energy("energy_full", "charge_full");
        let power = micro("power_now")
            .or_else(|| Some(micro("current_now")? * voltage?))
            .and_then(|v| match state {
                1 => Some(-v.abs()),
                2 => Some(v.abs()),
                _ if v == 0. => Some(0.),
                _ => None,
            });
        let percentage = now
            .zip(full.filter(|v| *v > 0.))
            .map(|(n, f)| n / f * 100.)
            .or_else(|| number("capacity"))
            .map(|v| v.clamp(0., 100.));
        packs.push((
            state,
            full,
            [
                power,
                percentage,
                voltage,
                now,
                number("temp").map(|v| v / 10.),
            ],
        ));
    }
    s.ac = if online.contains(&Some(true)) {
        Some(true)
    } else if !online.is_empty() && online.iter().all(|v| *v == Some(false)) {
        Some(false)
    } else {
        None
    };
    if packs.is_empty() {
        s.error = "No system battery telemetry available".into();
        return Ok((s, names));
    }
    s.status = if packs.iter().all(|p| p.0 == packs[0].0) {
        packs[0].0
    } else {
        5
    };
    s.metrics[0] = packs.iter().map(|p| p.2[0]).sum();
    s.metrics[3] = packs.iter().map(|p| p.2[3]).sum();
    if let Some(volts) = packs.iter().map(|p| p.2[2]).collect::<Option<Vec<_>>>() {
        if volts.iter().copied().fold(f64::NEG_INFINITY, f64::max)
            - volts.iter().copied().fold(f64::INFINITY, f64::min)
            < 1e-6
        {
            s.metrics[2] = Some(volts[0]);
        }
    }
    s.metrics[4] = packs.iter().filter_map(|p| p.2[4]).reduce(f64::max);
    s.metrics[1] = if packs.len() == 1 {
        packs[0].2[1]
    } else {
        let weighted: Option<f64> = packs
            .iter()
            .map(|p| Some(p.1.filter(|v| *v > 0.)? * p.2[1]?))
            .sum();
        weighted
            .zip(packs.iter().map(|p| p.1).sum::<Option<f64>>())
            .map(|(p, f)| p / f)
    };
    if s.metrics.iter().all(Option::is_none) {
        s.error = "System battery measurements unavailable".into();
    }
    Ok((s, names))
}

fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}
fn boot() -> f64 {
    let mut ts = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &mut ts) };
    ts.tv_sec as f64 + ts.tv_nsec as f64 * 1e-9
}

pub fn run(mut argv: Vec<String>) -> Result<std::process::ExitCode> {
    ensure!(!argv.is_empty(), "expected a power analytics command");
    let cmd = argv.remove(0);
    let args = Args::parse(argv, &[])?;
    let dir = Path::new(args.require("state-dir")?);
    if cmd == "clear" {
        storage::clear(dir)?;
        return Ok(std::process::ExitCode::SUCCESS);
    }
    let root = Path::new(
        args.value("sysfs-root")
            .unwrap_or("/sys/class/power_supply"),
    );
    let points = args.number("points", 300usize)?;
    let window = args.number("window-seconds", 1200u32)?;
    ensure!(
        (12..=300).contains(&points) && matches!(window, 1200 | 3600 | 28800),
        "invalid power history range"
    );
    let mut ring = match cmd.as_str() {
        "collect" => Some(storage::Ring::new(dir)?),
        "watch" => None,
        _ => bail!("unknown power command {cmd}"),
    };
    // Signals interrupt the two-second wait without polling and let the owner release its lock.
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let mut previous = None;
    let mut history = storage::History::default();
    runtime.block_on(async {
        use tokio::signal::unix::{signal, SignalKind};
        let mut term = signal(SignalKind::terminate())?;
        let mut interrupt = signal(SignalKind::interrupt())?;
        let mut timer = tokio::time::interval(Duration::from_secs(2));
        timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            tokio::select! {
                biased;
                _ = term.recv() => break,
                _ = interrupt.recv() => break,
                _ = timer.tick() => {}
            }
            let time = now();
            if let Some(ring) = &mut ring {
                let boot = boot();
                let (mut reading, topology) = sample(root, time).unwrap_or_else(|error| {
                    let message = format!("Battery telemetry unavailable: {error}")
                        .chars()
                        .take(48)
                        .collect();
                    (
                        Sample {
                            time,
                            error: message,
                            ..Sample::default()
                        },
                        Vec::new(),
                    )
                });
                reading.gap = previous.as_ref().is_none_or(|(b, t, top)| {
                    boot - b > GAP || time <= *t || time - t > GAP || *top != topology
                });
                ring.append(reading)?;
                previous = Some((boot, time, topology));
            } else {
                let data = match history.read(dir) {
                    Ok(records) => chart::snapshot(records.iter(), time, window, points),
                    Err(error) => {
                        let mut empty = chart::snapshot(std::iter::empty(), time, window, points);
                        empty["error"] =
                            json!(error.to_string().chars().take(160).collect::<String>());
                        empty
                    }
                };
                println!("{data}");
            }
        }
        Ok(std::process::ExitCode::SUCCESS)
    })
}
