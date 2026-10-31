//! Port of scripts/images/find_regions.py: content regions of a screenshot for the region selector.
//! Selective search in its fast setting, the way OpenCV's ximgproc does it: Felzenszwalb's graph
//! segmentation at three scales in HSV and Lab, then neighbours merged by similarity, with the box
//! of every region along the way as a candidate.

use crate::args::Args;
use crate::picture;
use anyhow::Result;
use image::RgbImage;
use serde_json::json;
use std::collections::BTreeSet;
use std::path::Path;

const DEFAULT_IMAGE: &str = "/tmp/quickshell/media/screenshot/image";
const COLOR_BINS: usize = 25;
const TEXTURE_BINS: usize = 10;
const TEXTURE_DIRECTIONS: usize = 8;
// OpenCV's defaults for what the Python script didn't set
const MIN_SEGMENT: usize = 100;

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub struct Rect {
    pub x: i64,
    pub y: i64,
    pub width: i64,
    pub height: i64,
}

impl Rect {
    fn area(&self) -> i64 {
        self.width * self.height
    }

    fn union(&self, other: &Rect) -> Rect {
        let x = self.x.min(other.x);
        let y = self.y.min(other.y);
        Rect { x, y, width: (self.x + self.width).max(other.x + other.width) - x, height: (self.y + self.height).max(other.y + other.height) - y }
    }

    fn iou(&self, other: &Rect) -> f64 {
        let width = ((self.x + self.width).min(other.x + other.width) - self.x.max(other.x)).max(0);
        let height = ((self.y + self.height).min(other.y + other.height) - self.y.max(other.y)).max(0);
        let shared = width * height;
        let total = self.area() + other.area() - shared;
        if total > 0 { shared as f64 / total as f64 } else { 0.0 }
    }
}

pub fn run(argv: Vec<String>) -> Result<()> {
    let args = Args::parse(argv, &["single", "hyprctl"])?;
    args.reject_unknown(&["image", "min-width", "min-height", "max-width", "max-height", "single", "hyprctl", "k", "min-size", "sigma", "resize-factor"])?;
    let path = args.value("image").unwrap_or(DEFAULT_IMAGE);
    let Ok(picture) = picture::load_rgb(Path::new(path)) else {
        eprintln!("Error: Could not load image {path}");
        std::process::exit(1);
    };
    let options = Options {
        min_width: args.number("min-width", 200)?,
        min_height: args.number("min-height", 100)?,
        max_width: args.value("max-width").map(str::parse).transpose()?,
        max_height: args.value("max-height").map(str::parse).transpose()?,
        k: args.number("k", 3000)?,
        k_step: args.number("min-size", 50)?, // The script's --min-size reached OpenCV as this step
        sigma: args.number("sigma", 0.6)?,
        resize_factor: args.number("resize-factor", 0.1)?,
    };
    let mut regions = find(&picture, &options)?;
    if args.flag("single") {
        // Largest first, and the first one of equal size, as max() picks
        regions.truncate(1);
    }
    let output: Vec<_> = regions.iter().map(|r| {
        if args.flag("hyprctl") {
            json!({ "at": [r.x, r.y], "size": [r.width, r.height] })
        } else {
            json!({ "x": r.x, "y": r.y, "width": r.width, "height": r.height })
        }
    }).collect();
    println!("{}", serde_json::Value::Array(output));
    Ok(())
}

pub struct Options {
    pub min_width: i64,
    pub min_height: i64,
    pub max_width: Option<i64>,
    pub max_height: Option<i64>,
    pub k: u32,
    pub k_step: u32,
    pub sigma: f32,
    pub resize_factor: f64,
}

