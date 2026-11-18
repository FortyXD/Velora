//! Metadata and bounded local decoding for the standalone Quick Look window.
use crate::{
    apps::file_uri,
    args::Args,
    subprocess::{interruptible, ChildGroup},
};
use anyhow::{ensure, Context, Result};
use serde_json::{json, Value};
use std::{
    fs::{self, File},
    io::{Read, Seek},
    path::Path,
    process::{ExitCode, Stdio},
    time::{Duration, UNIX_EPOCH},
};
use tokio::process::Command;

const TEXT_LIMIT: usize = 256 * 1024;

fn prefix(reader: impl Read, limit: usize) -> Result<(String, bool)> {
    let mut data = Vec::new();
    reader.take(limit as u64 + 1).read_to_end(&mut data)?;
    let truncated = data.len() > limit;
    data.truncate(limit);
    Ok((String::from_utf8_lossy(&data).into_owned(), truncated))
}

async fn decode(cmd: &mut Command, limit: usize) -> Result<(String, bool)> {
    let mut file = tempfile::tempfile()?;
    cmd.stdin(Stdio::null())
        .stderr(Stdio::null())
        .stdout(file.try_clone()?);
    // SAFETY: setrlimit is called only in the forked decoder before exec.
    unsafe {
        cmd.pre_exec(|| {
            for (resource, size) in [(libc::RLIMIT_AS, 1 << 30), (libc::RLIMIT_FSIZE, 32 << 20)] {
                if libc::setrlimit(
                    resource,
                    &libc::rlimit {
                        rlim_cur: size,
                        rlim_max: size,
                    },
                ) == -1
                {
                    return Err(std::io::Error::last_os_error());
                }
            }
            Ok(())
        });
    }
    let mut child = ChildGroup::spawn(cmd)?;
    let status = tokio::time::timeout(Duration::from_secs(12), child.0.wait())
        .await
        .context("Decoder timed out")??;
    ensure!(status.success(), "The file could not be decoded");
    file.rewind()?;
    prefix(file, limit)
}

async fn inspect(info: &mut Value, path: &Path, dir: &Path, page: u32, request: u64) -> Result<()> {
    let stat = path.metadata()?;
    info["size"] = json!(stat.len());
    info["modified"] = json!(stat
        .modified()?
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or_default());
    if stat.is_dir() {
        let mut names = Vec::new();
        for entry in fs::read_dir(path)?.take(1000) {
            let entry = entry?;
            let mut name = entry.file_name().to_string_lossy().into_owned();
            if entry.file_type()?.is_dir() {
                name.push('/');
            }
            names.push(name);
        }
        names.sort();
        info["kind"] = json!("text");
        info["truncated"] = json!(names.len() == 1000);
        info["text"] = json!(names.join("\n"));
        return Ok(());
    }
    ensure!(stat.is_file(), "Only regular files can be previewed");
    let (mime, _) = decode(
        Command::new("file")
            .args(["--brief", "--mime-type", "--"])
            .arg(path),
        256,
    )
    .await?;
    let mime = mime.trim();
    info["mime"] = json!(mime);
    if mime == "application/pdf" {
        let (meta, _) = decode(Command::new("pdfinfo").arg(path), 16384).await?;
        let pages: u32 = meta
            .lines()
            .find_map(|l| l.strip_prefix("Pages:")?.trim().parse().ok())
            .context("PDF page count unavailable")?;
        ensure!(pages > 0, "PDF is empty");
        let page = page.clamp(1, pages);
        let temporary = tempfile::tempdir_in(dir)?;
        let output = temporary.path().join("page");
        decode(
            Command::new("pdftoppm")
                .args([
                    "-f",
                    &page.to_string(),
                    "-l",
                    &page.to_string(),
                    "-scale-to",
                    "1600",
                    "-singlefile",
                    "-png",
                ])
                .arg(path)
                .arg(&output),
            0,
        )
        .await?;
        let preview = dir.join(if request == 0 {
            format!("page-{page}.png")
        } else {
            format!("preview-{}.png", request % 2)
        });
        fs::rename(output.with_extension("png"), &preview)?;
        info["kind"] = json!("pdf");
        info["pages"] = json!(pages);
        info["page"] = json!(page);
        info["preview"] = json!(file_uri(&preview));
    } else if mime.starts_with("image/") {
        let guess = image::ImageReader::open(path)?
            .with_guessed_format()?
            .into_dimensions();
        let (w, h) = match guess {
            Ok(size) => size,
            Err(image::ImageError::Unsupported(_))
                if matches!(
                    mime,
                    "image/avif"
                        | "image/jp2"
                        | "image/vnd.adobe.photoshop"
                        | "image/x-pcx"
                        | "image/x-dds"
                ) =>
            {
                let (dimensions, _) = decode(
                    Command::new("magick")
                        .args(["identify", "-ping", "-format", "%w %h"])
                        .arg(format!("{}[0]", path.display())),
                    64,
                )
                .await?;
                let (width, height) = dimensions
                    .split_once(' ')
                    .context("Missing image dimensions")?;
                (width.trim().parse::<u32>()?, height.trim().parse::<u32>()?)
            }
            Err(error) => return Err(error.into()),
        };
        ensure!(
            u64::from(w) * u64::from(h) <= 32_000_000,
            "Image is too large for Quick Look"
        );
        info["width"] = json!(w);
        info["height"] = json!(h);
        info["kind"] = json!(if mime == "image/gif" { "gif" } else { "image" });
    } else if mime.starts_with("audio/") || mime.starts_with("video/") {
        info["kind"] = json!(mime.split('/').next());
    } else if ["zip", "tar", "tgz", "gz", "bz2", "xz", "7z", "rar", "zst"]
        .iter()
        .any(|e| {
            path.extension()
                .is_some_and(|ext| ext.eq_ignore_ascii_case(e))
        })
    {
        let (data, truncated) =
            decode(Command::new("bsdtar").arg("-tf").arg(path), TEXT_LIMIT).await?;
        let mut lines = data.lines();
        info["text"] = json!(lines.by_ref().take(1000).collect::<Vec<_>>().join("\n"));
        info["truncated"] = json!(truncated || lines.next().is_some());
        info["kind"] = json!("text");
    } else if mime.starts_with("text/")
        || matches!(
            mime,
            "application/json"
                | "application/xml"
                | "application/javascript"
                | "application/x-shellscript"
        )
    {
        let (data, truncated) = prefix(File::open(path)?, TEXT_LIMIT)?;
        info["text"] = json!(data);
        info["truncated"] = json!(truncated);
        info["kind"] = json!("text");
    }
    Ok(())
}

pub fn run(argv: Vec<String>) -> Result<ExitCode> {
    let args = Args::parse(argv, &[])?;
    ensure!(args.positional.len() == 1, "expected a path");
    let path = std::path::absolute(&args.positional[0])?;
    let dir = std::path::absolute(args.require("directory")?)?;
    let request = args.number("request-id", 0u64)?;
    let page = args.number("page", 1i64)?.clamp(1, u32::MAX as i64) as u32;
    interruptible(
        async {
            let mut info = json!({"path":path,"name":path.file_name().unwrap_or_default().to_string_lossy(),"url":file_uri(&path),"kind":"other","requestId":request});
            if let Err(error) = inspect(&mut info, &path, &dir, page, request).await {
                info["error"] = json!(error.to_string());
            }
            println!("{info}");
            Ok(ExitCode::SUCCESS)
        },
        || {},
    )
}
