//! Port of scripts/colors/generate_colors_material.py: the material palette and harmonized
//! terminal colors as SCSS variables (material_colors.scss), from a source color. The source is
//! the one matugen chose, so terminals match the shell exactly.

use crate::args::Args;
use anyhow::{bail, Context, Result};
use material_colors::color::Rgb;
use material_colors::dynamic_color::{DynamicScheme, Variant};
use material_colors::hct::Hct;
use material_colors::utils::math::{difference_degrees, rotate_direction, sanitize_degrees_double};
use std::fmt::Write as _;
use std::path::Path;
use std::str::FromStr;

pub struct Options {
    pub source: Rgb,
    pub dark: bool,
    pub scheme: String,
    pub termscheme: Option<String>,
    pub harmony: f64,
    pub harmonize_threshold: f64,
    pub term_fg_boost: f64,
    pub blend_bg_fg: bool,
    pub transparent: bool,
}

pub fn run(argv: Vec<String>) -> Result<()> {
    let args = Args::parse(argv, &["blend-bg-fg"])?;
    args.reject_unknown(&["source", "color", "mode", "scheme", "termscheme", "harmony", "harmonize-threshold",
        "term-fg-boost", "blend-bg-fg", "transparency"])?;
    let source = args.value("source").or_else(|| args.value("color")).context("--source is required")?;
    let options = Options {
        source: parse_hex(source)?,
        dark: args.value("mode").unwrap_or("dark") == "dark",
        scheme: args.value("scheme").unwrap_or("scheme-tonal-spot").to_string(),
        termscheme: args.value("termscheme").map(str::to_string),
        harmony: args.number("harmony", 0.8)?,
        harmonize_threshold: args.number("harmonize-threshold", 100.0)?,
        term_fg_boost: args.number("term-fg-boost", 0.35)?,
        blend_bg_fg: args.flag("blend-bg-fg"),
        transparent: args.value("transparency") == Some("transparent"),
    };
    print!("{}", scss(&options)?);
    Ok(())
}

pub fn parse_hex(text: &str) -> Result<Rgb> {
    let text = text.trim();
    if text.trim_start_matches('#').len() != 6 {
        bail!("not a #RRGGBB color: {text}");
    }
    Rgb::from_str(text).map_err(|_| anyhow::anyhow!("not a #RRGGBB color: {text}"))
}

pub fn variant(name: &str) -> Variant {
    match name.trim_start_matches("scheme-") {
        "fruit-salad" => Variant::FruitSalad,
        "expressive" => Variant::Expressive,
        "monochrome" => Variant::Monochrome,
        "rainbow" => Variant::Rainbow,
        "neutral" => Variant::Neutral,
        "fidelity" => Variant::Fidelity,
        "content" => Variant::Content,
        "vibrant" => Variant::Vibrant,
        _ => Variant::TonalSpot,
    }
}

fn hex(color: Rgb) -> String {
    format!("#{:02X}{:02X}{:02X}", color.red, color.green, color.blue)
}

fn harmonize(design: Rgb, source: Rgb, threshold: f64, harmony: f64) -> Rgb {
    let from = Hct::new(design);
    let to = Hct::new(source);
    let rotation = (difference_degrees(from.get_hue(), to.get_hue()) * harmony).min(threshold);
    let hue = sanitize_degrees_double(from.get_hue() + rotation * rotate_direction(from.get_hue(), to.get_hue()));
    Hct::from(hue, from.get_chroma(), from.get_tone()).into()
}

fn boost_chroma_tone(color: Rgb, chroma: f64, tone: f64) -> Rgb {
    let hct = Hct::new(color);
    Hct::from(hct.get_hue(), hct.get_chroma() * chroma, hct.get_tone() * tone).into()
}