pub fn find(picture: &RgbImage, options: &Options) -> Result<Vec<Rect>> {
    let (original_width, original_height) = (i64::from(picture.width()), i64::from(picture.height()));
    let factor = options.resize_factor;
    let scaled = if (factor - 1.0).abs() > f64::EPSILON {
        picture::resize(picture, (f64::from(picture.width()) * factor) as u32, (f64::from(picture.height()) * factor) as u32)?
    } else {
        picture.clone()
    };
    let mut regions = Vec::new();
    for rect in selective_search(&scaled, options.k, options.k_step, options.sigma) {
        // Back to the size of the original
        let rect = if (factor - 1.0).abs() > f64::EPSILON {
            let up = |value: i64| (value as f64 / factor) as i64;
            Rect { x: up(rect.x), y: up(rect.y), width: up(rect.width), height: up(rect.height) }
        } else {
            rect
        };
        // The whole picture says nothing
        if rect.x == 0 && rect.y == 0 && rect.width == original_width && rect.height == original_height {
            continue;
        }
        if rect.width > options.min_width && rect.height > options.min_height
            && options.max_width.is_none_or(|max| rect.width < max) && options.max_height.is_none_or(|max| rect.height < max) {
            regions.push(rect);
        }
    }
    Ok(suppress(regions, 0.7))
}

/// Non-maximum suppression: the largest first, dropping what overlaps a kept one too much.
fn suppress(mut regions: Vec<Rect>, threshold: f64) -> Vec<Rect> {
    regions.sort_by_key(|rect| std::cmp::Reverse(rect.area()));
    let mut keep: Vec<Rect> = Vec::new();
    for rect in regions {
        if keep.iter().all(|kept| kept.iou(&rect) < threshold) {
            keep.push(rect);
        }
    }
    keep
}

fn selective_search(picture: &RgbImage, k: u32, k_step: u32, sigma: f32) -> Vec<Rect> {
    let (width, height) = (picture.width() as usize, picture.height() as usize);
    let mut unique = BTreeSet::new();
    let mut ordered = Vec::new();
    if width == 0 || height == 0 {
        return ordered;
    }
    for channels in [to_hsv(picture), to_lab(picture)] {
        let texture = texture_bins(&channels, width, height);
        for scale in 0..3 {
            let segments = segment(&channels, width, height, (k + k_step * scale) as f32, sigma, MIN_SEGMENT);
            let features = Features::new(&channels, &texture, &segments, width, height);
            // With and without the color term
            for use_color in [true, false] {
                for rect in group(&features, use_color) {
                    if unique.insert(rect) {
                        ordered.push(rect);
                    }
                }
            }
        }
    }
    ordered
}

// Color spaces, in the scale OpenCV gives 8-bit pictures ----------------------------------------------

fn to_hsv(picture: &RgbImage) -> Vec<[u8; 3]> {
    picture.pixels().map(|pixel| {
        let [r, g, b] = pixel.0.map(f32::from);
        let (max, min) = (r.max(g).max(b), r.min(g).min(b));
        let delta = max - min;
        let saturation = if max > 0.0 { 255.0 * delta / max } else { 0.0 };
        let hue = if delta == 0.0 {
            0.0
        } else if max == r {
            60.0 * (g - b) / delta
        } else if max == g {
            120.0 + 60.0 * (b - r) / delta
        } else {
            240.0 + 60.0 * (r - g) / delta
        };
        let hue = if hue < 0.0 { hue + 360.0 } else { hue };
        // 360° is 0°: the scale ends at 179
        [((hue / 2.0).round() as u8) % 180, saturation.round() as u8, max as u8]
    }).collect()
}

