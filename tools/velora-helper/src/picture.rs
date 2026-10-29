//! Loading and scaling wallpapers.

use anyhow::{Context, Result};
use fast_image_resize::{FilterType, ResizeAlg, ResizeOptions, Resizer};
use image::{DynamicImage, ImageReader, RgbImage};
use std::path::Path;

/// The first frame, as 8-bit RGB. The format comes from the content: saved presets name every
/// picture wallpaper.png whatever it really is.
pub fn load_rgb(path: &Path) -> Result<RgbImage> {
    let reader = ImageReader::open(path)
        .with_context(|| format!("can't open {}", path.display()))?
        .with_guessed_format()
        .with_context(|| format!("can't read {}", path.display()))?;
    let mut reader = reader;
    reader.no_limits(); // Wallpapers are often larger than the default limits allow
    let picture = reader.decode().with_context(|| format!("can't decode {}", path.display()))?;
    Ok(picture.into_rgb8())
}

/// Scales to exactly `width`×`height`. Shrinking averages every source pixel (like OpenCV's
/// INTER_AREA); growing interpolates linearly.
pub fn resize(picture: &RgbImage, width: u32, height: u32) -> Result<RgbImage> {
    let (width, height) = (width.max(1), height.max(1));
    if picture.width() == width && picture.height() == height {
        return Ok(picture.clone());
    }
    let shrinking = width < picture.width() || height < picture.height();
    let filter = if shrinking { FilterType::Box } else { FilterType::Bilinear };
    let source = DynamicImage::ImageRgb8(picture.clone());
    let mut target = DynamicImage::new_rgb8(width, height);
    Resizer::new()
        .resize(&source, &mut target, &ResizeOptions::new().resize_alg(ResizeAlg::Convolution(filter)))
        .context("can't scale the picture")?;
    Ok(target.into_rgb8())
}

/// At most `max_side` pixels on the longer side, keeping the proportions.
pub fn shrink_to(picture: &RgbImage, max_side: u32) -> Result<RgbImage> {
    let longest = picture.width().max(picture.height());
    if longest <= max_side {
        return Ok(picture.clone());
    }
    let scale = f64::from(max_side) / f64::from(longest);
    resize(picture, (f64::from(picture.width()) * scale) as u32, (f64::from(picture.height()) * scale) as u32)
}

/// How the shell shows a wallpaper on a screen: scaled to cover it ("fill") or to fit inside
/// ("fit"), then the middle cut out at the screen's size.
pub fn as_on_screen(picture: &RgbImage, screen_width: u32, screen_height: u32, fill: bool) -> Result<RgbImage> {
    let (width, height) = (f64::from(picture.width()), f64::from(picture.height()));
    let scale_x = f64::from(screen_width) / width;
    let scale_y = f64::from(screen_height) / height;
    let scale = if fill { scale_x.max(scale_y) } else { scale_x.min(scale_y) };
    let scaled = resize(picture, ((width * scale).round() as u32).max(1), ((height * scale).round() as u32).max(1))?;
    Ok(center_crop(&scaled, screen_width, screen_height))
}

pub fn center_crop(picture: &RgbImage, width: u32, height: u32) -> RgbImage {
    if picture.width() == width && picture.height() == height {
        return picture.clone();
    }
    let x = picture.width().saturating_sub(width) / 2;
    let y = picture.height().saturating_sub(height) / 2;
    let width = width.min(picture.width() - x);
    let height = height.min(picture.height() - y);
    image::imageops::crop_imm(picture, x, y, width, height).to_image()
}

/// Luma as OpenCV computes it for BGR→GRAY: 0.299 R + 0.587 G + 0.114 B, rounded.
pub fn gray(picture: &RgbImage) -> Vec<u8> {
    picture
        .pixels()
        .map(|pixel| {
            let [r, g, b] = pixel.0;
            ((f64::from(r) * 0.299 + f64::from(g) * 0.587 + f64::from(b) * 0.114).round()).min(255.0) as u8
        })
        .collect()
}
