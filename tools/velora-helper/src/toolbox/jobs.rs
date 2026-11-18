use super::{
    convert::{stem, Destination},
    identify, one, Args, Events,
};
use crate::subprocess;
use anyhow::{ensure, Context, Result};
use serde_json::{json, Value};
use std::{
    fs,
    path::{Path, PathBuf},
};
use tokio::process::Command;

pub async fn run(name: &str, argv: Vec<String>, events: Events<'_>) -> Result<()> {
    let args = Args::parse(argv, &["pdf", "playlist", "subs"])?;
    let input = one(&args)?;
    let result = match name {
        "download" | "info" => {
            if name == "download" {
                events(json!({"event":"start","file":input}));
                match download(input, &args, events).await {
                    Ok(path) => events(json!({"event":"done","file":input,"output":path})),
                    Err(error) => {
                        events(json!({"event":"error","file":input,"message":error.to_string()}))
                    }
                }
                json!({"event":"finished"})
            } else {
                args.reject_unknown(&["proxy"])?;
                let mut cmd = Command::new("yt-dlp");
                cmd.args([
                    "--no-playlist",
                    "--skip-download",
                    "--print",
                    "%(title)s\t%(duration_string)s\t%(uploader)s",
                ]);
                url(&mut cmd, input, &args);
                let data = subprocess::output(&mut cmd).await?;
                let mut fields = data
                    .lines()
                    .last()
                    .context("yt-dlp returned no media info")?
                    .split('\t');
                json!({"event":"info","title":fields.next(),"duration":fields.next().unwrap_or(""),"uploader":fields.next().unwrap_or("")})
            }
        }
        "qr-encode" => {
            args.reject_unknown(&["size", "out"])?;
            let path = args
                .value("out")
                .map(PathBuf::from)
                .unwrap_or_else(|| std::env::temp_dir().join("folis-qr.png"));
            let parent = path
                .parent()
                .filter(|p| !p.as_os_str().is_empty())
                .unwrap_or(Path::new("."));
            fs::create_dir_all(parent)?;
            let tmp = tempfile::NamedTempFile::new_in(parent)?;
            subprocess::run(Command::new("qrencode").arg("-o").arg(tmp.path()).args([
                "-s",
                args.value("size").unwrap_or("10"),
                "-m",
                "2",
                "-l",
                "M",
                "--",
                input,
            ]))
            .await?;
            tmp.persist(&path)?;
            json!({"event":"done","output":path})
        }
        "qr-scan" => {
            args.reject_unknown(&[])?;
            let text =
                subprocess::output(Command::new("zbarimg").args(["--quiet", "--raw", "--", input]))
                    .await
                    .context("No QR code found")?;
            let text = text.trim_end_matches('\n');
            ensure!(!text.is_empty(), "No QR code found");
            json!({"event":"done","output":text})
        }
        "ocr" => {
            args.reject_unknown(&["lang", "pdf"])?;
            ocr(input, &args, events).await?
        }
        "palette" => {
            args.reject_unknown(&["colors"])?;
            let count: usize = args.number("colors", 8)?;
            let src = std::path::absolute(input)?;
            let mut colors = Vec::new();
            subprocess::stream(
                Command::new("magick")
                    .arg(format!("{}[0]", src.display()))
                    .args([
                        "-resize",
                        "200x200",
                        "+dither",
                        "-colors",
                        &count.to_string(),
                        "-depth",
                        "8",
                        "-format",
                        "%c",
                        "histogram:info:-",
                    ]),
                |err, line| {
                    if err {
                        return;
                    }
                    if let Some((freq, rest)) = line.split_once(':') {
                        let color = rest.split_once('#').and_then(|(_, hex)| hex.get(..6));
                        if let (Ok(n), Some(hex)) = (
                            freq.trim().parse::<u64>(),
                            color.filter(|hex| hex.bytes().all(|b| b.is_ascii_hexdigit())),
                        ) {
                            colors.push((n, format!("#{}", hex.to_ascii_uppercase())));
                        }
                    }
                },
            )
            .await?;
            colors.sort_unstable_by(|a, b| b.cmp(a));
            json!({"event":"done","colors":colors.into_iter().take(count).map(|(_,c)| c).collect::<Vec<_>>()})
        }
        _ => unreachable!(),
    };
    events(result);
    Ok(())
}

fn url(cmd: &mut Command, input: &str, args: &Args) {
    if let Some(proxy) = args.value("proxy") {
        cmd.args(["--proxy", proxy]);
    }
    cmd.args(["--", input]);
}