fn to_lab(picture: &RgbImage) -> Vec<[u8; 3]> {
    let linear: Vec<f32> = (0..256).map(|value| {
        let value = value as f32 / 255.0;
        if value <= 0.04045 { value / 12.92 } else { ((value + 0.055) / 1.055).powf(2.4) }
    }).collect();
    let f = |t: f32| if t > 0.008856 { t.cbrt() } else { 7.787 * t + 16.0 / 116.0 };
    picture.pixels().map(|pixel| {
        let [r, g, b] = [linear[pixel.0[0] as usize], linear[pixel.0[1] as usize], linear[pixel.0[2] as usize]];
        // D65 white
        let x = f((0.412453 * r + 0.357580 * g + 0.180423 * b) / 0.950456);
        let y = f(0.212671 * r + 0.715160 * g + 0.072169 * b);
        let z = f((0.019334 * r + 0.119193 * g + 0.950227 * b) / 1.088754);
        let lightness = 116.0 * y - 16.0;
        [(lightness * 255.0 / 100.0).round().clamp(0.0, 255.0) as u8, (500.0 * (x - y) + 128.0).round().clamp(0.0, 255.0) as u8, (200.0 * (y - z) + 128.0).round().clamp(0.0, 255.0) as u8]
    }).collect()
}

// Graph segmentation ----------------------------------------------------------------------------------

struct Sets {
    parent: Vec<u32>,
    size: Vec<u32>,
}

impl Sets {
    fn new(count: usize) -> Self {
        Self { parent: (0..count as u32).collect(), size: vec![1; count] }
    }

    fn find(&mut self, mut item: u32) -> u32 {
        while self.parent[item as usize] != item {
            let grandparent = self.parent[self.parent[item as usize] as usize];
            self.parent[item as usize] = grandparent;
            item = grandparent;
        }
        item
    }

    fn join(&mut self, a: u32, b: u32) -> u32 {
        let (big, small) = if self.size[a as usize] >= self.size[b as usize] { (a, b) } else { (b, a) };
        self.parent[small as usize] = big;
        self.size[big as usize] += self.size[small as usize];
        big
    }
}

/// A Gaussian blur of each channel, with the kernel size OpenCV derives for floating-point pictures.
fn blur(channels: &[[u8; 3]], width: usize, height: usize, sigma: f32) -> Vec<[f32; 3]> {
    let size = (((sigma * 8.0 + 1.0).round() as i32) | 1).max(1) as usize;
    let center = (size / 2) as isize;
    let mut kernel: Vec<f32> = (0..size as isize).map(|i| {
        let distance = (i - center) as f32;
        (-(distance * distance) / (2.0 * sigma * sigma)).exp()
    }).collect();
    let total: f32 = kernel.iter().sum();
    kernel.iter_mut().for_each(|value| *value /= total);
    // Edges mirror without repeating the last pixel, OpenCV's default
    let mirror = |position: isize, length: usize| -> usize {
        let last = length as isize - 1;
        if last == 0 {
            return 0;
        }
        let period = 2 * last;
        let wrapped = position.rem_euclid(period);
        (if wrapped > last { period - wrapped } else { wrapped }) as usize
    };
    let mut across = vec![[0f32; 3]; width * height];
    for y in 0..height {
        for x in 0..width {
            let mut sum = [0f32; 3];
            for (offset, weight) in kernel.iter().enumerate() {
                let pixel = channels[y * width + mirror(x as isize + offset as isize - center, width)];
                for channel in 0..3 {
                    sum[channel] += f32::from(pixel[channel]) * weight;
                }
            }
            across[y * width + x] = sum;
        }
    }
    let mut result = vec![[0f32; 3]; width * height];
    for y in 0..height {
        for x in 0..width {
            let mut sum = [0f32; 3];
            for (offset, weight) in kernel.iter().enumerate() {
                let pixel = across[mirror(y as isize + offset as isize - center, height) * width + x];
                for channel in 0..3 {
                    sum[channel] += pixel[channel] * weight;
                }
            }
            result[y * width + x] = sum;
        }
    }
    result
}

