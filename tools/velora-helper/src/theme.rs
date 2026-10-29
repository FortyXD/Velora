//! A theme in two steps. `stage` writes every themed file (matugen's templates and the terminal
//! palette) into a cache directory while the screen is still live; `commit` puts them in place in
//! a few milliseconds, while the screen is covered by its picture. A staged theme is kept, so
//! applying the same look again needs no generation at all.
//!
//!   theme stage --cache-root <dir> --matugen-config <config.toml> (--image <path> | --color <hex>)
//!               --mode dark|light --type <scheme> [--terminal-scheme <json> --terminal-mode dark|light
//!               --scss-target <path> --harmony <f> --harmonize-threshold <f> --term-fg-boost <f>]
//!     Prints the directory of the staged theme.
//!   theme commit <dir>
//!   theme gc --cache-root <dir> [--keep <n>]

use crate::args::Args;
use crate::terminal;
use anyhow::{bail, Context, Result};
use serde_json::{json, Value};
use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::SystemTime;

const MANIFEST: &str = "manifest.json";
// The shell reacts to its palette file, so that one goes in last, with everything else ready.
const SHELL_TEMPLATE: &str = "m3colors";

pub fn run(mut argv: Vec<String>) -> Result<()> {
    if argv.is_empty() {
        bail!("usage: velora-helper theme <stage|commit|gc> ...");
    }
    match argv.remove(0).as_str() {
        "stage" => stage(Args::parse(argv, &[])?),
        "commit" => {
            let args = Args::parse(argv, &[])?;
            let dir = args.positional.first().context("theme commit needs the staged directory")?;
            commit(Path::new(dir))
        }
        "gc" => {
            let args = Args::parse(argv, &[])?;
            gc(Path::new(args.require("cache-root")?), args.number("keep", 40)?)
        }
        other => bail!("unknown theme command: {other}"),
    }
}

fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
}

/// `~/x` → `$HOME/x`; relative paths are taken from `base`, as matugen does for its config.
fn expand(path: &str, base: &Path) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        home().join(rest)
    } else if path == "~" {
        home()
    } else if Path::new(path).is_absolute() {
        PathBuf::from(path)
    } else {
        base.join(path)
    }
}

/// FNV-1a: stable across builds, unlike std's hasher, so the cache survives an update.
struct Fnv(u64);
impl Fnv {
    fn new() -> Self {
        Self(0xcbf29ce484222325)
    }
    fn add(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.0 ^= u64::from(*byte);
            self.0 = self.0.wrapping_mul(0x100000001b3);
        }
        self.0 ^= 0xff; // Separates fields: ("ab", "c") ≠ ("a", "bc")
        self.0 = self.0.wrapping_mul(0x100000001b3);
    }
    fn add_file(&mut self, path: &Path) {
        match fs::metadata(path) {
            Ok(meta) => {
                let modified = meta.modified().ok().and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok());
                self.add(path.as_os_str().as_encoded_bytes());
                self.add(&meta.len().to_le_bytes());
                self.add(&modified.map_or(0, |d| d.as_nanos()).to_le_bytes());
            }
            Err(_) => self.add(b"missing"),
        }
    }
}

struct Template {
    name: String,
    table: toml::Table,
    target: PathBuf,
}

fn read_templates(config: &Path) -> Result<(toml::Table, Vec<Template>)> {
    let text = fs::read_to_string(config).with_context(|| format!("can't read {}", config.display()))?;
    let mut root: toml::Table = text.parse().with_context(|| format!("can't parse {}", config.display()))?;
    let base = config.parent().unwrap_or(Path::new("/")).to_path_buf();
    let mut templates = Vec::new();
    if let Some(toml::Value::Table(table)) = root.remove("templates") {
        for (name, value) in table {
            let toml::Value::Table(mut template) = value else { continue };
            let Some(output) = template.get("output_path").and_then(toml::Value::as_str) else { continue };
            let target = expand(output, &base);
            if let Some(input) = template.get("input_path").and_then(toml::Value::as_str) {
                let input = expand(input, &base).to_string_lossy().into_owned();
                template.insert("input_path".into(), toml::Value::String(input));
            }
            templates.push(Template { name, table: template, target });
        }
    }
    // The shell's palette last, see SHELL_TEMPLATE
    templates.sort_by_key(|t| t.name == SHELL_TEMPLATE);
    Ok((root, templates))
}

