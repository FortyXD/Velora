//! File manager actions and the jobs shared by the Toolbox pages.
mod convert;
mod jobs;
mod media;

use crate::apps::which;
use crate::args::Args;
use crate::subprocess::{interruptible, output};
use anyhow::{bail, ensure, Result};
use serde_json::{json, Map, Value};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::time::Duration;

fn shell_dir() -> PathBuf {
    std::env::var_os("VELORA_SHELL_DIR").map_or_else(
        || {
            let config = std::env::var_os("XDG_CONFIG_HOME").map_or_else(
                || PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config"),
                PathBuf::from,
            );
            config.join("quickshell/ii")
        },
        PathBuf::from,
    )
}

const TOOLS: [&str; 24] = [
    "magick",
    "ffmpeg",
    "ffprobe",
    "soffice",
    "libreoffice",
    "pandoc",
    "pdftoppm",
    "pdfinfo",
    "qpdf",
    "gs",
    "7z",
    "bsdtar",
    "zstd",
    "yt-dlp",
    "qrencode",
    "zbarimg",
    "tesseract",
    "hyprpicker",
    "grim",
    "slurp",
    "wl-copy",
    "wl-paste",
    "kdialog",
    "file",
];
const DOCUMENT_EXTENSIONS: [&str; 20] = [
    "doc", "docx", "odt", "rtf", "txt", "md", "markdown", "html", "htm", "epub", "ods", "xls",
    "xlsx", "odp", "ppt", "pptx", "csv", "tex", "rst", "org",
];
const ARCHIVE_EXTENSIONS: [&str; 13] = [
    "zip", "7z", "rar", "tar", "gz", "tgz", "xz", "txz", "bz2", "tbz2", "zst", "tzst", "iso",
];

/// Which of the tools the window's pages need are installed.
pub fn caps() -> Result<()> {
    let tools: Map<String, Value> = TOOLS
        .iter()
        .map(|tool| {
            (
                tool.to_string(),
                which(tool).map_or(Value::Null, |path| json!(path.to_string_lossy())),
            )
        })
        .collect();
    println!("{}", Value::Object(tools));
    Ok(())
}

fn extension_of(path: &str) -> String {
    let name = path
        .rsplit('/')
        .next()
        .unwrap_or_default()
        .to_ascii_lowercase();
    if let Some(double) = ["tar.gz", "tar.zst", "tar.xz", "tar.bz2"]
        .iter()
        .find(|double| name.ends_with(&format!(".{double}")))
    {
        return double.to_string();
    }
    name.rsplit_once('.')
        .map_or(String::new(), |(_, extension)| extension.to_string())
}

fn kind_of(path: &str, extension: &str, mime: &str) -> &'static str {
    let is_archive = ARCHIVE_EXTENSIONS.contains(&extension)
        || extension.starts_with("tar.")
        || ["zip", "x-7z", "x-tar", "rar"]
            .iter()
            .any(|part| mime.contains(part));
    let is_document = DOCUMENT_EXTENSIONS.contains(&extension)
        || mime.starts_with("text/")
        || ["officedocument", "opendocument", "msword"]
            .iter()
            .any(|part| mime.contains(part));
    if Path::new(path).is_dir() {
        "folder"
    } else if mime == "application/pdf" || extension == "pdf" {
        "pdf"
    } else if mime.starts_with("image/") || matches!(extension, "heic" | "heif" | "avif") {
        "image"
    } else if mime.starts_with("video/") {
        "video"
    } else if mime.starts_with("audio/") {
        "audio"
    } else if is_archive {
        "archive"
    } else if is_document {
        "document"
    } else {
        "other"
    }
}

async fn duration_of(path: &str) -> f64 {
    let mut cmd = tokio::process::Command::new("ffprobe");
    cmd.args([
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        "--",
        path,
    ]);
    tokio::time::timeout(Duration::from_secs(30), output(&mut cmd))
        .await
        .ok()
        .and_then(Result::ok)
        .and_then(|s| s.trim().parse::<f64>().ok())
        .filter(|n| n.is_finite() && *n > 0.0)
        .unwrap_or(0.0)
}

async fn identify(path: &str) -> (&'static str, String) {
    if Path::new(path).is_dir() {
        return ("folder", "inode/directory".into());
    }
    let extension = extension_of(path);
    let mut cmd = tokio::process::Command::new("file");
    cmd.args(["--brief", "--mime-type", "--", path]);
    let mime = tokio::time::timeout(Duration::from_secs(10), output(&mut cmd))
        .await
        .ok()
        .and_then(Result::ok)
        .unwrap_or_default();
    let mut mime = mime.trim().to_owned();
    if mime.is_empty() && !extension.is_empty() {
        if let Ok(types) = std::fs::read_to_string("/etc/mime.types") {
            for line in types.lines() {
                let mut fields = line
                    .split('#')
                    .next()
                    .unwrap_or_default()
                    .split_whitespace();
                let candidate = fields.next().unwrap_or_default();
                if fields.any(|ext| ext == extension) {
                    mime = candidate.to_owned();
                    break;
                }
            }
        }
    }
    (kind_of(path, &extension, &mime), mime)
}

pub fn detect(files: Vec<String>) -> Result<()> {
    interruptible(
        async {
            detect_files(&files).await?;
            Ok(ExitCode::SUCCESS)
        },
        || {},
    )?;
    Ok(())
}

