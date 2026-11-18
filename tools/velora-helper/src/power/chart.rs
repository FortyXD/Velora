use super::{Sample, GAP, METRICS, RETENTION};
use serde_json::{json, Value};
use std::collections::BTreeSet;

fn extrema(samples: &[Sample], start: usize, end: usize, selected: &mut BTreeSet<usize>) {
    if start == end {
        return;
    }
    selected.extend([start, end - 1]);
    for metric in 0..METRICS.len() {
        let mut min = None;
        let mut max = None;
        for (i, s) in samples[start..end].iter().enumerate() {
            if let Some(n) = s.metrics[metric] {
                if min.is_none_or(|(x, _)| n < x) {
                    min = Some((n, start + i));
                }
                if max.is_none_or(|(x, _)| n > x) {
                    max = Some((n, start + i));
                }
            }
        }
        selected.extend(min.into_iter().chain(max).map(|(_, i)| i));
    }
}

fn downsample(samples: &[Sample], limit: usize) -> Vec<Value> {
    if samples.len() <= limit {
        return samples.iter().map(Sample::json).collect();
    }
    let mut selected = BTreeSet::new();
    extrema(samples, 0, samples.len(), &mut selected);
    let buckets = ((limit - selected.len()) / (2 + 2 * METRICS.len())).max(1);
    let start = samples[0].time;
    let scale = buckets as f64 / (samples.last().unwrap().time - start).max(1e-9);
    let bucket = |t: f64| (((t - start) * scale) as usize).min(buckets - 1);
    let mut candidates = BTreeSet::new();
    let mut left = 0;
    for right in 1..=samples.len() {
        if right == samples.len() || bucket(samples[left].time) != bucket(samples[right].time) {
            extrema(samples, left, right, &mut candidates);
            left = right;
        }
    }
    for i in candidates {
        if selected.len() == limit {
            break;
        }
        selected.insert(i);
    }
    let mut gaps: Vec<_> = (1..samples.len()).filter(|&i| samples[i].gap).collect();
    gaps.sort_by(|&a, &b| {
        (samples[b].time - samples[b - 1].time).total_cmp(&(samples[a].time - samples[a - 1].time))
    });
    for i in gaps {
        for j in [i, i - 1] {
            if selected.len() < limit {
                selected.insert(j);
            }
        }
    }
    let mut from = 0;
    selected
        .into_iter()
        .map(|i| {
            let mut point = samples[i].json();
            let span = &samples[from..=i];
            if span.iter().any(|s| s.gap) {
                point["gap_before"] = json!(true);
            }
            let missing: Vec<_> = METRICS
                .iter()
                .enumerate()
                .filter_map(|(k, name)| span.iter().any(|s| s.metrics[k].is_none()).then_some(name))
                .collect();
            if !missing.is_empty() {
                point["gaps_before"] = json!(missing);
            }
            from = i + 1;
            point
        })
        .collect()
}

fn stats(samples: &[Sample]) -> Value {
    let powers = || samples.iter().filter_map(|s| s.metrics[0]);
    let mut energy = None;
    for p in samples.windows(2) {
        let dt = p[1].time - p[0].time;
        let (Some(a), Some(b)) = (p[0].metrics[0], p[1].metrics[0]) else {
            continue;
        };
        if p[1].gap || dt <= 0. || dt > GAP {
            continue;
        }
        let (input, output) = energy.get_or_insert((0., 0.));
        let areas = if a * b < 0. {
            let mid = dt * a.abs() / (a.abs() + b.abs());
            [a * mid / 2., b * (dt - mid) / 2.]
        } else {
            [(a + b) * dt / 2., 0.]
        };
        for n in areas {
            if n < 0. {
                *input -= n / 3600.;
            } else {
                *output += n / 3600.;
            }
        }
    }
    let count = powers().count();
    json!({"power_min":powers().reduce(f64::min),"power_max":powers().reduce(f64::max),"power_mean":(count>0).then(||powers().sum::<f64>()/count as f64),
        "energy_in_wh":energy.map(|e|e.0),"energy_out_wh":energy.map(|e|e.1)})
}

pub(super) fn snapshot<'a>(
    records: impl Iterator<Item = &'a (u64, Sample)>,
    now: f64,
    window: u32,
    limit: usize,
) -> Value {
    let start = now - f64::from(window).min(RETENTION);
    let mut records: Vec<_> = records
        .filter(|(_, s)| s.time >= start && s.time <= now)
        .cloned()
        .collect();
    records.sort_by(|(a, x), (b, y)| x.time.total_cmp(&y.time).then_with(|| a.cmp(b)));
    let mut previous = None;
    let samples: Vec<_> = records
        .into_iter()
        .map(|(seq, mut s)| {
            if previous.is_some_and(|(n, t)| Some(n) != seq.checked_sub(1) || s.time - t > GAP) {
                s.gap = true;
            }
            previous = Some((seq, s.time));
            s
        })
        .collect();
    json!({"latest":samples.last().map(Sample::json),"window_start":now-f64::from(window),"window_end":now,
        "sample_count":samples.len(),"stats":stats(&samples),"points":downsample(&samples,limit)})
}
