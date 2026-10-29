//! Port of scripts/images/least_busy_region.py: where a desktop widget sits on a wallpaper (the
//! calmest or busiest spot, clear of the widgets placed before it) and the color behind it, for
//! readable text. Prints the same JSON. The largest-region and drawing modes stay in Python; they
//! exit with status 3 here so the wrapper falls back.

use crate::args::Args;
use crate::picture;
use anyhow::Result;
use image::RgbImage;
use serde_json::json;
use std::path::Path;

pub const UNSUPPORTED: i32 = 3;

pub fn run(argv: Vec<String>) -> Result<()> {
    let args = Args::parse(argv, &["busiest", "verbose", "largest-region", "visual-output"])?;
    if args.flag("largest-region") || args.flag("visual-output") {
        std::process::exit(UNSUPPORTED);
    }
    args.reject_unknown(&["width", "height", "screen-width", "screen-height", "stride", "screen-mode", "verbose",
        "horizontal-padding", "vertical-padding", "busiest", "slot", "gap", "sample-x", "sample-y",
        "variance-threshold", "aspect-ratio"])?;
    let path = args.positional.first().ok_or_else(|| anyhow::anyhow!("an image path is required"))?;
    let width: i64 = args.number("width", 300)?;
    let height: i64 = args.number("height", 200)?;
    let screen_width: u32 = args.number("screen-width", 1920)?;
    let screen_height: u32 = args.number("screen-height", 1080)?;
    let fill = args.value("screen-mode").unwrap_or("fill") != "fit";
    let wallpaper = picture::as_on_screen(&picture::load_rgb(Path::new(path))?, screen_width.max(1), screen_height.max(1), fill)?;

    if let Some(x) = args.value("sample-x") {
        let x: i64 = x.parse()?;
        let y: i64 = args.number("sample-y", 0)?;
        println!("{}", json!({ "dominant_color": hex(dominant_color(&wallpaper, x, y, width, height)?) }));
        return Ok(());
    }

    let search = Search {
        region_width: width,
        region_height: height,
        stride: args.number::<i64>("stride", 10)?.max(1),
        horizontal_padding: args.number("horizontal-padding", 50)?,
        vertical_padding: args.number("vertical-padding", 50)?,
        busiest: args.flag("busiest"),
        slot: args.number::<i64>("slot", 0)?.max(0) as usize,
        gap: args.number("gap", 120)?,
    };
    let gray = picture::gray(&wallpaper);
    let ((x, y), variance) = search.run(&gray, wallpaper.width() as i64, wallpaper.height() as i64);
    let color = dominant_color(&wallpaper, x, y, width, height)?;
    println!("{}", json!({
        "center_x": x + width / 2,
        "center_y": y + height / 2,
        "width": width,
        "height": height,
        "variance": variance,
        "dominant_color": hex(color),
    }));
    Ok(())
}

fn hex(color: [u8; 3]) -> String {
    format!("#{:02x}{:02x}{:02x}", color[0], color[1], color[2])
}

pub struct Search {
    pub region_width: i64,
    pub region_height: i64,
    pub stride: i64,
    pub horizontal_padding: i64,
    pub vertical_padding: i64,
    pub busiest: bool,
    pub slot: usize,
    pub gap: i64,
}

impl Search {
    /// Top-left corner of the chosen window and its variance (None when nothing fits).
    pub fn run(&self, gray: &[u8], w: i64, h: i64) -> ((i64, i64), Option<f64>) {
        let (mut hp, mut vp) = (self.horizontal_padding.max(0), self.vertical_padding.max(0));
        if hp * 2 >= w || vp * 2 >= h {
            hp = hp.min((w - 1) / 2).max(0);
            vp = vp.min((h - 1) / 2).max(0);
        }
        let region_width = self.region_width.clamp(1, (w - 2 * hp).max(1));
        let region_height = self.region_height.clamp(1, (h - 2 * vp).max(1));

        // Summed-area tables with a zero row and column, as cv2.integral2 builds them
        let stride_row = (w + 1) as usize;
        let mut sums = vec![0f64; stride_row * (h + 1) as usize];
        let mut squares = vec![0f64; stride_row * (h + 1) as usize];
        for y in 0..h as usize {
            let (mut row_sum, mut row_square) = (0f64, 0f64);
            for x in 0..w as usize {
                let value = f64::from(gray[y * w as usize + x]);
                row_sum += value;
                row_square += value * value;
                let index = (y + 1) * stride_row + x + 1;
                sums[index] = sums[index - stride_row] + row_sum;
                squares[index] = squares[index - stride_row] + row_square;
            }
        }
        let area = (region_width * region_height) as f64;
        let window = |table: &[f64], x: i64, y: i64| {
            let (x1, y1, x2, y2) = (x as usize, y as usize, (x + region_width) as usize, (y + region_height) as usize);
            table[y2 * stride_row + x2] - table[y1 * stride_row + x2] - table[y2 * stride_row + x1] + table[y1 * stride_row + x1]
        };

        let mut candidates = Vec::new();
        let mut y = vp;
        while y <= h - region_height - vp {
            let mut x = hp;
            while x <= w - region_width - hp {
                let mean = window(&sums, x, y) / area;
                let variance = (window(&squares, x, y) / area - mean * mean).max(0.0);
                candidates.push((variance, x, y));
                x += self.stride;
            }
            y += self.stride;
        }
        if candidates.is_empty() {
            return ((hp, vp), None);
        }
        // A stable order, so every widget sees the same sequence of spots
        let busiest = self.busiest;
        candidates.sort_by(|a, b| {
            let (va, vb) = if busiest { (-a.0, -b.0) } else { (a.0, b.0) };
            va.total_cmp(&vb).then(a.2.cmp(&b.2)).then(a.1.cmp(&b.1))
        });
        // Slot N is the best spot that keeps a gap from slots 0..N-1, so widgets don't stack up
        let mut taken: Vec<(i64, i64, i64, i64)> = Vec::new();
        let mut best = candidates[0];
        for _ in 0..=self.slot {
            let found = candidates.iter().find(|c| {
                !taken.iter().any(|&(tx1, ty1, tx2, ty2)| {
                    c.1 < tx2 && c.1 + region_width > tx1 && c.2 < ty2 && c.2 + region_height > ty1
                })
            });
            let Some(found) = found else { break }; // No room left: share the last spot
            best = *found;
            taken.push((best.1 - self.gap, best.2 - self.gap, best.1 + region_width + self.gap, best.2 + region_height + self.gap));
        }
        ((best.1, best.2), Some(best.0))
    }
}