async fn detect_files(files: &[String]) -> Result<()> {
    let mut result = Vec::new();
    for path in files {
        let (kind, mime) = identify(path).await;
        let extension = extension_of(path);
        let meta = std::fs::metadata(path)
            .ok()
            .filter(std::fs::Metadata::is_file);
        let mut entry = json!({
            "path": path,
            "name": path.trim_end_matches('/').rsplit('/').next().unwrap_or_default(),
            "kind": kind,
            "mime": if kind == "folder" { "inode/directory" } else { mime.as_str() },
            "ext": extension,
            "size": meta.map_or(0, |meta| meta.len()),
        });
        if kind == "video" || kind == "audio" {
            entry["duration"] = json!(duration_of(path).await);
        }
        result.push(entry);
    }
    println!("{}", Value::Array(result));
    Ok(())
}

/// `open [tab] [files…]`: a running toolbox gets the tab and files over IPC instead of a second window.
pub fn open(argv: Vec<String>) -> Result<ExitCode> {
    let toolbox = shell_dir().join("toolbox.qml");
    let mut arguments = argv.into_iter();
    let tab = arguments.next().unwrap_or_else(|| "converter".to_string());
    let files: String = arguments
        .map(|file| {
            std::fs::canonicalize(&file).map_or(file, |path| path.display().to_string()) + "\n"
        })
        .collect();
    let running = Command::new("qs")
        .arg("-p")
        .arg(&toolbox)
        .args(["ipc", "call", "toolbox", "open", &tab, &files])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    if running.is_ok_and(|status| status.success()) {
        let _ = Command::new("hyprctl")
            .args([
                "dispatch",
                r#"hl.dsp.focus({ window = "title:^(Folis Toolbox)$" })"#,
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        return Ok(ExitCode::SUCCESS);
    }
    let status = Command::new("qs")
        .arg("-p")
        .arg(&toolbox)
        .env("TOOLBOX_TAB", &tab)
        .env("TOOLBOX_FILES", &files)
        .status()?;
    Ok(if status.success() {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    })
}

type Events<'a> = &'a mut dyn FnMut(Value);

fn one(args: &Args) -> Result<&str> {
    ensure!(args.positional.len() == 1, "expected one input");
    Ok(&args.positional[0])
}

fn emit(event: Value) {
    println!("{event}");
}

pub fn job(mut argv: Vec<String>) -> Result<ExitCode> {
    ensure!(
        !argv.is_empty(),
        "usage: velora-helper toolbox <command> ..."
    );
    let name = argv.remove(0);
    interruptible(
        async {
            let result = match name.as_str() {
                "caps" => caps(),
                "detect" => detect_files(&argv).await,
                "convert" => convert::run(argv, &mut emit).await,
                "download" | "info" | "qr-encode" | "qr-scan" | "palette" | "ocr" => {
                    jobs::run(&name, argv, &mut emit).await
                }
                _ => bail!("unknown toolbox command {name}"),
            };
            if let Err(error) = result {
                emit(json!({"event":"error", "message":error.to_string()}));
                return Ok(ExitCode::FAILURE);
            }
            Ok(ExitCode::SUCCESS)
        },
        || emit(json!({"event":"cancelled"})),
    )
}

/// Convert from Dolphin and offer to reveal the results.
pub fn quick(mut argv: Vec<String>) -> Result<ExitCode> {
    ensure!(
        argv.len() >= 2,
        "usage: velora-helper toolbox-quick <target> files…"
    );
    let target = argv.remove(0);
    let mut arguments = vec!["--to".into(), target.clone(), "--".into()];
    arguments.extend(argv);
    let mut outputs = Vec::new();
    let mut errors = Vec::new();
    let code = interruptible(
        async {
            convert::run(arguments, &mut |event| match event["event"].as_str() {
                Some("done") => {
                    if let Some(path) = event["output"].as_str() {
                        outputs.push(path.to_owned());
                    }
                }
                Some("error") => {
                    let file = event["file"]
                        .as_str()
                        .unwrap_or_default()
                        .rsplit('/')
                        .next()
                        .unwrap_or_default();
                    errors.push(format!(
                        "{file}: {}",
                        event["message"].as_str().unwrap_or_default()
                    ));
                }
                _ => {}
            })
            .await?;
            Ok(ExitCode::SUCCESS)
        },
        || {},
    )?;
    if code != ExitCode::SUCCESS {
        return Ok(code);
    }
    let upper = target.to_uppercase();
    if !errors.is_empty() {
        let _ = Command::new("notify-send")
            .args([
                "-a",
                "Folis Toolbox",
                "-i",
                "dialog-error",
                &format!("Couldn't convert to {upper}"),
                &errors.join("\n"),
            ])
            .status();
    }
    if let Some(first) = outputs.first() {
        let title = if outputs.len() > 1 {
            format!("{} files converted to {upper}", outputs.len())
        } else {
            format!("Converted to {upper}")
        };
        let lower = first.to_lowercase();
        let icon = if [".png", ".jpg", ".jpeg"]
            .iter()
            .any(|extension| lower.ends_with(extension))
        {
            first.as_str()
        } else {
            "document-save"
        };
        let name = first.rsplit('/').next().unwrap_or_default();
        let action = Command::new("notify-send")
            .args([
                "-a",
                "Folis Toolbox",
                "-i",
                icon,
                "-A",
                "show=Show",
                &title,
                name,
            ])
            .output()?;
        if String::from_utf8_lossy(&action.stdout).trim() == "show" {
            let items = outputs
                .iter()
                .map(|path| format!("file://{path}"))
                .collect::<Vec<_>>()
                .join(",");
            let _ = Command::new("dbus-send")
                .args([
                    "--session",
                    "--dest=org.freedesktop.FileManager1",
                    "--type=method_call",
                    "/org/freedesktop/FileManager1",
                    "org.freedesktop.FileManager1.ShowItems",
                    &format!("array:string:{items}"),
                    "string:",
                ])
                .status();
        }
    }
    Ok(if errors.is_empty() {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    })
}