async fn download(input: &str, args: &Args, events: Events<'_>) -> Result<PathBuf> {
    args.reject_unknown(&[
        "mode",
        "quality",
        "audio-format",
        "subs",
        "playlist",
        "proxy",
        "out-dir",
    ])?;
    let dir = args.value("out-dir").map(PathBuf::from).unwrap_or_else(|| {
        PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join("Videos/Downloads")
    });
    let dir = std::path::absolute(dir)?;
    fs::create_dir_all(&dir)?;
    let mut cmd = Command::new("yt-dlp");
    cmd.args([
        "--newline",
        "--progress",
        if args.flag("playlist") {
            "--yes-playlist"
        } else {
            "--no-playlist"
        },
        "--progress-template",
        "download:PROGRESS %(progress._percent_str)s %(progress._speed_str)s %(progress._eta_str)s",
        "-o",
    ])
    .arg(dir.join("%(title).150B [%(id)s].%(ext)s"))
    .args(["--print", "after_move:filepath"]);
    match args.value("mode").unwrap_or("video") {
        "audio" => {
            cmd.args([
                "-x",
                "--audio-format",
                args.value("audio-format").unwrap_or("mp3"),
                "--audio-quality",
                "0",
            ]);
        }
        "video" => {
            let h = args.value("quality").unwrap_or("1080");
            cmd.arg("-f")
                .arg(format!("bv*[height<={h}]+ba/b[height<={h}]/b"))
                .args(["--merge-output-format", "mp4"]);
        }
        mode => anyhow::bail!("Unknown download mode {mode}"),
    }
    if args.flag("subs") {
        cmd.args([
            "--write-subs",
            "--write-auto-subs",
            "--sub-langs",
            "ru.*,en.*",
            "--embed-subs",
        ]);
    }
    url(&mut cmd, input, args);
    let mut saved = dir;
    subprocess::stream(&mut cmd, |err, line| {
        if let Some(progress) = line.strip_prefix("PROGRESS ") {
            let mut fields = progress.split_whitespace();
            if let Some(percent) = fields.next().and_then(|s| s.trim_end_matches('%').parse::<f64>().ok()) {
                events(json!({"event":"progress","file":input,"percent":percent as u32,"speed":fields.next().unwrap_or(""),"eta":fields.next().unwrap_or("")}));
            }
        } else if !err && line.starts_with('/') && Path::new(line).exists() {
            saved = line.into();
        } else if line.starts_with("[download] Destination:") || line.starts_with("[Merger]") {
            events(json!({"event":"status","file":input,"message":line}));
        }
    }).await?;
    Ok(saved)
}

async fn ocr(input: &str, args: &Args, events: Events<'_>) -> Result<Value> {
    let available = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        subprocess::output(Command::new("tesseract").arg("--list-langs")),
    )
    .await
    .ok()
    .and_then(Result::ok)
    .unwrap_or_default();
    let langs: Vec<_> = available
        .lines()
        .skip(1)
        .map(str::trim)
        .filter(|s| !s.is_empty() && *s != "osd")
        .collect();
    let wanted: Vec<_> = args
        .value("lang")
        .unwrap_or("eng+rus")
        .split('+')
        .filter(|s| langs.contains(s))
        .collect();
    let lang = if wanted.is_empty() {
        langs.first().copied().unwrap_or("eng").to_owned()
    } else {
        wanted.join("+")
    };
    let path = std::path::absolute(input)?;
    let src = path.to_str().context("invalid file name")?;
    let tmp = if identify(src).await.0 == "pdf" {
        Some(tempfile::tempdir()?)
    } else {
        None
    };
    let pages = if let Some(dir) = &tmp {
        let dir = dir.path();
        subprocess::run(
            Command::new("pdftoppm")
                .args(["-r", "300", "-png", src])
                .arg(dir.join("page")),
        )
        .await?;
        let mut pages = fs::read_dir(dir)?
            .map(|e| e.map(|e| e.path()))
            .collect::<std::io::Result<Vec<_>>>()?;
        pages.sort();
        ensure!(!pages.is_empty(), "PDF has no pages");
        pages
    } else {
        vec![path.clone()]
    };
    if args.flag("pdf") {
        let dest = Destination::new(
            path.parent().context("missing directory")?,
            &format!("{}-searchable", stem(src)),
            "pdf",
        )?;
        let input = if pages.len() == 1 {
            pages[0].clone()
        } else {
            let list = tmp.as_ref().unwrap().path().join("pages.txt");
            fs::write(
                &list,
                pages
                    .iter()
                    .map(|p| p.to_string_lossy())
                    .collect::<Vec<_>>()
                    .join("\n"),
            )?;
            list
        };
        subprocess::run(
            Command::new("tesseract")
                .arg(input)
                .arg(dest.part().with_extension(""))
                .args(["-l", &lang, "pdf"]),
        )
        .await?;
        return Ok(json!({"event":"done","output":dest.publish()?,"language":lang}));
    }
    let mut texts = Vec::new();
    for (index, page) in pages.iter().enumerate() {
        events(json!({"event":"progress","percent":index * 100 / pages.len()}));
        let text = subprocess::output(Command::new("tesseract").arg(page).args(["-", "-l", &lang]))
            .await?;
        if !text.trim().is_empty() {
            texts.push(text.trim().to_owned());
        }
    }
    Ok(json!({"event":"done","language":lang,"text":texts.join("\n\n")}))
}