fn stage(args: Args) -> Result<()> {
    args.reject_unknown(&["cache-root", "matugen-config", "image", "color", "mode", "type", "terminal-scheme",
        "terminal-mode", "scss-target", "harmony", "harmonize-threshold", "term-fg-boost", "matugen"])?;
    let cache_root = PathBuf::from(args.require("cache-root")?);
    let config = PathBuf::from(args.require("matugen-config")?);
    let mode = args.value("mode").unwrap_or("dark").to_string();
    let scheme = args.value("type").unwrap_or("scheme-tonal-spot").to_string();
    let image = args.value("image").map(PathBuf::from);
    let color = args.value("color").map(str::to_string);
    if image.is_none() == color.is_none() {
        bail!("give exactly one of --image and --color");
    }
    if let Some(color) = &color {
        terminal::parse_hex(color)?;
    }
    let terminal_mode = args.value("terminal-mode").unwrap_or(&mode).to_string();
    let harmony: f64 = args.number("harmony", 0.8)?;
    let threshold: f64 = args.number("harmonize-threshold", 100.0)?;
    let boost: f64 = args.number("term-fg-boost", 0.35)?;
    let (root, templates) = read_templates(&config)?;

    // Everything that changes the output is in the key
    let mut key = Fnv::new();
    key.add(env!("CARGO_PKG_VERSION").as_bytes());
    for value in [&mode, &scheme, &terminal_mode, &color.clone().unwrap_or_default()] {
        key.add(value.as_bytes());
    }
    for value in [harmony, threshold, boost] {
        key.add(&value.to_le_bytes());
    }
    if let Some(image) = &image {
        key.add_file(image);
    }
    key.add_file(&config);
    for template in &templates {
        key.add(template.name.as_bytes());
        key.add(template.target.as_os_str().as_encoded_bytes());
        if let Some(input) = template.table.get("input_path").and_then(toml::Value::as_str) {
            key.add_file(Path::new(input));
        }
    }
    for name in ["terminal-scheme", "scss-target"] {
        key.add(args.value(name).unwrap_or_default().as_bytes());
    }
    if let Some(path) = args.value("terminal-scheme") {
        key.add_file(Path::new(path));
    }
    let dir = cache_root.join(format!("{:016x}", key.0));
    if dir.join(MANIFEST).is_file() {
        touch(&dir);
        println!("{}", dir.display());
        return Ok(());
    }

    // Built aside and renamed into place, so an interrupted run never looks complete
    fs::create_dir_all(&cache_root)?;
    let building = cache_root.join(format!(".{:016x}.{}", key.0, std::process::id()));
    let _ = fs::remove_dir_all(&building);
    fs::create_dir_all(building.join("files"))?;
    let result = build(&building, &root, &templates, &args, image.as_deref(), color.as_deref(), &mode, &scheme,
        &terminal_mode, harmony, threshold, boost);
    if let Err(error) = result {
        let _ = fs::remove_dir_all(&building);
        return Err(error);
    }
    let _ = fs::remove_dir_all(&dir);
    fs::rename(&building, &dir).context("can't store the staged theme")?;
    let _ = gc(&cache_root, 40);
    println!("{}", dir.display());
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn build(building: &Path, root: &toml::Table, templates: &[Template], args: &Args, image: Option<&Path>,
    color: Option<&str>, mode: &str, scheme: &str, terminal_mode: &str, harmony: f64, threshold: f64, boost: f64) -> Result<()> {
    let mut files = Vec::new();
    let mut hooks = Vec::new();
    let mut staged = toml::Table::new();
    let mut staged_templates = toml::Table::new();
    for template in templates {
        let mut table = template.table.clone();
        // Hooks would run before the files are in place; they run on commit instead
        for hook in ["pre_hook", "post_hook"] {
            if let Some(toml::Value::String(command)) = table.remove(hook) {
                hooks.push(json!({ "when": hook, "command": command }));
            }
        }
        // Relative to the theme's directory in the manifest, so it can be renamed once complete
        let file = format!("files/{}", template.name);
        table.insert("output_path".into(), toml::Value::String(building.join(&file).to_string_lossy().into_owned()));
        staged_templates.insert(template.name.clone(), toml::Value::Table(table));
        files.push(json!({ "from": file, "to": template.target }));
    }
    for (name, value) in root {
        staged.insert(name.clone(), value.clone());
    }
    staged.insert("templates".into(), toml::Value::Table(staged_templates));
    let staged_config = building.join("matugen.toml");
    fs::write(&staged_config, toml::to_string(&staged)?)?;

    let matugen = args.value("matugen").unwrap_or("matugen");
    let mut command = Command::new(matugen);
    match (image, color) {
        (Some(image), _) => command.arg("image").arg(image),
        (_, Some(color)) => command.args(["color", "hex", color]),
        _ => unreachable!(),
    };
    command.args(["-c"]).arg(&staged_config).args(["-m", mode, "-t", scheme, "--source-color-index", "0", "--json", "hex", "-q"]);
    let output = command.output().with_context(|| format!("can't run {matugen}"))?;
    if !output.status.success() {
        bail!("matugen failed: {}", String::from_utf8_lossy(&output.stderr).trim());
    }
    let colors: Value = serde_json::from_slice(&output.stdout).context("matugen printed no colors")?;
    let source = colors.pointer("/colors/source_color/default/color").and_then(Value::as_str)
        .or(color).context("matugen gave no source color")?.to_string();

    if let (Some(termscheme), Some(target)) = (args.value("terminal-scheme"), args.value("scss-target")) {
        let text = terminal::scss(&terminal::Options {
            source: terminal::parse_hex(&source)?,
            dark: terminal_mode == "dark",
            scheme: scheme.to_string(),
            termscheme: Some(termscheme.to_string()),
            harmony,
            harmonize_threshold: threshold,
            term_fg_boost: boost,
            blend_bg_fg: true,
            transparent: false,
        })?;
        fs::write(building.join("files/material_colors.scss"), text)?;
        // Before the shell's palette, which stays last
        files.insert(files.len().saturating_sub(1), json!({ "from": "files/material_colors.scss", "to": target }));
    }
    for file in &files {
        let from = file["from"].as_str().unwrap_or_default();
        if !building.join(from).is_file() {
            bail!("matugen didn't write {from}");
        }
    }
    let manifest = json!({ "version": 1, "source": source, "mode": mode, "type": scheme, "files": files, "hooks": hooks });
    let mut file = fs::File::create(building.join(MANIFEST))?;
    file.write_all(serde_json::to_string_pretty(&manifest)?.as_bytes())?;
    file.sync_all()?;
    Ok(())
}

/// Copies (the staged theme stays cached) to a temporary name next to each target, then renames
/// it over the target, so readers see either the old file or the new one, never half of one.
fn commit(dir: &Path) -> Result<()> {
    let manifest: Value = serde_json::from_str(&fs::read_to_string(dir.join(MANIFEST))
        .with_context(|| format!("{} isn't a staged theme", dir.display()))?)?;
    let files = manifest["files"].as_array().context("the manifest lists no files")?;
    let mut pending = Vec::new();
    for file in files {
        let from = dir.join(file["from"].as_str().context("bad manifest")?);
        let to = PathBuf::from(file["to"].as_str().context("bad manifest")?);
        if let Some(parent) = to.parent() {
            fs::create_dir_all(parent)?;
        }
        // A symlinked target (dotfiles) is replaced where it points
        let to = fs::canonicalize(&to).unwrap_or(to);
        let temporary = to.with_file_name(format!(".{}.velora-{}", to.file_name().unwrap_or_default().to_string_lossy(), std::process::id()));
        fs::copy(&from, &temporary).with_context(|| format!("can't write {}", temporary.display()))?;
        pending.push((temporary, to));
    }
    for (temporary, to) in pending {
        fs::rename(&temporary, &to).with_context(|| format!("can't replace {}", to.display()))?;
    }
    touch(dir);
    for hook in manifest["hooks"].as_array().into_iter().flatten() {
        if let Some(command) = hook["command"].as_str() {
            let _ = Command::new("sh").args(["-c", command]).status();
        }
    }
    Ok(())
}

fn touch(dir: &Path) {
    let _ = fs::File::options().write(true).open(dir.join(MANIFEST)).and_then(|f| f.set_modified(SystemTime::now()));
}

/// Keeps the most recently used staged themes.
fn gc(cache_root: &Path, keep: usize) -> Result<()> {
    let mut entries: Vec<(SystemTime, PathBuf)> = fs::read_dir(cache_root)?
        .filter_map(Result::ok)
        .filter(|entry| !entry.file_name().to_string_lossy().starts_with('.'))
        .filter_map(|entry| {
            let used = fs::metadata(entry.path().join(MANIFEST)).and_then(|m| m.modified()).ok()?;
            Some((used, entry.path()))
        })
        .collect();
    entries.sort_by_key(|entry| std::cmp::Reverse(entry.0));
    for (_, path) in entries.into_iter().skip(keep) {
        let _ = fs::remove_dir_all(path);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("velora-helper-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn commit_replaces_targets_and_keeps_the_cache() {
        let root = temp("commit");
        let staged = root.join("staged");
        fs::create_dir_all(staged.join("files")).unwrap();
        fs::write(staged.join("files/a"), "new a").unwrap();
        fs::write(staged.join("files/b"), "new b").unwrap();
        let target_a = root.join("out/a.txt");
        let target_b = root.join("out/deeper/b.txt");
        fs::create_dir_all(target_a.parent().unwrap()).unwrap();
        fs::write(&target_a, "old a").unwrap();
        let manifest = json!({ "files": [{ "from": "files/a", "to": target_a }, { "from": "files/b", "to": target_b }], "hooks": [] });
        fs::write(staged.join(MANIFEST), manifest.to_string()).unwrap();
        commit(&staged).unwrap();
        assert_eq!(fs::read_to_string(&target_a).unwrap(), "new a");
        assert_eq!(fs::read_to_string(&target_b).unwrap(), "new b");
        assert!(staged.join("files/a").is_file(), "the staged copy stays cached");
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn templates_expand_home_and_put_the_shell_palette_last() {
        let root = temp("templates");
        let config = root.join("config.toml");
        fs::write(&config, "[config]\n[templates.m3colors]\ninput_path = 'a'\noutput_path = '~/x/colors.json'\n\
            [templates.gtk]\ninput_path = '/t/gtk'\noutput_path = '/o/gtk.css'\n").unwrap();
        let (_, templates) = read_templates(&config).unwrap();
        assert_eq!(templates.iter().map(|t| t.name.as_str()).collect::<Vec<_>>(), ["gtk", "m3colors"]);
        assert_eq!(templates[1].target, home().join("x/colors.json"));
        assert_eq!(templates[1].table["input_path"].as_str().unwrap(), root.join("a").to_str().unwrap());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn gc_keeps_the_newest() {
        let root = temp("gc");
        for (index, name) in ["old", "mid", "new"].iter().enumerate() {
            let dir = root.join(name);
            fs::create_dir_all(&dir).unwrap();
            let file = fs::File::create(dir.join(MANIFEST)).unwrap();
            file.set_modified(SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(1000 + index as u64)).unwrap();
        }
        gc(&root, 2).unwrap();
        assert!(!root.join("old").exists());
        assert!(root.join("mid").exists() && root.join("new").exists());
        fs::remove_dir_all(root).unwrap();
    }
}
