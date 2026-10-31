//! Port of scripts/keyboard/layout_keys.py: what each key of a keyboard layout types, as JSON, for the drawn
//! keyboard in Settings → Keyboard. "code" is the XKB keycode, which Qt reports as a key event's nativeScanCode
//! on Wayland. Results are cached, as the compiler takes a moment.

use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

const HEADER: &str = "/usr/include/xkbcommon/xkbcommon-keysyms.h";

fn valid_name(name: &str) -> bool {
    !name.is_empty() && name.bytes().all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'(' | b')' | b'-'))
}

/// Keysym name → character, from the comments in xkbcommon's header (`/* U+0439 CYRILLIC ... */`).
fn keysym_characters(header: &str) -> HashMap<String, char> {
    let mut symbols = HashMap::new();
    for line in header.lines() {
        let Some(rest) = line.strip_prefix("#define XKB_KEY_") else { continue };
        let mut parts = rest.split_whitespace();
        let (Some(name), Some(value)) = (parts.next(), parts.next()) else { continue };
        if !value.starts_with("0x") || parts.next() != Some("/*") {
            continue;
        }
        let Some(code) = parts.next().and_then(|word| word.strip_prefix("U+")) else { continue };
        let digits = code.chars().take_while(char::is_ascii_hexdigit).count();
        if !(4..=6).contains(&digits) {
            continue;
        }
        if let Some(character) = u32::from_str_radix(&code[..digits], 16).ok().and_then(char::from_u32) {
            symbols.entry(name.to_string()).or_insert(character);
        }
    }
    symbols
}

/// The accent a dead key adds to the next key.
fn dead_key(keysym: &str) -> Option<&'static str> {
    Some(match keysym {
        "dead_grave" => "`",
        "dead_acute" => "´",
        "dead_circumflex" => "^",
        "dead_tilde" => "~",
        "dead_diaeresis" => "¨",
        "dead_cedilla" => "¸",
        "dead_caron" => "ˇ",
        "dead_breve" => "˘",
        "dead_abovering" => "˚",
        "dead_macron" => "¯",
        "dead_doubleacute" => "˝",
        "dead_ogonek" => "˛",
        "dead_abovedot" => "˙",
        _ => return None,
    })
}

fn character(keysym: &str, symbols: &HashMap<String, char>) -> String {
    if let Some(character) = symbols.get(keysym) {
        return character.to_string();
    }
    if let Some(accent) = dead_key(keysym) {
        return accent.to_string();
    }
    // Unicode keysyms, e.g. U0451
    keysym
        .strip_prefix('U')
        .filter(|digits| (4..=6).contains(&digits.len()) && digits.bytes().all(|byte| byte.is_ascii_hexdigit()))
        .and_then(|digits| u32::from_str_radix(digits, 16).ok())
        .and_then(char::from_u32)
        .map(String::from)
        .unwrap_or_default()
}

/// Reads a compiled keymap: the codes of key names, then what each key types.
pub fn keys_from_keymap(keymap: &str, symbols: &HashMap<String, char>) -> Map<String, Value> {
    let mut codes = HashMap::new();
    for line in keymap.lines() {
        let line = line.trim();
        let Some(rest) = line.strip_prefix('<') else { continue };
        let Some((name, value)) = rest.split_once('>') else { continue };
        let Some(number) = value.trim().strip_prefix('=').and_then(|value| value.trim().strip_suffix(';')) else { continue };
        if let Ok(number) = number.trim().parse::<i64>() {
            codes.insert(name.to_string(), number);
        }
    }
    let mut keys = Map::new();
    let mut rest = keymap;
    while let Some(start) = rest.find("key <") {
        // Only at the start of a line, as anything else is part of another statement
        let before = &rest[..start];
        let at_line_start = before.rsplit('\n').next().is_some_and(|line| line.trim().is_empty());
        let after = &rest[start + 5..];
        rest = after;
        if !at_line_start {
            continue;
        }
        let Some((name, body)) = after.split_once('>') else { break };
        // Names like <VOL-> are media keys the drawn keyboard has no place for
        if !name.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'_') {
            continue;
        }
        let Some(open) = body.trim_start().strip_prefix('{') else { continue };
        let Some((inside, _)) = open.split_once("};") else { break };
        let Some(group_start) = inside.find('[') else { continue };
        let Some(group_end) = inside[group_start..].find(']') else { continue };
        let group = &inside[group_start + 1..group_start + group_end];
        let levels: Vec<String> = group.split(',').map(|keysym| character(keysym.trim(), symbols)).collect();
        keys.insert(name.to_string(), json!({ "code": codes.get(name).copied().unwrap_or(0), "levels": levels }));
    }
    keys
}

