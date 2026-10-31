//! Port of scripts/images/text_color.py: the background and text color of a crop of the screen, for
//! the screen translator. The picture comes over stdin, the colors go out as JSON.

use anyhow::Result;
use image::RgbImage;
use serde_json::json;
use std::io::Read as _;

pub fn run() -> Result<()> {
    let mut bytes = Vec::new();
    std::io::stdin().read_to_end(&mut bytes)?;
    if bytes.is_empty() {
        println!("{}", json!({ "error": "No data received via stdin" }));
        return Ok(());
    }
    let Ok(picture) = image::load_from_memory(&bytes) else {
        println!("{}", json!({ "error": "Could not decode image data" }));
        return Ok(());
    };
    let (background, text) = colors(&picture.into_rgb8());
    println!("{}", json!({ "background": hex(background), "text": hex(text) }));
    Ok(())
}

fn hex(color: [u8; 3]) -> String {
    format!("#{:02x}{:02x}{:02x}", color[0], color[1], color[2])
}

/// NumPy's median: an even count averages the middle pair. Converting to int truncates it.
fn median(values: &mut [u8]) -> u8 {
    values.sort_unstable();
    let n = values.len();
    if n.is_multiple_of(2) { ((u16::from(values[n / 2 - 1]) + u16::from(values[n / 2])) / 2) as u8 } else { values[n / 2] }
}

fn channel_median(pixels: &[[u8; 3]]) -> [u8; 3] {
    [0, 1, 2].map(|channel| {
        let mut values: Vec<u8> = pixels.iter().map(|pixel| pixel[channel]).collect();
        median(&mut values)
    })
}

pub fn colors(picture: &RgbImage) -> ([u8; 3], [u8; 3]) {
    let (width, height) = picture.dimensions();
    // The corners anchor the background; a median handles noise and gradients better than an average
    let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)].map(|(x, y)| picture.get_pixel(x, y).0);
    let background = channel_median(&corners);

    let distance = |pixel: &[u8; 3]| -> f64 {
        (0..3).map(|channel| (f64::from(pixel[channel]) - f64::from(background[channel])).powi(2)).sum::<f64>().sqrt()
    };
    let pixels: Vec<[u8; 3]> = picture.pixels().map(|pixel| pixel.0).collect();
    let mut distances: Vec<f64> = pixels.iter().map(distance).collect();
    distances.sort_unstable_by(f64::total_cmp);
    // The 95th percentile, interpolated like NumPy's: the text is what lies furthest from the background
    let position = (distances.len() - 1) as f64 * 0.95;
    let (below, above) = (position.floor() as usize, position.ceil() as usize);
    let threshold = distances[below] + (distances[above] - distances[below]) * (position - below as f64);
    let text: Vec<[u8; 3]> = pixels.into_iter().filter(|pixel| distance(pixel) >= threshold).collect();
    (background, if text.is_empty() { [255, 255, 255] } else { channel_median(&text) })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dark_text_on_a_light_background() {
        let picture = RgbImage::from_fn(100, 20, |x, _| if x % 10 == 5 { image::Rgb([10, 20, 30]) } else { image::Rgb([240, 240, 230]) });
        assert_eq!(colors(&picture), ([240, 240, 230], [10, 20, 30]));
    }

    #[test]
    fn a_plain_picture_has_one_color() {
        let picture = RgbImage::from_pixel(8, 8, image::Rgb([9, 8, 7]));
        assert_eq!(colors(&picture), ([9, 8, 7], [9, 8, 7]));
    }

    #[test]
    fn a_single_pixel_works() {
        let picture = RgbImage::from_pixel(1, 1, image::Rgb([1, 2, 3]));
        assert_eq!(colors(&picture), ([1, 2, 3], [1, 2, 3]));
    }
}
