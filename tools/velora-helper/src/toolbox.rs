//! Port of scripts/toolbox/open.sh and quick.sh: opening the toolbox, and converting files from the file
//! manager's menu with a notification when done. Also the two quick questions the window asks of
//! folis_toolbox.py as you use it; the conversions stay there, where the tools take all the time.

use crate::apps::{capture, which};
use anyhow::{anyhow, Result};
use serde_json::{json, Map, Value};
use std::path::{Path, PathBuf};
use std::time::Duration;
use std::process::{Command, ExitCode, Stdio};

fn shell_dir() -> PathBuf {
    std::env::var_os("VELORA_SHELL_DIR").map_or_else(
        || {
            let config = std::env::var_os("XDG_CONFIG_HOME").map_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config"), PathBuf::from);
            config.join("quickshell/ii")
        },
        PathBuf::from,
    )
}

const TOOLS: [&str; 24] = ["magick", "ffmpeg", "ffprobe", "soffice", "libreoffice", "pandoc", "pdftoppm", "pdfinfo", "qpdf", "gs",
    "7z", "bsdtar", "zstd", "yt-dlp", "qrencode", "zbarimg", "tesseract", "hyprpicker", "grim", "slurp",
    "wl-copy", "wl-paste", "kdialog", "file"];
const DOCUMENT_EXTENSIONS: [&str; 20] = ["doc", "docx", "odt", "rtf", "txt", "md", "markdown", "html", "htm", "epub", "ods", "xls", "xlsx",
    "odp", "ppt", "pptx", "csv", "tex", "rst", "org"];
const ARCHIVE_EXTENSIONS: [&str; 13] = ["zip", "7z", "rar", "tar", "gz", "tgz", "xz", "txz", "bz2", "tbz2", "zst", "tzst", "iso"];

/// Which of the tools the window's pages need are installed.
pub fn caps() -> Result<()> {
    let tools: Map<String, Value> = TOOLS.iter()
        .map(|tool| (tool.to_string(), which(tool).map_or(Value::Null, |path| json!(path.to_string_lossy()))))
        .collect();
    println!("{}", Value::Object(tools));
    Ok(())
}

fn extension_of(path: &str) -> String {
    let name = path.rsplit('/').next().unwrap_or_default().to_lowercase();
    if let Some(double) = ["tar.gz", "tar.zst", "tar.xz", "tar.bz2"].iter().find(|double| name.ends_with(&format!(".{double}"))) {
        return double.to_string();
    }
    name.rsplit_once('.').map_or(String::new(), |(_, extension)| extension.to_string())
}

fn kind_of(path: &str, extension: &str, mime: &str) -> &'static str {
    let is_archive = ARCHIVE_EXTENSIONS.contains(&extension) || extension.starts_with("tar.") || ["zip", "x-7z", "x-tar", "rar"].iter().any(|part| mime.contains(part));
    let is_document = DOCUMENT_EXTENSIONS.contains(&extension) || mime.starts_with("text/") || ["officedocument", "opendocument", "msword"].iter().any(|part| mime.contains(part));
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

fn duration_of(path: &str) -> f64 {
    let arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", "--", path];
    capture("ffprobe", &arguments, Duration::from_secs(30)).and_then(|(_, output)| output.trim().parse().ok()).unwrap_or(0.0)
}