fn cache_directory() -> PathBuf {
    std::env::var_os("XDG_CACHE_HOME").map_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".cache"), PathBuf::from).join("quickshell/keyboard")
}

pub fn run(argv: Vec<String>) -> Result<()> {
    let layout = argv.first().map_or("us", String::as_str);
    let variant = argv.get(1).map_or("", String::as_str);
    if !valid_name(layout) || (!variant.is_empty() && !valid_name(variant)) {
        bail!("bad layout name");
    }
    let directory = cache_directory();
    let cache = directory.join(format!("{layout}-{}.json", if variant.is_empty() { "standard" } else { variant }));
    if let Ok(text) = fs::read_to_string(&cache) {
        println!("{text}");
        return Ok(());
    }
    // The system's own tool; an `xkbcli` earlier in PATH (e.g. from conda) may lack compile-keymap
    let system = "/usr/lib/xkbcommon/xkbcli-compile-keymap";
    let mut command = if std::path::Path::new(system).exists() {
        Command::new(system)
    } else {
        let mut command = Command::new("xkbcli");
        command.arg("compile-keymap");
        command
    };
    command.args(["--layout", layout]);
    if !variant.is_empty() {
        command.args(["--variant", variant]);
    }
    let output = command.output().context("couldn't run the keymap compiler")?;
    if !output.status.success() {
        return Err(anyhow!("the keymap compiler refused {layout} {variant}"));
    }
    let header = fs::read(std::env::var_os("VELORA_XKB_KEYSYMS").map_or_else(|| PathBuf::from(HEADER), PathBuf::from))?;
    let symbols = keysym_characters(&String::from_utf8_lossy(&header));
    let keys = keys_from_keymap(&String::from_utf8_lossy(&output.stdout), &symbols);
    let result = json!({ "layout": layout, "variant": variant, "keys": keys }).to_string();
    fs::create_dir_all(&directory)?;
    let staged = cache.with_extension("json.tmp");
    fs::write(&staged, &result)?;
    fs::rename(&staged, &cache)?;
    println!("{result}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const HEADER_SAMPLE: &str = "#define XKB_KEY_a                             0x0061  /* U+0061 LATIN SMALL LETTER A */\n\
        #define XKB_KEY_Cyrillic_shorti              0x06ca  /* U+0439 CYRILLIC SMALL LETTER SHORT I */\n\
        #define XKB_KEY_NoSymbol                      0x000000  /* Special KeySym */\n\
        #define XKB_KEY_a                             0x0099  /* U+0099 A LATER DUPLICATE */\n";

    #[test]
    fn keysyms_read_from_their_comments_and_the_first_one_counts() {
        let symbols = keysym_characters(HEADER_SAMPLE);
        assert_eq!(symbols["a"], 'a');
        assert_eq!(symbols["Cyrillic_shorti"], 'й');
        assert!(!symbols.contains_key("NoSymbol"));
    }

    #[test]
    fn characters_come_from_the_table_dead_keys_or_the_name_itself() {
        let symbols = keysym_characters(HEADER_SAMPLE);
        assert_eq!(character("a", &symbols), "a");
        assert_eq!(character("dead_acute", &symbols), "´");
        assert_eq!(character("U0451", &symbols), "ё");
        assert_eq!(character("NoSymbol", &symbols), "");
        assert_eq!(character("Up", &symbols), "");
    }

    #[test]
    fn a_keymap_gives_codes_and_levels() {
        let keymap = "xkb_keycodes {\n    <AD01> = 24;\n    <AD02> = 25;\n};\nxkb_symbols {\n    key <AD01> {\t[ a, Cyrillic_shorti ] };\n    key <AD02> {\n        type= \"ALPHABETIC\",\n        [ U0451, dead_acute ]\n    };\n    key <NONE> { type= \"X\" };\n    other key <SKIP> { [ a ] };\n    key <VOL-> { [ a ] };\n};\n";
        let keys = keys_from_keymap(keymap, &keysym_characters(HEADER_SAMPLE));
        assert_eq!(keys["AD01"], json!({ "code": 24, "levels": ["a", "й"] }));
        assert_eq!(keys["AD02"], json!({ "code": 25, "levels": ["ё", "´"] }));
        assert!(!keys.contains_key("NONE"));
        assert!(!keys.contains_key("SKIP"));
        assert!(!keys.contains_key("VOL-"));
    }

    #[test]
    fn names_are_checked_before_they_reach_a_command() {
        assert!(valid_name("us") && valid_name("de(nodeadkeys)") && valid_name("a_b-c"));
        assert!(!valid_name("") && !valid_name("us;rm") && !valid_name("a b"));
    }
}