/// Felzenszwalb and Huttenlocher: the segment number of each pixel, counted in scan order.
fn segment(channels: &[[u8; 3]], width: usize, height: usize, k: f32, sigma: f32, min_size: usize) -> Vec<u32> {
    let smooth = blur(channels, width, height, sigma);
    let mut edges: Vec<(f32, u32, u32)> = Vec::with_capacity(width * height * 2);
    let mut edge = |from: usize, to: usize| {
        let (a, b) = (smooth[from], smooth[to]);
        let weight = ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt();
        edges.push((weight, from as u32, to as u32));
    };
    for y in 0..height {
        for x in 0..width {
            let here = y * width + x;
            // Left, right, up and down only: OpenCV leaves the diagonals out
            if x + 1 < width {
                edge(here, here + 1);
            }
            if y + 1 < height {
                edge(here, here + width);
            }
        }
    }
    edges.sort_unstable_by(|a, b| a.0.total_cmp(&b.0));
    let mut sets = Sets::new(width * height);
    let mut thresholds = vec![k; width * height];
    for edge in &mut edges {
        let (a, b) = (sets.find(edge.1), sets.find(edge.2));
        if a != b && edge.0 <= thresholds[a as usize] && edge.0 <= thresholds[b as usize] {
            let joined = sets.join(a, b);
            thresholds[joined as usize] = edge.0 + k / sets.size[joined as usize] as f32;
            edge.0 = 0.0; // Used up: small areas don't merge along it below
        }
    }
    for &(weight, from, to) in &edges {
        if weight <= 0.0 {
            continue;
        }
        let (a, b) = (sets.find(from), sets.find(to));
        if a != b && ((sets.size[a as usize] as usize) < min_size || (sets.size[b as usize] as usize) < min_size) {
            sets.join(a, b);
        }
    }
    let mut numbers = vec![u32::MAX; width * height];
    let mut next = 0;
    (0..width * height).map(|pixel| {
        let root = sets.find(pixel as u32) as usize;
        if numbers[root] == u32::MAX {
            numbers[root] = next;
            next += 1;
        }
        numbers[root]
    }).collect()
}

// Grouping --------------------------------------------------------------------------------------------

/// The bin of each pixel in each channel and gradient direction, for the texture histograms.
fn texture_bins(channels: &[[u8; 3]], width: usize, height: usize) -> Vec<u8> {
    let mut bins = vec![0u8; width * height * 3 * TEXTURE_DIRECTIONS];
    let at = |x: isize, y: isize, channel: usize| {
        let x = x.clamp(0, width as isize - 1) as usize;
        let y = y.clamp(0, height as isize - 1) as usize;
        f32::from(channels[y * width + x][channel])
    };
    for channel in 0..3 {
        let mut gradients = vec![[0f32; TEXTURE_DIRECTIONS]; width * height];
        let mut peak = [0f32; TEXTURE_DIRECTIONS];
        for y in 0..height as isize {
            for x in 0..width as isize {
                let dx = (at(x + 1, y - 1, channel) + 2.0 * at(x + 1, y, channel) + at(x + 1, y + 1, channel)) - (at(x - 1, y - 1, channel) + 2.0 * at(x - 1, y, channel) + at(x - 1, y + 1, channel));
                let dy = (at(x - 1, y + 1, channel) + 2.0 * at(x, y + 1, channel) + at(x + 1, y + 1, channel)) - (at(x - 1, y - 1, channel) + 2.0 * at(x, y - 1, channel) + at(x + 1, y - 1, channel));
                let directions = [dx, -dx, dy, -dy, dx + dy, -(dx + dy), dx - dy, dy - dx];
                let cell = &mut gradients[y as usize * width + x as usize];
                for (direction, value) in directions.into_iter().enumerate() {
                    let value = value.max(0.0);
                    cell[direction] = value;
                    peak[direction] = peak[direction].max(value);
                }
            }
        }
        for (pixel, cell) in gradients.iter().enumerate() {
            for direction in 0..TEXTURE_DIRECTIONS {
                let scale = if peak[direction] > 0.0 { cell[direction] / peak[direction] } else { 0.0 };
                let bin = ((scale * TEXTURE_BINS as f32) as usize).min(TEXTURE_BINS - 1);
                bins[(pixel * 3 + channel) * TEXTURE_DIRECTIONS + direction] = bin as u8;
            }
        }
    }
    bins
}

