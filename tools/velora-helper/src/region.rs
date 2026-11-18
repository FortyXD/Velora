//! Port of scripts/images/least_busy_region.py: where a desktop widget sits on a wallpaper (the
//! calmest or busiest spot, clear of the widgets placed before it) and the color behind it, for
//! readable text. A summed-area table also supports largest-region search.

use crate::args::Args;
use crate::picture;
use anyhow::Result;
use image::RgbImage;
use serde_json::json;
use std::path::Path;

pub fn run(argv: Vec<String>) -> Result<()> {
    let args = Args::parse(argv, &["busiest", "verbose", "largest-region", "visual-output"])?;
    args.reject_unknown(&["width", "height", "screen-width", "screen-height", "stride", "screen-mode", "verbose",
        "horizontal-padding", "vertical-padding", "busiest", "slot", "gap", "sample-x", "sample-y",
        "variance-threshold", "aspect-ratio", "avoid-rects", "largest-region", "visual-output"])?;
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
        avoid_rects: serde_json::from_str(args.value("avoid-rects").unwrap_or("[]"))?,
    };
    let gray = picture::gray(&wallpaper);
    let w = i64::from(wallpaper.width());
    let h = i64::from(wallpaper.height());
    let (x, y, width, height, variance) = if args.flag("largest-region") {
        let aspect: f64 = args.number("aspect-ratio", 1.78)?;
        anyhow::ensure!(aspect.is_finite() && aspect > 0.0, "invalid aspect ratio");
        let Some(rect) = search.largest(&gray, w, h, aspect, args.number("variance-threshold", 1000.0)?) else {
            println!("{}", json!({"error": "No region found under the threshold."}));
            return Ok(());
        };
        rect
    } else {
        let ((x, y), variance) = search.run(&gray, w, h);
        (x, y, width, height, variance)
    };
    if args.flag("visual-output") {
        let mut annotated = wallpaper.clone();
        let color = image::Rgb(if args.flag("largest-region") { [0,0,255] } else { [255,0,0] });
        for (px, py, pixel) in annotated.enumerate_pixels_mut() {
            let dx = i64::from(px) - x;
            let dy = i64::from(py) - y;
            if (-1..=width).contains(&dx) && (-1..=height).contains(&dy)
                && (dx <= 1 || dx >= width-2 || dy <= 1 || dy >= height-2) { *pixel = color; }
        }
        annotated.save("output.png")?;
    }
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

#[derive(Clone)]
pub struct Search {
    pub region_width: i64,
    pub region_height: i64,
    pub stride: i64,
    pub horizontal_padding: i64,
    pub vertical_padding: i64,
    pub busiest: bool,
    pub slot: usize,
    pub gap: i64,
    pub avoid_rects: Vec<[f64; 4]>,
}

struct Integral { stride: usize, sums: Vec<f64>, squares: Vec<f64> }

impl Integral {
    fn new(gray: &[u8], w: i64, h: i64) -> Self {
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
        Self { stride: stride_row, sums, squares }
    }

    fn variance(&self, x:i64, y:i64, w:i64, h:i64) -> f64 {
        let window = |table: &[f64]| {
            let (x1,y1,x2,y2) = (x as usize,y as usize,(x+w) as usize,(y+h) as usize);
            table[y2*self.stride+x2] - table[y1*self.stride+x2] - table[y2*self.stride+x1] + table[y1*self.stride+x1]
        };
        let area = (w*h) as f64;
        let mean = window(&self.sums)/area;
        (window(&self.squares)/area - mean*mean).max(0.0)
    }
}

impl Search {
    fn largest(&self, gray:&[u8], w:i64, h:i64, aspect:f64, threshold:f64)
        -> Option<(i64,i64,i64,i64,Option<f64>)> {
        let hp=self.horizontal_padding.clamp(0,(w-1)/2);
        let vp=self.vertical_padding.clamp(0,(h-1)/2);
        let (ew,eh)=(w-2*hp,h-2*vp);
        let mut hi=if aspect>=1.0 {eh.min((ew as f64/aspect) as i64)}else{ew.min((eh as f64*aspect) as i64)}.max(1);
        let mut lo=if hi<10 {1} else {10};
        let integral=Integral::new(gray,w,h);
        let mut best=None;
        while lo<=hi {
            let mid=lo+(hi-lo)/2;
            let (rw,rh)=if aspect>=1.0 {((mid as f64*aspect).round_ties_even() as i64,mid)} else {(mid,(mid as f64/aspect).round_ties_even() as i64)};
            let stride=self.stride.max(1) as usize;
            let found=(vp..=h-rh-vp).step_by(stride).find_map(|y| (hp..=w-rw-hp).step_by(stride).find_map(|x| {
                let v=integral.variance(x,y,rw,rh);
                (v<=threshold.max(0.0)).then_some((x,y,rw,rh,Some(v)))
            }));
            if found.is_some(){best=found;lo=mid+1;}else{hi=mid-1;}
        }
        best
    }

