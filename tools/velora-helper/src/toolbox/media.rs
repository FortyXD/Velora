use super::{duration_of, Args, Events};
use crate::subprocess;
use anyhow::{ensure, Result};
use serde_json::json;
use std::path::Path;
use tokio::process::Command;

fn time(text: Option<&str>) -> Result<Option<f64>> {
    text.filter(|v| !v.is_empty())
        .map(|v| {
            let mut seconds = 0.;
            for part in v.trim().split(':') {
                seconds = 60. * seconds + part.parse::<f64>()?;
            }
            ensure!(seconds.is_finite() && seconds >= 0., "Invalid time {v}");
            Ok(seconds)
        })
        .transpose()
}

fn codecs(cmd: &mut Command, target: &str, args: &Args, duration: f64) -> Result<()> {
    let height = args.value("height");
    let fps = args.value("fps");
    let bitrate = args.value("bitrate");
    if target == "gif" {
        let scale = height.map_or_else(|| "scale=640:-1".into(), |h| format!("scale=-2:{h}"));
        cmd.arg("-vf").arg(format!("fps={},{scale}:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer", fps.unwrap_or("12"))).args(["-loop", "0", "-an"]);
        return Ok(());
    }
    let audio: &[&str] = match target {
        "mp3" if bitrate.is_some() => &["-c:a", "libmp3lame", "-b:a", bitrate.unwrap_or("192k")],
        "mp3" => &["-c:a", "libmp3lame", "-q:a", "2"],
        "opus" => &["-c:a", "libopus", "-b:a", bitrate.unwrap_or("128k")],
        "ogg" => &["-c:a", "libvorbis", "-q:a", "5"],
        "flac" => &["-c:a", "flac"],
        "wav" => &["-c:a", "pcm_s16le"],
        "m4a" => &["-c:a", "aac", "-b:a", bitrate.unwrap_or("192k")],
        _ => &[],
    };
    if !audio.is_empty() {
        cmd.arg("-vn").args(audio);
        return Ok(());
    }
    let filters = [
        height.map(|h| format!("scale=-2:{h}")),
        fps.map(|f| format!("fps={f}")),
    ];
    let filters: Vec<_> = filters.into_iter().flatten().collect();
    if !filters.is_empty() {
        cmd.arg("-vf").arg(filters.join(","));
    }
    let crf: u8 = args.number("crf", 23)?;
    let size: f64 = args.number("target-size", 0.)?;
    if target == "webm" {
        cmd.args([
            "-c:v",
            "libvpx-vp9",
            "-row-mt",
            "1",
            "-deadline",
            "good",
            "-cpu-used",
            "4",
        ]);
        if size <= 0. || duration <= 0. {
            cmd.arg("-crf")
                .arg((u16::from(crf) + 9).to_string())
                .args(["-b:v", "0"]);
        }
        cmd.args(["-c:a", "libopus", "-b:a", "128k"]);
    } else {
        cmd.args([
            "-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p",
        ]);
        if size <= 0. || duration <= 0. {
            cmd.arg("-crf").arg(crf.to_string());
        }
        cmd.args(["-c:a", "aac", "-b:a", "160k"]);
        if target == "mp4" {
            cmd.args(["-movflags", "+faststart"]);
        }
    }
    if size > 0. && duration > 0. {
        let audio = if args.flag("no-audio") { 0 } else { 128 };
        let kbps = (size * 8192. / duration - f64::from(audio)).clamp(100., 1e9) as u64;
        cmd.arg("-b:v")
            .arg(format!("{kbps}k"))
            .arg("-maxrate")
            .arg(format!("{}k", kbps * 12 / 10))
            .arg("-bufsize")
            .arg(format!("{}k", kbps * 2));
        if audio > 0 {
            cmd.args(["-b:a", "128k"]);
        }
    }
    if args.flag("no-audio") {
        cmd.arg("-an");
    }
    Ok(())
}

pub async fn convert(
    src: &str,
    target: &str,
    part: &Path,
    args: &Args,
    index: usize,
    events: Events<'_>,
) -> Result<()> {
    let start = time(args.value("start"))?;
    let end = time(args.value("end"))?;
    let duration = match end {
        Some(end) => end,
        None => duration_of(src).await,
    } - start.unwrap_or_default();
    let mut cmd = Command::new("ffmpeg");
    cmd.args(["-hide_banner", "-nostdin", "-y"]);
    if let Some(s) = start {
        cmd.arg("-ss").arg(s.to_string());
    }
    if let Some(e) = end {
        cmd.arg("-to").arg(e.to_string());
    }
    cmd.args(["-i", src]);
    codecs(&mut cmd, target, args, duration)?;
    cmd.args(["-progress", "pipe:1", "-nostats"]).arg(part);
    let mut last = None;
    subprocess::stream(&mut cmd, |err, line| {
        if err || duration <= 0. {
            return;
        }
        let Some(time) = line
            .strip_prefix("out_time_us=")
            .or_else(|| line.strip_prefix("out_time_ms="))
            .and_then(|x| x.parse::<f64>().ok())
        else {
            return;
        };
        let percent = (time / (duration * 1e4)).clamp(0., 99.) as u32;
        if last != Some(percent) {
            last = Some(percent);
            events(json!({"event":"progress","index":index,"file":src,"percent":percent}));
        }
    })
    .await
}
