//! CPU-time attribution only while the power analytics table is open.
use crate::processes::{cpu_ticks, my_processes};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    fs,
    path::Path,
    time::Instant,
};

pub(super) struct Snapshot {
    at: Instant,
    total: Option<u64>,
    // PID plus start time distinguishes a reused PID from its predecessor.
    tasks: HashMap<(u32, u64), (String, u64)>,
    packages: BTreeMap<String, (u64, u64)>,
}

impl Snapshot {
    pub fn read() -> Self {
        let proc = Path::new("/proc");
        let total = fs::read_to_string(proc.join("stat")).ok().and_then(|stat| {
            let mut line = stat.lines().next()?.split_whitespace();
            (line.next() == Some("cpu")).then_some(())?;
            line.take(8).map(|field| field.parse::<u64>().ok()).sum()
        });
        let tasks = my_processes(proc, rustix::process::getuid().as_raw())
            .into_iter()
            .filter_map(|(pid, dir)| {
                let stat = fs::read_to_string(dir.join("stat")).ok()?;
                let (head, fields) = stat.rsplit_once(')')?;
                let start = fields.split_whitespace().nth(19)?.parse().ok()?;
                let executable = fs::read_link(dir.join("exe")).ok();
                let name = executable
                    .as_deref()
                    .and_then(Path::file_name)
                    .and_then(|n| n.to_str())
                    .or_else(|| head.split_once('(').map(|(_, comm)| comm))?;
                Some(((pid, start), (name.to_owned(), cpu_ticks(&stat)?)))
            })
            .collect();
        let mut packages = BTreeMap::new();
        for domain in fs::read_dir("/sys/class/powercap")
            .into_iter()
            .flatten()
            .flatten()
        {
            let dir = domain.path();
            let num = |key: &str| {
                fs::read_to_string(dir.join(key))
                    .ok()?
                    .trim()
                    .parse::<u64>()
                    .ok()
            };
            let Ok(name) = fs::read_to_string(dir.join("name")) else {
                continue;
            };
            // A package can also be published through a second (MMIO) interface.
            // Key by hardware package and skip subdomains such as cores and DRAM.
            if name.trim().starts_with("package-") {
                if let (Some(value), Some(max)) = (num("energy_uj"), num("max_energy_range_uj")) {
                    packages
                        .entry(name.trim().to_string())
                        .or_insert((value, max));
                }
            }
        }
        Self {
            at: Instant::now(),
            total,
            tasks,
            packages,
        }
    }

    fn package_watts(&self, old: &Self, seconds: f64) -> Option<f64> {
        if self.packages.is_empty() || self.packages.keys().ne(old.packages.keys()) {
            return None;
        }
        let mut energy = 0.0;
        for (name, &(value, max)) in &self.packages {
            let (previous, old_max) = old.packages[name];
            if old_max != max || max == 0 || value > max || previous > max {
                return None;
            }
            energy += if value >= previous {
                value - previous
            } else {
                max - previous + value
            } as f64;
        }
        Some(energy / 1e6 / seconds)
    }
}

pub(super) fn estimate(old: Option<&Snapshot>, new: &Snapshot, battery: &Value, now: f64) -> Value {
    let Some(old) = old else {
        return json!({"source":"sampling","rows":[]});
    };
    let seconds = new.at.duration_since(old.at).as_secs_f64();
    let ticks = new
        .total
        .zip(old.total)
        .and_then(|(b, a)| b.checked_sub(a))
        .unwrap_or(0);
    if seconds <= 0.0 || seconds > super::GAP || ticks == 0 {
        return json!({"source":"sampling","rows":[]});
    }
    let battery_watts = || {
        let age = now - battery["timestamp"].as_f64()?;
        if battery["status"] != "discharging" || !(0.0..=seconds.max(1.0)).contains(&age) {
            return None;
        }
        battery["battery_power_w"]
            .as_f64()
            .filter(|watts| *watts >= 0.0)
    };
    let measured = battery_watts();
    let (source, watts) = if let Some(w) = new.package_watts(old, seconds) {
        ("package", Some(measured.map_or(w, |total| w.min(total))))
    } else if let Some(w) = measured {
        ("battery", Some(w))
    } else {
        ("unavailable", None)
    };
    let mut groups = BTreeMap::<&str, u64>::new();
    for (id, (name, cpu)) in &new.tasks {
        let used = old
            .tasks
            .get(id)
            .filter(|(before, _)| before == name)
            .map_or(0, |(_, previous)| cpu.saturating_sub(*previous));
        *groups.entry(name).or_default() += used;
    }
    let mut groups: Vec<_> = groups.into_iter().collect();
    groups.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0)));
    let denominator = ticks.max(groups.iter().map(|(_, value)| value).sum::<u64>()) as f64;
    let rows: Vec<_> = groups
        .into_iter()
        .map(|(name, delta)| {
            let share = delta as f64 / denominator;
            json!({"name":name,"cpu":share * 100.0,"watts":watts.map(|w| w * share)})
        })
        .collect();
    let attributed = watts.map(|_| rows.iter().filter_map(|r| r["watts"].as_f64()).sum::<f64>());
    json!({"source":source,"battery_w":measured,"applications_w":attributed,
           "system_w":measured.zip(attributed).map(|(total, apps)| (total-apps).max(0.0)), "rows":rows})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn estimates_preserve_idle_time_group_tasks_and_ignore_reused_pids() {
        let at = Instant::now();
        let mut old = Snapshot {
            at,
            total: Some(100),
            tasks: HashMap::new(),
            packages: BTreeMap::new(),
        };
        let mut new = Snapshot {
            at: at + std::time::Duration::from_secs(2),
            total: Some(200),
            tasks: HashMap::new(),
            packages: BTreeMap::new(),
        };
        for (pid, start, before, after) in [(1, 1, 10, 30), (2, 1, 30, 50), (3, 2, 5, 90)] {
            old.tasks.insert((pid, 1), ("Kate".into(), before));
            new.tasks.insert((pid, start), ("Kate".into(), after));
        }
        let battery = json!({"timestamp":99.0,"status":"discharging","battery_power_w":20.0});
        let v = estimate(Some(&old), &new, &battery, 100.0);
        assert_eq!(v["rows"][0]["watts"], 8.0);
        assert_eq!(v["battery_w"], 20.0);
        assert_eq!(v["applications_w"].as_f64().unwrap() + v["system_w"].as_f64().unwrap(), 20.0);
        assert!(estimate(Some(&old), &new, &battery, 109.0)["rows"][0]["watts"].is_null());
        old.packages
            .insert("package-0".into(), (95_000_000, 100_000_000));
        new.packages
            .insert("package-0".into(), (15_000_000, 100_000_000));
        assert_eq!(
            estimate(Some(&old), &new, &Value::Null, 100.0)["rows"][0]["watts"],
            4.0
        );
    }
}