#[derive(Clone)]
struct Region {
    size: f32,
    rect: Rect,
    color: Vec<f32>,
    texture: Vec<f32>,
}

struct Features {
    regions: Vec<Region>,
    neighbours: Vec<(usize, usize)>,
    image_size: f32,
}

impl Features {
    fn new(channels: &[[u8; 3]], texture: &[u8], segments: &[u32], width: usize, height: usize) -> Self {
        let count = segments.iter().max().map_or(0, |max| *max as usize + 1);
        let color_length = COLOR_BINS * 3;
        let texture_length = TEXTURE_BINS * TEXTURE_DIRECTIONS * 3;
        let mut regions: Vec<Region> = vec![Region {
            size: 0.0,
            rect: Rect { x: i64::MAX, y: i64::MAX, width: 0, height: 0 },
            color: vec![0.0; color_length],
            texture: vec![0.0; texture_length],
        }; count];
        let mut extent = vec![(i64::MAX, i64::MAX, i64::MIN, i64::MIN); count];
        let mut neighbours = BTreeSet::new();
        for y in 0..height {
            for x in 0..width {
                let pixel = y * width + x;
                let id = segments[pixel] as usize;
                let region = &mut regions[id];
                region.size += 1.0;
                let box_ = &mut extent[id];
                *box_ = (box_.0.min(x as i64), box_.1.min(y as i64), box_.2.max(x as i64), box_.3.max(y as i64));
                for channel in 0..3 {
                    region.color[channel * COLOR_BINS + usize::from(channels[pixel][channel]) * COLOR_BINS / 256] += 1.0;
                    for direction in 0..TEXTURE_DIRECTIONS {
                        let bin = usize::from(texture[(pixel * 3 + channel) * TEXTURE_DIRECTIONS + direction]);
                        region.texture[(channel * TEXTURE_DIRECTIONS + direction) * TEXTURE_BINS + bin] += 1.0;
                    }
                }
                // Left, up and up-left, away from the first row and column, as OpenCV does
                if x > 0 && y > 0 {
                    for other in [pixel - 1, pixel - width, pixel - width - 1] {
                        let other = segments[other] as usize;
                        if other != id {
                            neighbours.insert((id.max(other), id.min(other)));
                        }
                    }
                }
            }
        }
        for (region, box_) in regions.iter_mut().zip(&extent) {
            region.rect = Rect { x: box_.0, y: box_.1, width: box_.2 - box_.0 + 1, height: box_.3 - box_.1 + 1 };
            normalize(&mut region.color);
            normalize(&mut region.texture);
        }
        Self { regions, neighbours: neighbours.into_iter().collect(), image_size: (width * height) as f32 }
    }
}

fn normalize(histogram: &mut [f32]) {
    let total: f32 = histogram.iter().sum();
    if total > 0.0 {
        histogram.iter_mut().for_each(|value| *value /= total);
    }
}

fn overlap(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b).map(|(x, y)| x.min(*y)).sum()
}

fn similarity(a: &Region, b: &Region, image_size: f32, use_color: bool) -> f32 {
    let bounds = a.rect.union(&b.rect).area() as f32;
    let fill = 1.0 - (bounds - a.size - b.size) / image_size;
    let size = 1.0 - (a.size + b.size) / image_size;
    let texture = overlap(&a.texture, &b.texture);
    if use_color {
        (overlap(&a.color, &b.color) + fill + texture + size) / 4.0
    } else {
        (fill + texture + size) / 3.0
    }
}

fn merged(a: &Region, b: &Region) -> Region {
    let mix = |x: &[f32], y: &[f32]| -> Vec<f32> {
        x.iter().zip(y).map(|(p, q)| (p * a.size + q * b.size) / (a.size + b.size)).collect()
    };
    Region { size: a.size + b.size, rect: a.rect.union(&b.rect), color: mix(&a.color, &b.color), texture: mix(&a.texture, &b.texture) }
}