/// What each file is, for the converter page.
pub fn detect(files: Vec<String>) -> Result<()> {
    let mut result = Vec::new();
    for path in &files {
        let mime = capture("file", &["--brief", "--mime-type", "--", path], Duration::from_secs(10)).map_or(String::new(), |(_, output)| output.trim().to_string());
        let extension = extension_of(path);
        let kind = kind_of(path, &extension, &mime);
        let meta = std::fs::metadata(path).ok().filter(std::fs::Metadata::is_file);
        let mut entry = json!({
            "path": path,
            "name": path.trim_end_matches('/').rsplit('/').next().unwrap_or_default(),
            "kind": kind,
            "mime": if kind == "folder" { "inode/directory" } else { mime.as_str() },
            "ext": extension,
            "size": meta.map_or(0, |meta| meta.len()),
        });
        if kind == "video" || kind == "audio" {
            entry["duration"] = json!(duration_of(path));
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
    let files: String = arguments.map(|file| std::fs::canonicalize(&file).map_or(file, |path| path.display().to_string()) + "\n").collect();
    let running = Command::new("qs").arg("-p").arg(&toolbox).args(["ipc", "call", "toolbox", "open", &tab, &files]).stdout(Stdio::null()).stderr(Stdio::null()).status();
    if running.is_ok_and(|status| status.success()) {
        let _ = Command::new("hyprctl").args(["dispatch", r#"hl.dsp.focus({ window = "title:^(Folis Toolbox)$" })"#]).stdout(Stdio::null()).stderr(Stdio::null()).status();
        return Ok(ExitCode::SUCCESS);
    }
    let status = Command::new("qs").arg("-p").arg(&toolbox).env("TOOLBOX_TAB", &tab).env("TOOLBOX_FILES", &files).status()?;
    Ok(if status.success() { ExitCode::SUCCESS } else { ExitCode::FAILURE })
}

/// What a backend line reports: a file done, or an error about one.
#[derive(Debug, PartialEq, Eq)]
enum Line {
    Done(String),
    Failed(String),
    Other,
}

fn parse_line(line: &str) -> Line {
    let Ok(value) = serde_json::from_str::<Value>(line) else { return Line::Other };
    match value["event"].as_str() {
        Some("done") => value["output"].as_str().map_or(Line::Other, |output| Line::Done(output.to_string())),
        Some("error") => {
            let file = value["file"].as_str().unwrap_or_default().rsplit('/').next().unwrap_or_default().to_string();
            Line::Failed(format!("{file}: {}", value["message"].as_str().unwrap_or_default()))
        }
        _ => Line::Other,
    }
}

/// `quick <target> files…`
pub fn quick(argv: Vec<String>) -> Result<ExitCode> {
    let mut arguments = argv.into_iter();
    let target = arguments.next().filter(|target| !target.is_empty()).ok_or_else(|| anyhow!("usage: velora-helper toolbox-quick <target> files…"))?;
    let files: Vec<String> = arguments.collect();
    if files.is_empty() {
        return Ok(ExitCode::FAILURE);
    }
    let backend = shell_dir().join("scripts/toolbox/folis_toolbox.py");
    let output = Command::new("/usr/bin/python3").arg("-I").arg(&backend).args(["convert", "--to", &target, "--"]).args(&files).stderr(Stdio::piped()).output()?;
    let mut outputs = Vec::new();
    let mut errors = Vec::new();
    for line in String::from_utf8_lossy(&output.stdout).lines().chain(String::from_utf8_lossy(&output.stderr).lines()) {
        match parse_line(line) {
            Line::Done(path) => outputs.push(path),
            Line::Failed(message) => errors.push(message),
            Line::Other => {}
        }
    }
    let upper = target.to_uppercase();
    if !errors.is_empty() {
        let _ = Command::new("notify-send").args(["-a", "Folis Toolbox", "-i", "dialog-error", &format!("Couldn't convert to {upper}"), &errors.join("\n")]).status();
    }
    if let Some(first) = outputs.first() {
        let title = if outputs.len() > 1 { format!("{} files converted to {upper}", outputs.len()) } else { format!("Converted to {upper}") };
        let lower = first.to_lowercase();
        let icon = if [".png", ".jpg", ".jpeg"].iter().any(|extension| lower.ends_with(extension)) { first.as_str() } else { "document-save" };
        let name = first.rsplit('/').next().unwrap_or_default();
        let action = Command::new("notify-send").args(["-a", "Folis Toolbox", "-i", icon, "-A", "show=Show", &title, name]).output()?;
        if String::from_utf8_lossy(&action.stdout).trim() == "show" {
            let items = outputs.iter().map(|path| format!("file://{path}")).collect::<Vec<_>>().join(",");
            let _ = Command::new("dbus-send")
                .args(["--session", "--dest=org.freedesktop.FileManager1", "--type=method_call", "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems", &format!("array:string:{items}"), "string:"])
                .status();
        }
    }
    Ok(ExitCode::SUCCESS)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backend_lines_are_read_by_their_event() {
        assert_eq!(parse_line(r#"{"event":"done","output":"/x/a.png"}"#), Line::Done("/x/a.png".to_string()));
        assert_eq!(parse_line(r#"{"event":"error","file":"/x/a.png","message":"bad"}"#), Line::Failed("a.png: bad".to_string()));
        assert_eq!(parse_line(r#"{"event":"error","message":"bad"}"#), Line::Failed(": bad".to_string()));
        assert_eq!(parse_line(r#"{"event":"progress"}"#), Line::Other);
        assert_eq!(parse_line("not json"), Line::Other);
    }
}