/// The per-channel median of the area behind a widget, sampled at no more than 64×64.
pub fn dominant_color(wallpaper: &RgbImage, x: i64, y: i64, w: i64, h: i64) -> Result<[u8; 3]> {
    let (width, height) = (wallpaper.width() as i64, wallpaper.height() as i64);
    let x = x.clamp(0, width - 1);
    let y = y.clamp(0, height - 1);
    let w = w.clamp(1, width - x);
    let h = h.clamp(1, height - y);
    let region = image::imageops::crop_imm(wallpaper, x as u32, y as u32, w as u32, h as u32).to_image();
    let sample = picture::resize(&region, w.min(64) as u32, h.min(64) as u32)?;
    let mut channels: [Vec<u8>; 3] = Default::default();
    for pixel in sample.pixels() {
        for (channel, value) in channels.iter_mut().zip(pixel.0) {
            channel.push(value);
        }
    }
    Ok(channels.map(|mut values| {
        values.sort_unstable();
        let n = values.len();
        // NumPy's median of an even count averages the middle pair; int() truncates it
        if n % 2 == 0 { ((u16::from(values[n / 2 - 1]) + u16::from(values[n / 2])) / 2) as u8 } else { values[n / 2] }
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn search(stride: i64, padding: i64, busiest: bool, slot: usize, gap: i64, size: i64) -> Search {
        Search { region_width: size, region_height: size, stride, horizontal_padding: padding, vertical_padding: padding, busiest, slot, gap }
    }

    // Same check as tests/test_wallpaper.py: the fast search equals brute force
    #[test]
    fn matches_brute_force() {
        let (w, h) = (100i64, 80i64);
        let mut state = 42u64;
        let gray: Vec<u8> = (0..w * h).map(|_| {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (state >> 56) as u8
        }).collect();
        let variance = |x: i64, y: i64| {
            let values: Vec<f64> = (y..y + 20).flat_map(|yy| (x..x + 20).map(move |xx| (yy, xx)))
                .map(|(yy, xx)| f64::from(gray[(yy * w + xx) as usize])).collect();
            let mean = values.iter().sum::<f64>() / values.len() as f64;
            values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / values.len() as f64
        };
        for busiest in [false, true] {
            let mut windows = Vec::new();
            for y in (5..=55).step_by(5) {
                for x in (5..=75).step_by(5) {
                    windows.push((variance(x, y), x, y));
                }
            }
            windows.sort_by(|a, b| {
                let (va, vb) = if busiest { (-a.0, -b.0) } else { (a.0, b.0) };
                va.total_cmp(&vb).then(a.2.cmp(&b.2)).then(a.1.cmp(&b.1))
            });
            let ((x, y), found) = search(5, 5, busiest, 0, 120, 20).run(&gray, w, h);
            assert_eq!((x, y), (windows[0].1, windows[0].2));
            assert!((found.unwrap() - windows[0].0).abs() < 1e-6);
        }
    }

    #[test]
    fn slots_keep_widgets_apart() {
        let gray = vec![0u8; 600 * 400];
        let positions: Vec<(i64, i64)> = (0..3).map(|slot| search(10, 10, false, slot, 20, 100).run(&gray, 600, 400).0).collect();
        for pair in positions.windows(2) {
            assert!((pair[0].0 - pair[1].0).abs() >= 120 || (pair[0].1 - pair[1].1).abs() >= 120, "{positions:?}");
        }
    }

    #[test]
    fn samples_its_own_background_including_black() {
        let picture = RgbImage::from_fn(200, 100, |x, _| if x < 100 { image::Rgb([0, 0, 0]) } else { image::Rgb([255, 255, 255]) });
        assert_eq!(dominant_color(&picture, 10, 10, 50, 50).unwrap(), [0, 0, 0]);
        assert_eq!(dominant_color(&picture, 110, 10, 50, 50).unwrap(), [255, 255, 255]);
        let blue = RgbImage::from_pixel(100, 100, image::Rgb([220, 30, 10]));
        assert_eq!(dominant_color(&blue, 0, 0, 100, 100).unwrap(), [220, 30, 10]);
    }
}