/// Merges the most similar neighbours until one region is left. Returns the box of every region seen.
fn group(features: &Features, use_color: bool) -> Vec<Rect> {
    let mut regions = features.regions.clone();
    let mut pairs: Vec<(f32, usize, usize)> = features.neighbours.iter()
        .map(|&(a, b)| (similarity(&regions[a], &regions[b], features.image_size, use_color), a, b))
        .collect();
    let mut rects: Vec<Rect> = regions.iter().map(|region| region.rect).collect();
    while let Some(best) = pairs.iter().enumerate().max_by(|a, b| a.1 .0.total_cmp(&b.1 .0)).map(|(position, _)| position) {
        let (_, a, b) = pairs.swap_remove(best);
        let new = merged(&regions[a], &regions[b]);
        rects.push(new.rect);
        let id = regions.len();
        regions.push(new);
        let mut around = BTreeSet::new();
        pairs.retain(|&(_, from, to)| {
            if from == a || from == b || to == a || to == b {
                around.insert(if from == a || from == b { to } else { from });
                false
            } else {
                true
            }
        });
        around.remove(&a);
        around.remove(&b);
        for other in around {
            pairs.push((similarity(&regions[id], &regions[other], features.image_size, use_color), id, other));
        }
    }
    rects
}

#[cfg(test)]
mod tests {
    use super::*;

    fn options(factor: f64) -> Options {
        Options { min_width: 20, min_height: 20, max_width: None, max_height: None, k: 3000, k_step: 50, sigma: 0.6, resize_factor: factor }
    }

    /// A dark desktop with a light window.
    fn desktop() -> RgbImage {
        RgbImage::from_fn(400, 300, |x, y| {
            if (100..300).contains(&x) && (60..220).contains(&y) { image::Rgb([235, 235, 240]) } else { image::Rgb([20, 30, 40]) }
        })
    }

    #[test]
    fn finds_a_window_on_a_plain_desktop() {
        let found = find(&desktop(), &options(1.0)).unwrap();
        let window = Rect { x: 100, y: 60, width: 200, height: 160 };
        assert!(found.iter().any(|rect| rect.iou(&window) > 0.8), "{found:?}");
    }

    #[test]
    fn the_whole_picture_is_not_a_region() {
        let found = find(&desktop(), &options(1.0)).unwrap();
        assert!(!found.iter().any(|rect| rect.width == 400 && rect.height == 300), "{found:?}");
    }

    #[test]
    fn limits_are_exclusive() {
        let mut limited = options(1.0);
        limited.max_width = Some(200);
        let found = find(&desktop(), &limited).unwrap();
        assert!(found.iter().all(|rect| rect.width < 200), "{found:?}");
    }

    #[test]
    fn overlapping_boxes_collapse_to_the_largest() {
        let big = Rect { x: 0, y: 0, width: 100, height: 100 };
        let close = Rect { x: 0, y: 0, width: 95, height: 95 };
        let apart = Rect { x: 200, y: 0, width: 50, height: 50 };
        assert_eq!(suppress(vec![close, apart, big], 0.7), [big, apart]);
    }

    #[test]
    fn colors_match_opencv() {
        let picture = RgbImage::from_fn(3, 1, |x, _| [image::Rgb([255, 0, 0]), image::Rgb([0, 255, 0]), image::Rgb([255, 255, 255])][x as usize]);
        assert_eq!(to_hsv(&picture), [[0, 255, 255], [60, 255, 255], [0, 0, 255]]);
        let lab = to_lab(&picture);
        // cv2.cvtColor gives (136, 208, 195) for pure red and (255, 128, 128) for white
        assert!((i32::from(lab[0][0]) - 136).abs() <= 1 && (i32::from(lab[0][1]) - 208).abs() <= 1 && (i32::from(lab[0][2]) - 195).abs() <= 1, "{lab:?}");
        assert_eq!(lab[2], [255, 128, 128]);
    }
}