/// The SCSS file, in the order and spelling the Python script printed.
pub fn scss(options: &Options) -> Result<String> {
    let scheme = DynamicScheme::by_variant(options.source, &variant(&options.scheme), options.dark, Some(0.0));
    let s = &scheme;
    let material: Vec<(&str, Rgb)> = vec![
        ("primary_paletteKeyColor", s.primary_palette_key_color()),
        ("secondary_paletteKeyColor", s.secondary_palette_key_color()),
        ("tertiary_paletteKeyColor", s.tertiary_palette_key_color()),
        ("neutral_paletteKeyColor", s.neutral_palette_key_color()),
        ("neutral_variant_paletteKeyColor", s.neutral_variant_palette_key_color()),
        ("background", s.background()),
        ("onBackground", s.on_background()),
        ("surface", s.surface()),
        ("surfaceDim", s.surface_dim()),
        ("surfaceBright", s.surface_bright()),
        ("surfaceContainerLowest", s.surface_container_lowest()),
        ("surfaceContainerLow", s.surface_container_low()),
        ("surfaceContainer", s.surface_container()),
        ("surfaceContainerHigh", s.surface_container_high()),
        ("surfaceContainerHighest", s.surface_container_highest()),
        ("onSurface", s.on_surface()),
        ("surfaceVariant", s.surface_variant()),
        ("onSurfaceVariant", s.on_surface_variant()),
        ("inverseSurface", s.inverse_surface()),
        ("inverseOnSurface", s.inverse_on_surface()),
        ("outline", s.outline()),
        ("outlineVariant", s.outline_variant()),
        ("shadow", s.shadow()),
        ("scrim", s.scrim()),
        ("surfaceTint", s.surface_tint()),
        ("primary", s.primary()),
        ("onPrimary", s.on_primary()),
        ("primaryContainer", s.primary_container()),
        ("onPrimaryContainer", s.on_primary_container()),
        ("inversePrimary", s.inverse_primary()),
        ("secondary", s.secondary()),
        ("onSecondary", s.on_secondary()),
        ("secondaryContainer", s.secondary_container()),
        ("onSecondaryContainer", s.on_secondary_container()),
        ("tertiary", s.tertiary()),
        ("onTertiary", s.on_tertiary()),
        ("tertiaryContainer", s.tertiary_container()),
        ("onTertiaryContainer", s.on_tertiary_container()),
        ("error", s.error()),
        ("onError", s.on_error()),
        ("errorContainer", s.error_container()),
        ("onErrorContainer", s.on_error_container()),
        ("primaryFixed", s.primary_fixed()),
        ("primaryFixedDim", s.primary_fixed_dim()),
        ("onPrimaryFixed", s.on_primary_fixed()),
        ("onPrimaryFixedVariant", s.on_primary_fixed_variant()),
        ("secondaryFixed", s.secondary_fixed()),
        ("secondaryFixedDim", s.secondary_fixed_dim()),
        ("onSecondaryFixed", s.on_secondary_fixed()),
        ("onSecondaryFixedVariant", s.on_secondary_fixed_variant()),
        ("tertiaryFixed", s.tertiary_fixed()),
        ("tertiaryFixedDim", s.tertiary_fixed_dim()),
        ("onTertiaryFixed", s.on_tertiary_fixed()),
        ("onTertiaryFixedVariant", s.on_tertiary_fixed_variant()),
    ];
    let success: [(&str, &str); 4] = if options.dark {
        [("success", "#B5CCBA"), ("onSuccess", "#213528"), ("successContainer", "#374B3E"), ("onSuccessContainer", "#D1E9D6")]
    } else {
        [("success", "#4F6354"), ("onSuccess", "#FFFFFF"), ("successContainer", "#D1E8D5"), ("onSuccessContainer", "#0C1F13")]
    };

    let mut out = String::new();
    let python_bool = |value: bool| if value { "True" } else { "False" };
    writeln!(out, "$darkmode: {};", python_bool(options.dark))?;
    writeln!(out, "$transparent: {};", python_bool(options.transparent))?;
    for (name, color) in &material {
        writeln!(out, "${name}: {};", hex(*color))?;
    }
    for (name, color) in success {
        writeln!(out, "${name}: {color};")?;
    }

    if let Some(path) = &options.termscheme {
        let text = std::fs::read_to_string(Path::new(path)).with_context(|| format!("can't read {path}"))?;
        let json: serde_json::Value = serde_json::from_str(&text).with_context(|| format!("can't parse {path}"))?;
        let colors = json
            .get(if options.dark { "dark" } else { "light" })
            .and_then(serde_json::Value::as_object)
            .with_context(|| format!("{path} has no {} colors", if options.dark { "dark" } else { "light" }))?;
        let primary_key = s.primary_palette_key_color();
        for (name, value) in colors {
            let base = parse_hex(value.as_str().unwrap_or_default())?;
            let color = if options.blend_bg_fg && name == "term0" {
                boost_chroma_tone(s.surface_container_low(), 1.2, 0.95)
            } else if options.blend_bg_fg && name == "term15" {
                boost_chroma_tone(s.on_surface(), 3.0, 1.0)
            } else {
                let harmonized = harmonize(base, primary_key, options.harmonize_threshold, options.harmony);
                boost_chroma_tone(harmonized, 1.0, 1.0 + options.term_fg_boost * if options.dark { 1.0 } else { -1.0 })
            };
            writeln!(out, "${name}: {};", hex(color))?;
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn options(source: &str, dark: bool) -> Options {
        Options {
            source: parse_hex(source).unwrap(),
            dark,
            scheme: "scheme-tonal-spot".into(),
            termscheme: None,
            harmony: 0.8,
            harmonize_threshold: 100.0,
            term_fg_boost: 0.35,
            blend_bg_fg: true,
            transparent: false,
        }
    }

    // matugen 4.2 gives #c2c1ff for this source, tonal spot, dark: the shell and the terminals agree
    #[test]
    fn matches_matugen() {
        let text = scss(&options("#9190dc", true)).unwrap();
        assert!(text.contains("$primary: #C2C1FF;"), "{text}");
        assert!(text.contains("$surface: #131318;"), "{text}");
        assert!(text.starts_with("$darkmode: True;\n$transparent: False;\n$primary_paletteKeyColor:"));
    }

    #[test]
    fn light_mode_uses_light_success_colors() {
        let text = scss(&options("#B388FF", false)).unwrap();
        assert!(text.contains("$darkmode: False;"));
        assert!(text.contains("$success: #4F6354;"));
    }

    #[test]
    fn rejects_bad_colors() {
        assert!(parse_hex("#12345").is_err());
        assert!(parse_hex("zzzzzz").is_err());
    }
}
