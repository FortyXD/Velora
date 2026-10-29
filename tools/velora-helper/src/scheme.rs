//! Port of scripts/colors/scheme_for_image.py: picks a palette type from how colorful a picture is.

use crate::args::Args;
use crate::picture;
use anyhow::Result;
use image::RgbImage;
use std::path::Path;

pub fn run(argv: Vec<String>) -> Result<()> {
    let args = Args::parse(argv, &["colorfulness"])?;
    args.reject_unknown(&["colorfulness"])?;
    let Some(path) = args.positional.first() else {
        println!("scheme-tonal-spot");
        std::process::exit(1);
    };
    let picture = match picture::load_rgb(Path::new(path)).and_then(|p| picture::shrink_to(&p, 128)) {
        Ok(picture) => picture,
        Err(_) => {
            println!("scheme-tonal-spot");
            std::process::exit(1);
        }
    };
    let value = colorfulness(&picture);
    if args.flag("colorfulness") {
        println!("{value}");
    } else {
        println!("{}", pick(value));
    }
    Ok(())
}

/// scheme-content respects the image's colors very well, but it might look too saturated,
/// so only pictures that aren't very colorful get the neutral scheme.
pub fn pick(colorfulness: f64) -> &'static str {
    if colorfulness < 40.0 { "scheme-neutral" } else { "scheme-tonal-spot" }
}

/// Hasler and Süsstrunk's colorfulness metric.
pub fn colorfulness(picture: &RgbImage) -> f64 {
    let count = f64::from(picture.width() * picture.height()).max(1.0);
    let (mut sum_rg, mut sum_yb, mut sq_rg, mut sq_yb) = (0.0, 0.0, 0.0, 0.0);
    for pixel in picture.pixels() {
        let [r, g, b] = pixel.0.map(f64::from);
        let rg = (r - g).abs();
        let yb = (0.5 * (r + g) - b).abs();
        sum_rg += rg;
        sum_yb += yb;
        sq_rg += rg * rg;
        sq_yb += yb * yb;
    }
    let (mean_rg, mean_yb) = (sum_rg / count, sum_yb / count);
    let std_rg = (sq_rg / count - mean_rg * mean_rg).max(0.0).sqrt();
    let std_yb = (sq_yb / count - mean_yb * mean_yb).max(0.0).sqrt();
    (std_rg * std_rg + std_yb * std_yb).sqrt() + 0.3 * (mean_rg * mean_rg + mean_yb * mean_yb).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gray_picture_is_neutral() {
        let picture = RgbImage::from_pixel(10, 10, image::Rgb([90, 90, 90]));
        assert_eq!(colorfulness(&picture), 0.0);
        assert_eq!(pick(colorfulness(&picture)), "scheme-neutral");
    }

    #[test]
    fn vivid_picture_gets_tonal_spot() {
        let picture = RgbImage::from_fn(10, 10, |x, _| if x % 2 == 0 { image::Rgb([255, 0, 0]) } else { image::Rgb([0, 0, 255]) });
        assert!(colorfulness(&picture) > 40.0);
        assert_eq!(pick(colorfulness(&picture)), "scheme-tonal-spot");
    }
}
