use super::{extension_of, identify, media, Args, Events};
use crate::{apps::which, subprocess};
use anyhow::{anyhow, bail, ensure, Context, Result};
use rustix::fs::{renameat_with, RenameFlags, CWD};
use serde_json::json;
use std::{
    fs,
    path::{Component, Path, PathBuf},
};
use tempfile::TempDir;
use tokio::process::Command;

pub(super) fn stem(path: &str) -> &str {
    let name = path
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or(path);
    let ext = extension_of(name);
    name.get(..name.len().saturating_sub(ext.len() + 1))
        .filter(|base| !base.is_empty() && !ext.is_empty())
        .unwrap_or(name)
}

/// All outputs, including page directories, are private until the external tool succeeds.
pub(super) struct Destination {
    scratch: TempDir,
    directory: PathBuf,
    base: String,
    suffix: String,
}

impl Destination {
    pub fn new(directory: &Path, base: &str, ext: &str) -> Result<Self> {
        ensure!(
            matches!(
                Path::new(base).components().collect::<Vec<_>>().as_slice(),
                [Component::Normal(_)]
            ) && !base.contains('/'),
            "invalid output name"
        );
        fs::create_dir_all(directory)?;
        Ok(Self {
            scratch: tempfile::Builder::new()
                .prefix(".velora-toolbox-")
                .tempdir_in(directory)?,
            directory: directory.to_owned(),
            base: base.into(),
            suffix: if ext.is_empty() {
                String::new()
            } else {
                format!(".{ext}")
            },
        })
    }

    pub fn part(&self) -> PathBuf {
        self.scratch
            .path()
            .join(format!("{}{}", self.base, self.suffix))
    }

    pub fn publish(self) -> Result<PathBuf> {
        let part = self.part();
        for counter in 0u64.. {
            let number = if counter == 0 {
                String::new()
            } else {
                format!("-{counter}")
            };
            let path = self
                .directory
                .join(format!("{}{number}{}", self.base, self.suffix));
            match renameat_with(CWD, &part, CWD, &path, RenameFlags::NOREPLACE) {
                Ok(()) => return Ok(path),
                Err(rustix::io::Errno::EXIST) => continue,
                Err(error) => return Err(error).context("Could not publish the output"),
            }
        }
        unreachable!()
    }
}

async fn image(src: &str, target: &str, dst: &Path, args: &Args) -> Result<()> {
    let multi =
        matches!(extension_of(src).as_str(), "gif" | "webp") && matches!(target, "gif" | "webp");
    let mut cmd = Command::new("magick");
    cmd.arg(if multi {
        src.to_owned()
    } else {
        format!("{src}[0]")
    })
    .arg("-auto-orient");
    if let Some(size) = args.value("resize") {
        cmd.args(["-resize", size]);
    }
    if args.flag("strip") {
        cmd.arg("-strip");
    }
    if target == "jpg" {
        cmd.args(["-background", "white", "-alpha", "remove", "-alpha", "off"]);
    }
    if target == "ico" {
        cmd.args([
            "-resize",
            "256x256>",
            "-define",
            "icon:auto-resize=256,128,64,48,32,16",
        ]);
    }
    if matches!(target, "jpg" | "webp" | "avif" | "heic") {
        if let Some(quality) = args.value("quality") {
            cmd.args(["-quality", quality]);
        }
    }
    subprocess::run(cmd.arg(dst)).await
}

async fn document(src: &str, target: &str, dest: &Destination, from_pdf: bool) -> Result<()> {
    let ext = extension_of(src);
    let office = which("soffice").or_else(|| which("libreoffice"));
    let office_format = matches!(
        ext.as_str(),
        "doc" | "docx" | "odt" | "rtf" | "ods" | "xls" | "xlsx" | "odp" | "ppt" | "pptx" | "csv"
    );
    if from_pdf
        || (matches!(target, "docx" | "odt" | "pdf") && office_format)
        || (target == "pdf" && matches!(ext.as_str(), "txt" | "html" | "htm"))
    {
        if let Some(office) = &office {
            let mut cmd = Command::new(office);
            let profile = dest.scratch.path().join("profile");
            cmd.arg(format!(
                "-env:UserInstallation={}",
                crate::apps::file_uri(&profile)
            ))
            .arg("--headless");
            if from_pdf {
                cmd.arg("--infilter=writer_pdf_import");
            }
            return subprocess::run(
                cmd.args(["--convert-to", target, "--outdir"])
                    .arg(dest.scratch.path())
                    .arg(src),
            )
            .await;
        }
        ensure!(!from_pdf, "PDF to DOCX needs LibreOffice");
    }
    ensure!(
        which("pandoc").is_some()
            && matches!(
                ext.as_str(),
                "md" | "markdown"
                    | "html"
                    | "htm"
                    | "docx"
                    | "odt"
                    | "epub"
                    | "txt"
                    | "tex"
                    | "rst"
                    | "org"
            ),
        "Can't convert .{ext} to .{target}: install pandoc or LibreOffice"
    );
    let mut cmd = Command::new("pandoc");
    cmd.arg(src).arg("-o").arg(dest.part());
    if target == "md" {
        cmd.args(["-t", "gfm"]);
    } else {
        cmd.arg("--standalone");
    }
    subprocess::run(&mut cmd).await
}

