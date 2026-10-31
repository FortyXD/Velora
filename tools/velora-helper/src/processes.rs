//! Port of scripts/system/top-apps.sh: this user's processes with their CPU use, sampled over half a second, and
//! proportional memory (PSS), which splits shared pages so per-app sums don't count libraries many times.
//! Prints "N <cpu count>", then "pid<TAB>cpu %<TAB>pss kB<TAB>command" per process.

use anyhow::Result;
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

/// utime + stime from a /proc/<pid>/stat line, whose command name may itself contain spaces and parentheses.
fn cpu_ticks(stat: &str) -> Option<u64> {
    let after_name = stat.rsplit_once(')')?.1;
    let mut fields = after_name.split_whitespace();
    let utime: u64 = fields.nth(11)?.parse().ok()?;
    let stime: u64 = fields.next()?.parse().ok()?;
    Some(utime + stime)
}

fn pss_kb(smaps_rollup: &str) -> i64 {
    smaps_rollup.lines().find_map(|line| line.strip_prefix("Pss:")).and_then(|rest| rest.trim().trim_end_matches("kB").trim().parse().ok()).unwrap_or(0)
}

fn my_processes(proc_root: &Path, uid: u32) -> Vec<(u32, PathBuf)> {
    let Ok(entries) = fs::read_dir(proc_root) else { return Vec::new() };
    entries
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let pid: u32 = entry.file_name().to_str()?.parse().ok()?;
            (entry.metadata().ok()?.uid() == uid).then(|| (pid, entry.path()))
        })
        .collect()
}

fn sample(processes: &[(u32, PathBuf)]) -> HashMap<u32, u64> {
    processes.iter().filter_map(|(pid, path)| Some((*pid, cpu_ticks(&fs::read_to_string(path.join("stat")).ok()?)?))).collect()
}

/// Percent of one CPU, as `top` shows it, from clock ticks over a time.
fn cpu_percent(before: u64, after: u64, elapsed: Duration, ticks_per_second: f64) -> f64 {
    let seconds = elapsed.as_secs_f64();
    if seconds <= 0.0 {
        return 0.0;
    }
    (after.saturating_sub(before) as f64 / ticks_per_second) / seconds * 100.0
}

pub fn run() -> Result<()> {
    let proc_root = std::env::var_os("VELORA_PROC").map_or_else(|| PathBuf::from("/proc"), PathBuf::from);
    let cpus = std::thread::available_parallelism().map_or(1, |count| count.get());
    let mut report = format!("N {cpus}\n");
    let uid = fs::metadata(&proc_root)?.uid().max(fs::metadata("/proc/self")?.uid());
    let processes = my_processes(&proc_root, uid);
    let first = sample(&processes);
    let started = Instant::now();
    std::thread::sleep(Duration::from_millis(500));
    let second = sample(&processes);
    let elapsed = started.elapsed();
    for (pid, path) in &processes {
        let (Some(before), Some(after)) = (first.get(pid), second.get(pid)) else { continue };
        let name = fs::read_to_string(path.join("comm")).unwrap_or_default();
        let pss = fs::read_to_string(path.join("smaps_rollup")).map(|text| pss_kb(&text)).unwrap_or(0);
        // USER_HZ is 100 on every platform Linux runs Velora on
        report.push_str(&format!("{pid}\t{:.1}\t{pss}\t{}\n", cpu_percent(*before, *after, elapsed, 100.0), name.trim()));
    }
    // A reader that stopped reading isn't an error here
    let _ = std::io::stdout().write_all(report.as_bytes());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stat_fields_are_found_after_the_name_whatever_it_holds() {
        let line = "123 (a (b) c) S 1 123 123 0 -1 4194560 1 2 3 4 700 42 0 0 20 0 1 0 5 6 7";
        assert_eq!(cpu_ticks(line), Some(742));
        assert_eq!(cpu_ticks("garbage"), None);
    }

    #[test]
    fn proportional_memory_comes_from_its_line() {
        assert_eq!(pss_kb("100-200 ---p 00000000 00:00 0  [rollup]\nRss:  10 kB\nPss:   4096 kB\nDirty: 1 kB\n"), 4096);
        assert_eq!(pss_kb(""), 0);
    }

    #[test]
    fn cpu_is_a_percent_of_one_core() {
        assert_eq!(cpu_percent(100, 150, Duration::from_millis(500), 100.0), 100.0);
        assert_eq!(cpu_percent(100, 100, Duration::from_millis(500), 100.0), 0.0);
        assert_eq!(cpu_percent(150, 100, Duration::from_millis(500), 100.0), 0.0);
        assert_eq!(cpu_percent(0, 1, Duration::ZERO, 100.0), 0.0);
    }
}
