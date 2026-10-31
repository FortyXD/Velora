//! Port of scripts/thumbnails/thumbgen.py and generate-thumbnails-magick.sh: Freedesktop thumbnails for
//! a folder of wallpapers. Pictures are decoded in this process instead of starting a sandboxed
//! thumbnailer for each; what it can't read goes to ImageMagick, and videos to ffmpeg.
//!
//!   thumbnails --size <normal|large|x-large|xx-large> --directory <dir>
//!     Prints `PROGRESS n/total FILE path` as files finish.

use crate::args::Args;
use anyhow::{bail, Context, Result};
use fast_image_resize::{FilterType, ResizeAlg, ResizeOptions, Resizer};
use image::{DynamicImage, ImageDecoder, ImageReader};
use md5::{Digest, Md5};
use std::fs;
use std::io::{BufWriter, Write as _};
use std::os::unix::fs::{MetadataExt as _, PermissionsExt as _};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

const VIDEOS: [&str; 5] = ["mp4", "webm", "mkv", "avi", "mov"];
// Pictures ImageMagick might read when the built-in decoders can't
const OTHER_PICTURES: [&str; 9] = ["avif", "heic", "heif", "jxl", "svg", "svgz", "ico", "jp2", "tga"];
const NATIVE_PICTURES: [&str; 8] = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff"];

pub fn run(argv: Vec<String>) -> Result<()> {
    let args = Args::parse(argv, &[])?;
    args.reject_unknown(&["size", "directory"])?;
    let size_name = args.value("size").unwrap_or("normal");
    let size = match size_name {
        "normal" => 128,
        "large" => 256,
        "x-large" => 512,
        "xx-large" => 1024,
        other => bail!("unknown size: {other}"),
    };
    let directory = fs::canonicalize(args.require("directory")?).context("the directory doesn't exist")?;
    let mut files: Vec<PathBuf> = fs::read_dir(&directory)?.filter_map(Result::ok).map(|entry| entry.path()).filter(|path| path.is_file()).collect();
    files.sort();
    let cache = cache_home().join("thumbnails").join(size_name);
    fs::create_dir_all(&cache)?;

    // In the background of whatever the user is doing, on part of the cores
    // SAFETY: nice only changes this process's priority.
    unsafe { libc::nice(10) };
    let workers = std::thread::available_parallelism().map_or(1, |cores| cores.get() / 2).clamp(1, 4);
    let next = AtomicUsize::new(0);
    let done = Mutex::new(0usize);
    std::thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| {
                while let Some(file) = files.get(next.fetch_add(1, Ordering::Relaxed)) {
                    if let Err(error) = thumbnail(file, &cache, size) {
                        eprintln!("{}: {error:#}", file.display());
                    }
                    let Ok(mut done) = done.lock() else { return };
                    *done += 1;
                    println!("PROGRESS {}/{} FILE {}", *done, files.len(), file.display());
                    let _ = std::io::stdout().flush();
                }
            });
        }
    });
    Ok(())
}

fn cache_home() -> PathBuf {
    std::env::var_os("XDG_CACHE_HOME").filter(|path| !path.is_empty()).map_or_else(
        || PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".cache"),
        PathBuf::from,
    )
}

/// The URI the shell hashes to find a thumbnail: ThumbnailImage.qml runs encodeURIComponent on each part.
pub fn file_uri(path: &Path) -> String {
    let mut uri = String::from("file://");
    for byte in path.as_os_str().as_encoded_bytes() {
        if byte.is_ascii_alphanumeric() || b"/-_.!~*'()".contains(byte) {
            uri.push(*byte as char);
        } else {
            uri.push_str(&format!("%{byte:02X}"));
        }
    }
    uri
}

pub fn thumbnail_name(uri: &str) -> String {
    let digest = Md5::digest(uri.as_bytes());
    let mut name: String = digest.iter().map(|byte| format!("{byte:02x}")).collect();
    name.push_str(".png");
    name
}

/// A thumbnail stays valid while it names the file's current modification time. Ones without that
/// (made by other tools) are taken as they are, as regenerating them wouldn't always give them one.
fn is_fresh(path: &Path, modified: i64) -> bool {
    let Ok(file) = fs::File::open(path) else { return false };
    let Ok(reader) = png::Decoder::new(std::io::BufReader::new(file)).read_info() else { return false };
    let info = reader.info();
    let stored = info.uncompressed_latin1_text.iter().find(|chunk| chunk.keyword == "Thumb::MTime").map(|chunk| chunk.text.clone());
    stored.is_none_or(|stored| stored.trim().parse::<i64>().ok() == Some(modified))
}

fn thumbnail(file: &Path, cache: &Path, size: u32) -> Result<()> {
    let extension = file.extension().map(|extension| extension.to_string_lossy().to_lowercase()).unwrap_or_default();
    let is_video = VIDEOS.contains(&extension.as_str());
    let is_native = NATIVE_PICTURES.contains(&extension.as_str());
    if !is_video && !is_native && !OTHER_PICTURES.contains(&extension.as_str()) {
        return Ok(());
    }
    let meta = fs::metadata(file)?;
    let uri = file_uri(file);
    let target = cache.join(thumbnail_name(&uri));
    if is_fresh(&target, meta.mtime()) {
        return Ok(());
    }
    // Written aside: the shell may be watching for this name
    let temporary = target.with_extension(format!("{}.tmp.png", std::process::id()));
    let result = if is_video {
        video_frame(file, &temporary, size)
    } else {
        match is_native.then(|| decode(file)).transpose().and_then(|picture| picture.context("no built-in decoder")) {
            Ok(picture) => write_png(&scaled(&picture, size)?, &temporary, &uri, meta.mtime()),
            Err(_) => magick(file, &temporary, size),
        }
    };
    if let Err(error) = result {
        let _ = fs::remove_file(&temporary);
        return Err(error);
    }
    fs::rename(&temporary, &target)?;
    Ok(())
}