    /// Top-left corner of the chosen window and its variance (None when nothing fits).
    pub fn run(&self, gray: &[u8], w: i64, h: i64) -> ((i64, i64), Option<f64>) {
        let region_width = self.region_width.clamp(1, w);
        let region_height = self.region_height.clamp(1, h);
        let hp = self.horizontal_padding.clamp(0, (w - region_width) / 2);
        let vp = self.vertical_padding.clamp(0, (h - region_height) / 2);

        let integral = Integral::new(gray, w, h);

        // Include screen edges and exact neighbour edges even between stride samples.
        let axis = |padding: i64, end: i64, size: i64, coordinate: usize| {
            let mut values: Vec<i64> = (padding..=end).step_by(self.stride.max(1) as usize).collect();
            values.push(end);
            for rect in &self.avoid_rects {
                values.push(((rect[coordinate] - size as f64).floor() as i64).clamp(padding, end));
                values.push(((rect[coordinate] + rect[coordinate + 2]).ceil() as i64).clamp(padding, end));
            }
            values.sort_unstable();
            values.dedup();
            values
        };
        let xs = axis(hp, w - region_width - hp, region_width, 0);
        let ys = axis(vp, h - region_height - vp, region_height, 1);
        let mut candidates = Vec::new();
        for y in ys {
            for &x in &xs {
                let variance = integral.variance(x, y, region_width, region_height);
                candidates.push((variance, x, y));
            }
        }
        let mut taken = self.avoid_rects.clone();
        let mut best = candidates[0];
        for _ in 0..=self.slot {
            let mut best_overlap = 0.0;
            for clearance in [self.gap.max(0) as f64, 0.0] {
                let ranked = candidates.iter().map(|&(variance, x, y)| {
                    let overlap: f64 = taken.iter().map(|r| {
                        let dx = ((x + region_width) as f64).min(r[0] + r[2] + clearance)
                            - (x as f64).max(r[0] - clearance);
                        let dy = ((y + region_height) as f64).min(r[1] + r[3] + clearance)
                            - (y as f64).max(r[1] - clearance);
                        dx.max(0.0) * dy.max(0.0)
                    }).sum();
                    (overlap, if self.busiest { -variance } else { variance }, y, x, variance)
                }).min_by(|a, b| a.0.total_cmp(&b.0).then(a.1.total_cmp(&b.1)).then(a.2.cmp(&b.2)).then(a.3.cmp(&b.3))).unwrap();
                best = (ranked.4, ranked.3, ranked.2);
                best_overlap = ranked.0;
                if best_overlap == 0.0 { break; }
            }
            if best_overlap > 0.0 && (hp > 0 || vp > 0) {
                // A screen margin is preferable to covering another widget.
                return Search { horizontal_padding: 0, vertical_padding: 0, slot: 0,
                                avoid_rects: taken, ..self.clone() }.run(gray, w, h);
            }
            taken.push([best.1 as f64, best.2 as f64, region_width as f64, region_height as f64]);
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
        Search { region_width: size, region_height: size, stride, horizontal_padding: padding, vertical_padding: padding, busiest, slot, gap, avoid_rects: Vec::new() }
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
    fn different_sizes_and_strategies_avoid_actual_bounds() {
        let gray: Vec<u8> = (0..900 * 600).map(|i| ((i * 73 + i / 900 * 37) % 256) as u8).collect();
        let mut occupied: Vec<[f64; 4]> = Vec::new();
        for (width, height, busiest) in [(230, 260, false), (200, 200, false), (310, 160, true)] {
            let mut placement = search(10, 100, busiest, 0, 120, width);
            placement.region_height = height;
            placement.avoid_rects = occupied.clone();
            let ((x, y), _) = placement.run(&gray, 900, 600);
            for r in &occupied {
                assert!((x + width) as f64 <= r[0] || r[0] + r[2] <= x as f64 ||
                        (y + height) as f64 <= r[1] || r[1] + r[3] <= y as f64, "{x},{y} vs {r:?}");
            }
            occupied.push([x as f64, y as f64, width as f64, height as f64]);
        }
    }

    #[test]
    fn compact_screen_uses_margins_before_overlapping() {
        let mut placement = search(10, 100, false, 0, 120, 200);
        placement.avoid_rects = vec![[0.0, 0.0, 210.0, 240.0]];
        assert_eq!(placement.run(&vec![0; 410 * 240], 410, 240).0, (210, 0));
    }

    #[test]
    fn exact_fit_between_stride_samples() {
        let mut placement = search(10, 0, false, 0, 120, 100);
        placement.avoid_rects = vec![[0.0, 0.0, 103.0, 100.0], [203.0, 0.0, 6.0, 100.0]];
        assert_eq!(placement.run(&vec![0; 209 * 100], 209, 100).0, (103, 0));
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