async fn pack(files: &[String], target: &str, part: &Path) -> Result<()> {
    let parent = Path::new(&files[0])
        .parent()
        .context("missing input directory")?
        .ancestors()
        .find(|dir| files.iter().all(|f| Path::new(f).starts_with(dir)))
        .context("no common parent")?;
    // Prefix relative names so a name beginning with '-' cannot become a tool option.
    let names = files
        .iter()
        .map(|f| Path::new(".").join(Path::new(f).strip_prefix(parent).unwrap()));
    let scratch = part.parent().context("missing staging directory")?;
    let exclude = files
        .iter()
        .any(|p| scratch.starts_with(p))
        .then(|| scratch.file_name().unwrap().to_string_lossy());
    let mut cmd = if target == "7z" || (target == "zip" && which("7z").is_some()) {
        let mut cmd = Command::new("7z");
        cmd.args(["a", "-y"]);
        if target == "zip" {
            cmd.arg("-tzip");
        }
        if let Some(name) = exclude.as_ref() {
            cmd.arg(format!("-xr!{name}"));
        }
        cmd.arg(part);
        cmd
    } else {
        let mut cmd = Command::new("bsdtar");
        cmd.args(["-a", "-cf"]).arg(part);
        if let Some(name) = exclude {
            cmd.args(["--exclude", name.as_ref()]);
        }
        cmd
    };
    subprocess::run(cmd.args(names).current_dir(parent)).await
}

async fn batch(files: &[String], target: &str, directory: &Path, args: &Args) -> Result<PathBuf> {
    let name = stem(&files[0]);
    let (base, ext) = match target {
        "pdf-merge" => (format!("{name}-merged"), "pdf"),
        "pdf" => (
            if files.len() == 1 {
                name.into()
            } else {
                format!("{name}-images")
            },
            "pdf",
        ),
        _ => (
            args.value("name")
                .unwrap_or(if files.len() == 1 { name } else { "archive" })
                .into(),
            target,
        ),
    };
    let dest = Destination::new(directory, &base, ext)?;
    let part = dest.part();
    match target {
        "pdf-merge" if which("qpdf").is_some() => {
            subprocess::run(
                Command::new("qpdf")
                    .args(["--empty", "--pages"])
                    .args(files)
                    .arg("--")
                    .arg(part),
            )
            .await?
        }
        "pdf-merge" => {
            subprocess::run(
                Command::new("gs")
                    .args(["-sDEVICE=pdfwrite", "-dNOPAUSE", "-dQUIET", "-dBATCH"])
                    .arg(format!("-sOutputFile={}", part.display()))
                    .args(files),
            )
            .await?
        }
        "pdf" => {
            let mut cmd = Command::new("magick");
            cmd.args(files.iter().map(|f| format!("{f}[0]")))
                .arg("-auto-orient");
            if let Some(size) = args.value("resize") {
                cmd.args(["-resize", size]);
            }
            subprocess::run(cmd.arg(part)).await?;
        }
        _ => pack(files, target, &part).await?,
    }
    dest.publish()
}