fn decode(file: &Path) -> Result<DynamicImage> {
    let mut reader = ImageReader::open(file)?.with_guessed_format()?;
    reader.no_limits(); // Wallpapers are often larger than the default limits allow
    let mut decoder = reader.into_decoder()?;
    let orientation = decoder.orientation()?;
    let mut picture = DynamicImage::from_decoder(decoder)?;
    picture.apply_orientation(orientation);
    Ok(picture)
}

/// To fit in `size`×`size`, keeping the proportions. Smaller pictures stay as they are, per the spec.
fn scaled(picture: &DynamicImage, size: u32) -> Result<DynamicImage> {
    let (width, height) = (picture.width(), picture.height());
    let longest = width.max(height);
    let opaque = !picture.color().has_alpha();
    let source = if opaque { DynamicImage::ImageRgb8(picture.to_rgb8()) } else { DynamicImage::ImageRgba8(picture.to_rgba8()) };
    if longest <= size {
        return Ok(source);
    }
    let scale = f64::from(size) / f64::from(longest);
    let (new_width, new_height) = (((f64::from(width) * scale).round() as u32).max(1), ((f64::from(height) * scale).round() as u32).max(1));
    let mut target = if opaque { DynamicImage::new_rgb8(new_width, new_height) } else { DynamicImage::new_rgba8(new_width, new_height) };
    Resizer::new()
        .resize(&source, &mut target, &ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Bilinear)))
        .context("can't scale the picture")?;
    Ok(target)
}

fn write_png(picture: &DynamicImage, path: &Path, uri: &str, modified: i64) -> Result<()> {
    let file = fs::File::create(path)?;
    // Thumbnails are private, per the spec
    file.set_permissions(fs::Permissions::from_mode(0o600))?;
    let mut encoder = png::Encoder::new(BufWriter::new(file), picture.width(), picture.height());
    encoder.set_color(if picture.color().has_alpha() { png::ColorType::Rgba } else { png::ColorType::Rgb });
    encoder.set_depth(png::BitDepth::Eight);
    encoder.set_compression(png::Compression::Fast);
    encoder.add_text_chunk("Thumb::URI".to_string(), uri.to_string())?;
    encoder.add_text_chunk("Thumb::MTime".to_string(), modified.to_string())?;
    let mut writer = encoder.write_header()?;
    writer.write_image_data(picture.as_bytes())?;
    writer.finish()?;
    Ok(())
}

fn quiet(command: &mut Command) -> bool {
    command.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status().is_ok_and(|status| status.success())
}

fn magick(file: &Path, target: &Path, size: u32) -> Result<()> {
    if !quiet(Command::new("magick").arg(file).args(["-resize", &format!("{size}x{size}")]).arg(target)) {
        bail!("magick can't read it");
    }
    Ok(())
}

/// A frame from a second in (the very first one is often black), or the first if it's shorter.
fn video_frame(file: &Path, target: &Path, size: u32) -> Result<()> {
    let scale = format!("scale={size}:{size}:force_original_aspect_ratio=decrease");
    let attempt = |seek: &[&str]| {
        quiet(Command::new("ffmpeg").args(["-nostdin", "-loglevel", "error", "-y"]).args(seek).arg("-i").arg(file).args(["-frames:v", "1", "-vf", &scale]).arg(target))
    };
    if !attempt(&["-ss", "1"]) && !attempt(&[]) {
        bail!("ffmpeg can't read it");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uris_match_the_shell() {
        assert_eq!(file_uri(Path::new("/a b/c (1)'!.png")), "file:///a%20b/c%20(1)'!.png");
        assert_eq!(file_uri(Path::new("/ю&=.png")), "file:///%D1%8E%26%3D.png");
    }

    #[test]
    fn names_are_the_md5_of_the_uri() {
        // Qt.md5("file:///a.png")
        assert_eq!(thumbnail_name("file:///a.png"), format!("{:x}.png", u128::from_be_bytes(Md5::digest(b"file:///a.png").into())));
        assert_eq!(thumbnail_name("").len(), 36);
        assert_eq!(thumbnail_name(""), "d41d8cd98f00b204e9800998ecf8427e.png");
    }

    #[test]
    fn scaling_keeps_proportions_and_never_enlarges() {
        let wide = DynamicImage::new_rgb8(1000, 500);
        let small = scaled(&wide, 256).unwrap();
        assert_eq!((small.width(), small.height()), (256, 128));
        let tiny = DynamicImage::new_rgba8(10, 20);
        let same = scaled(&tiny, 256).unwrap();
        assert_eq!((same.width(), same.height()), (10, 20));
        assert!(same.color().has_alpha());
    }
}