async fn single(
    src: &str,
    kind: &str,
    target: &str,
    directory: &Path,
    args: &Args,
    index: usize,
    events: Events<'_>,
) -> Result<PathBuf> {
    let name = stem(src);
    let (base, ext) = match (kind, target) {
        ("pdf", "png" | "jpg") => (format!("{name}-pages"), ""),
        ("pdf", "pdf-compress") => (format!("{name}-small"), "pdf"),
        ("archive", "extract") => (name.into(), ""),
        (
            "image",
            "png" | "jpg" | "webp" | "avif" | "heic" | "ico" | "bmp" | "tiff" | "gif" | "pdf",
        )
        | ("video", "mp4" | "webm" | "mkv" | "gif" | "mp3" | "opus" | "flac" | "m4a")
        | ("audio", "mp3" | "opus" | "ogg" | "flac" | "wav" | "m4a")
        | ("document", "pdf" | "docx" | "odt" | "html" | "md" | "txt" | "epub")
        | ("pdf", "txt" | "docx") => (name.into(), target),
        _ => bail!("Can't turn {kind} into .{target}"),
    };
    let dest = Destination::new(directory, &base, ext)?;
    let part = dest.part();
    match (kind, target) {
        ("image", _) => image(src, target, &part, args).await?,
        ("audio" | "video", _) => media::convert(src, target, &part, args, index, events).await?,
        ("document", _) | ("pdf", "docx") => document(src, target, &dest, kind == "pdf").await?,
        ("pdf", "png" | "jpg") => {
            fs::create_dir(&part)?;
            subprocess::run(
                Command::new("pdftoppm")
                    .args([
                        "-r",
                        args.value("dpi").unwrap_or("150"),
                        if target == "png" { "-png" } else { "-jpeg" },
                        src,
                    ])
                    .arg(part.join("page")),
            )
            .await?;
        }
        ("pdf", "txt") => {
            subprocess::run(Command::new("pdftotext").args(["-layout", src]).arg(part)).await?
        }
        ("pdf", "pdf-compress") => {
            subprocess::run(
                Command::new("gs")
                    .args([
                        "-sDEVICE=pdfwrite",
                        "-dCompatibilityLevel=1.5",
                        "-dPDFSETTINGS=/ebook",
                        "-dNOPAUSE",
                        "-dQUIET",
                        "-dBATCH",
                    ])
                    .arg(format!("-sOutputFile={}", part.display()))
                    .arg(src),
            )
            .await?
        }
        ("archive", _) => {
            fs::create_dir(&part)?;
            if which("7z").is_some() && !extension_of(src).starts_with("tar") {
                subprocess::run(
                    Command::new("7z")
                        .args(["x", "-y"])
                        .arg(format!("-o{}", part.display()))
                        .arg(src),
                )
                .await?;
            } else {
                subprocess::run(Command::new("bsdtar").args(["-xf", src, "-C"]).arg(part)).await?;
            }
        }
        _ => unreachable!(),
    }
    dest.publish()
}

pub async fn run(argv: Vec<String>, events: Events<'_>) -> Result<()> {
    let args = Args::parse(argv, &["strip", "no-audio", "merge"])?;
    args.reject_unknown(&[
        "to",
        "out-dir",
        "quality",
        "resize",
        "strip",
        "crf",
        "height",
        "fps",
        "start",
        "end",
        "target-size",
        "no-audio",
        "bitrate",
        "dpi",
        "merge",
        "name",
    ])?;
    let target = args.require("to")?;
    ensure!(!args.positional.is_empty(), "expected input files");
    let files: Vec<String> = args
        .positional
        .iter()
        .map(|p| std::path::absolute(p).map(|p| p.to_string_lossy().into_owned()))
        .collect::<std::io::Result<_>>()?;
    let explicit_dir = args.value("out-dir").map(std::path::absolute).transpose()?;
    let mut group = matches!(target, "zip" | "7z" | "tar.gz" | "tar.zst" | "pdf-merge");
    let mut kinds = Vec::new();
    if target == "pdf" && args.flag("merge") {
        for path in &files {
            kinds.push(identify(path).await.0);
        }
        group = kinds.iter().all(|k| *k == "image");
    }
    for (index, src) in files.iter().enumerate() {
        events(json!({"event":"start","index":index,"file":src}));
        let dir = explicit_dir
            .as_deref()
            .or_else(|| Path::new(src).parent())
            .ok_or_else(|| anyhow!("no output directory"))?;
        let result = if group {
            batch(&files, target, dir, &args).await
        } else {
            let kind = match kinds.get(index) {
                Some(kind) => *kind,
                None => identify(src).await.0,
            };
            single(src, kind, target, dir, &args, index, events).await
        };
        match result {
            Ok(path) => events(json!({"event":"done","index":index,"file":src,"output":path})),
            Err(e) => {
                events(json!({"event":"error","index":index,"file":src,"message":e.to_string()}))
            }
        }
        if group {
            break;
        }
    }
    events(json!({"event":"finished"}));
    Ok(())
}
