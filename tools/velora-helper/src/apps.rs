//! Port of hypr/hyprland/scripts/default_apps.py: default apps, and asking which app opens a file type
//! the first time. Every Super+Return goes through here, so it mustn't cost an interpreter.
//!
//! Roles backed by MIME types (browser, file manager, images...) live in ~/.config/mimeapps.list, so
//! every app that opens links or files agrees with them. File types nobody picked an app for point to
//! the chooser (folis-open-with.desktop): it asks the shell which app to use and can remember the
//! answer in the same file. Roles without a MIME type (terminal, code editor) live in
//! ~/.config/hypr/custom/default_apps.json; the terminal is also written to kdeglobals so Dolphin's
//! "Open Terminal" follows it.

use anyhow::{anyhow, bail, Result};
use serde_json::{json, Map, Value};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::fs;
use std::io::{self, Read as _};
use std::os::unix::process::CommandExt as _;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{mpsc, OnceLock};
use std::time::Duration;

const USAGE: &str = "usage: velora-helper apps <command>
  list [LANG]                  JSON with every role, its current app and the choices
  set ROLE DESKTOP_ID|ask      make an installed app the default, or ask every time
  set-command ROLE CMD [NAME]  use a command instead (terminal and code editor only)
  set-webmail SERVICE          web mail used when the email app is a browser
  launch ROLE                  start the default app for ROLE
  open DESKTOP_ID [URI...]     start an app by its desktop file id, optionally with files
  sync                         install the chooser and hand it every type without an app
  open-with URI...             run by the chooser: ask the shell which app opens these
  set-mime DESKTOP_ID TYPE...  remember an app for file types
  unset-mime TYPE...           ask again next time
  mailto URI                   open a mailto: link in the chosen web mail
  open-archive URI...          browse archives as folders in Dolphin";

const CHOOSER_ID: &str = "folis-open-with.desktop";
const WEBMAIL_ID: &str = "folis-webmail.desktop";
const ARCHIVE_ID: &str = "folis-dolphin-archive.desktop";
const OWN_IDS: [&str; 3] = [CHOOSER_ID, WEBMAIL_ID, ARCHIVE_ID];
// Shadowed with NoDisplay and no MimeType: the file manager is Dolphin
const HIDDEN_APPS: [&str; 1] = ["org.gnome.Nautilus.desktop"];
const GENERATED_MARK: &str = "# Written by velora-helper apps sync, changes are overwritten";
// What earlier versions marked their entries with: those are still ours to replace
const OLD_GENERATED_MARK: &str = "# Written by default_apps.py sync, changes are overwritten";

#[derive(Clone, Copy, PartialEq)]
enum Match {
    Mimes,
    Categories,
    Either,
}

struct Role {
    id: &'static str,
    mimes: &'static [&'static str],
    categories: &'static [&'static str],
    matching: Match,
    command: bool,
}

const ROLES: &[Role] = &[
    Role { id: "browser", mimes: &["x-scheme-handler/https", "x-scheme-handler/http", "text/html", "application/xhtml+xml",
        "x-scheme-handler/about", "x-scheme-handler/unknown"], categories: &["WebBrowser"], matching: Match::Mimes, command: false },
    // Browsers can open mail links through a web mail service
    Role { id: "mail", mimes: &["x-scheme-handler/mailto", "message/rfc822"], categories: &["Email", "WebBrowser"], matching: Match::Either, command: false },
    Role { id: "files", mimes: &["inode/directory"], categories: &["FileManager"], matching: Match::Categories, command: false },
    Role { id: "terminal", mimes: &[], categories: &["TerminalEmulator"], matching: Match::Categories, command: true },
    Role { id: "text", mimes: &["text/plain"], categories: &["TextEditor"], matching: Match::Mimes, command: false },
    Role { id: "code", mimes: &[], categories: &["IDE", "TextEditor"], matching: Match::Categories, command: true },
    Role { id: "images", mimes: &["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/tiff",
        "image/avif", "image/heif", "image/svg+xml", "image/x-icon"], categories: &["Viewer", "Photography", "RasterGraphics"], matching: Match::Mimes, command: false },
    Role { id: "video", mimes: &["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo",
        "video/mpeg", "video/ogg", "video/x-flv", "video/3gpp"], categories: &["Video", "Player"], matching: Match::Mimes, command: false },
    Role { id: "music", mimes: &["audio/mpeg", "audio/flac", "audio/x-flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/opus",
        "audio/wav", "audio/x-wav", "audio/mp4", "audio/aac", "audio/x-m4a", "audio/webm"], categories: &["Audio", "Music", "Player"], matching: Match::Mimes, command: false },
    Role { id: "pdf", mimes: &["application/pdf"], categories: &["Viewer", "Office"], matching: Match::Mimes, command: false },
    Role { id: "documents", mimes: &["application/vnd.oasis.opendocument.text",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/msword", "application/rtf"], categories: &["WordProcessor", "Office"], matching: Match::Mimes, command: false },
    Role { id: "spreadsheets", mimes: &["application/vnd.oasis.opendocument.spreadsheet",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-excel"], categories: &["Spreadsheet", "Office"], matching: Match::Mimes, command: false },
    Role { id: "presentations", mimes: &["application/vnd.oasis.opendocument.presentation",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "application/vnd.ms-powerpoint"], categories: &["Presentation", "Office"], matching: Match::Mimes, command: false },
    Role { id: "archives", mimes: &["application/zip", "application/x-7z-compressed", "application/vnd.rar", "application/x-rar",
        "application/x-tar", "application/gzip", "application/x-compressed-tar",
        "application/x-bzip2-compressed-tar", "application/x-xz-compressed-tar",
        "application/x-zstd-compressed-tar", "application/zstd"], categories: &["Archiving", "Compression"], matching: Match::Mimes, command: false },
];

// Archives Dolphin can browse, and the KIO protocol (kio-extras) that reads each
const ARCHIVE_PROTOCOLS: &[(&str, &str)] = &[
    ("application/zip", "zip"),
    ("application/x-7z-compressed", "sevenz"),
    ("application/x-tar", "tar"),
    ("application/x-compressed-tar", "tar"),
    ("application/x-bzip2-compressed-tar", "tar"),
    ("application/x-xz-compressed-tar", "tar"),
    ("application/x-zstd-compressed-tar", "tar"),
    ("application/x-lzma-compressed-tar", "tar"),
];

// id, name, home, compose
const WEBMAIL: &[(&str, &str, &str, &str)] = &[
    ("gmail", "Gmail", "https://mail.google.com/", "https://mail.google.com/mail/?extsrc=mailto&url={uri}"),
    ("outlook", "Outlook", "https://outlook.live.com/mail/", "https://outlook.live.com/mail/deeplink/compose?mailtouri={uri}"),
    ("yandex", "Yandex", "https://mail.yandex.ru/", "https://mail.yandex.ru/compose?mailto={uri}"),
    ("proton", "Proton Mail", "https://mail.proton.me/", "https://mail.proton.me/inbox/#mailto={uri}"),
];
const SEED_WEBMAIL: &str = "gmail";

// Apps a fresh setup starts with: the first one installed wins. Only roles still without an app.
const SEED: &[(&str, &[&str])] = &[
    ("browser", &["brave-browser.desktop", "firefox.desktop", "chromium.desktop", "org.gnome.Epiphany.desktop"]),
    ("files", &["org.kde.dolphin.desktop"]),
    ("text", &["org.kde.kate.desktop", "org.gnome.TextEditor.desktop", "org.kde.kwrite.desktop"]),
    ("images", &["org.gnome.Loupe.desktop", "org.kde.gwenview.desktop", "imv.desktop"]),
    ("video", &["org.gnome.Showtime.desktop", "mpv.desktop", "vlc.desktop", "org.kde.haruna.desktop"]),
    ("music", &["org.gnome.Decibels.desktop", "org.kde.elisa.desktop", "vlc.desktop"]),
    ("pdf", &["org.gnome.Papers.desktop", "org.kde.okular.desktop", "org.gnome.Evince.desktop"]),
    ("documents", &["libreoffice-writer.desktop"]),
    ("spreadsheets", &["libreoffice-calc.desktop"]),
    ("presentations", &["libreoffice-impress.desktop"]),
    ("archives", &[ARCHIVE_ID]),
];

fn role(id: &str) -> Option<&'static Role> {
    ROLES.iter().find(|role| role.id == id)
}

fn webmail(id: &str) -> Option<&'static (&'static str, &'static str, &'static str, &'static str)> {
    WEBMAIL.iter().find(|service| service.0 == id)
}

// Directories ---------------------------------------------------------------------------------------

fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
}

fn env_nonempty(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|value| !value.is_empty())
}

fn config_home() -> PathBuf {
    env_nonempty("XDG_CONFIG_HOME").map_or_else(|| home().join(".config"), PathBuf::from)
}

fn data_home() -> PathBuf {
    env_nonempty("XDG_DATA_HOME").map_or_else(|| home().join(".local/share"), PathBuf::from)
}

fn split_paths(value: &str) -> Vec<PathBuf> {
    value.split(':').filter(|path| !path.is_empty()).map(PathBuf::from).collect()
}

fn data_dirs() -> Vec<PathBuf> {
    split_paths(&env_nonempty("XDG_DATA_DIRS").unwrap_or_else(|| "/usr/local/share:/usr/share".to_string()))
}

fn config_dirs() -> Vec<PathBuf> {
    split_paths(&env_nonempty("XDG_CONFIG_DIRS").unwrap_or_else(|| "/etc/xdg".to_string()))
}

fn desktops() -> Vec<String> {
    env_nonempty("XDG_CURRENT_DESKTOP").unwrap_or_default().split(':').filter(|d| !d.is_empty()).map(str::to_lowercase).collect()
}

fn qs_config() -> String {
    env_nonempty("QS_CONFIG_NAME").unwrap_or_else(|| "ii".to_string())
}

fn store_path() -> PathBuf {
    config_home().join("hypr/custom/default_apps.json")
}

fn user_mimeapps() -> PathBuf {
    config_home().join("mimeapps.list")
}

fn user_apps() -> PathBuf {
    data_home().join("applications")
}

/// Through ~/.config so the entries keep working wherever the dotfiles are checked out.
fn launcher() -> PathBuf {
    config_home().join("quickshell").join(qs_config()).join("scripts/helper")
}

/// shutil.which: a path with a slash is checked as it is, anything else is looked up in PATH.
pub fn which(name: &str) -> Option<PathBuf> {
    use std::os::unix::fs::PermissionsExt as _;
    let executable = |path: &Path| fs::metadata(path).is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0);
    if name.is_empty() {
        return None;
    }
    if name.contains('/') {
        let path = PathBuf::from(name);
        return executable(&path).then_some(path);
    }
    std::env::var_os("PATH").and_then(|paths| std::env::split_paths(&paths).map(|dir| dir.join(name)).find(|path| executable(path)))
}

fn expand_user(path: &str) -> String {
    match path.strip_prefix("~/") {
        Some(rest) => home().join(rest).to_string_lossy().into_owned(),
        None if path == "~" => home().to_string_lossy().into_owned(),
        None => path.to_string(),
    }
}

// Installed apps ------------------------------------------------------------------------------------

struct App {
    id: String,
    path: PathBuf,
    name: String,
    comment: String,
    icon: String,
    exec: String,
    terminal: bool,
    mimes: HashSet<String>,
    categories: HashSet<String>,
    hidden: bool,
}

impl App {
    fn public(&self) -> Value {
        json!({ "id": self.id, "name": self.name, "comment": self.comment, "icon": self.icon })
    }

    /// Shown in lists: visible apps and our own handlers, never the chooser itself.
    fn choosable(&self) -> bool {
        self.id != CHOOSER_ID && self.id != WEBMAIL_ID && (!self.hidden || OWN_IDS.contains(&self.id.as_str()))
    }

    fn is_browser(&self) -> bool {
        self.categories.contains("WebBrowser")
    }

    fn sort_name(&self) -> String {
        self.name.to_lowercase()
    }
}

struct Apps {
    list: Vec<App>,
    index: HashMap<String, usize>,
}

impl Apps {
    fn get(&self, id: &str) -> Option<&App> {
        self.index.get(id).map(|&position| &self.list[position])
    }

    fn contains(&self, id: &str) -> bool {
        self.index.contains_key(id)
    }
}

fn localized(entry: &HashMap<String, String>, key: &str) -> String {
    let lang = env_nonempty("LC_MESSAGES").or_else(|| env_nonempty("LANG")).unwrap_or_default();
    let lang = lang.split('.').next().unwrap_or_default();
    let short = lang.split('_').next().unwrap_or_default();
    [format!("{key}[{lang}]"), format!("{key}[{short}]"), key.to_string()]
        .iter()
        .find_map(|candidate| entry.get(candidate).filter(|value| !value.is_empty()).cloned())
        .unwrap_or_default()
}

fn parse_desktop_file(path: &Path) -> Option<HashMap<String, String>> {
    let bytes = fs::read(path).ok()?;
    let mut entry = HashMap::new();
    let mut in_main = false;
    for line in String::from_utf8_lossy(&bytes).lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_main = line == "[Desktop Entry]";
        } else if in_main && !line.starts_with('#') {
            if let Some((key, value)) = line.split_once('=') {
                entry.insert(key.trim().to_string(), value.trim().to_string());
            }
        }
    }
    Some(entry)
}

fn split_list(value: &str) -> impl Iterator<Item = &str> {
    value.split(';').filter(|item| !item.is_empty())
}

fn desktop_files(directory: &Path, found: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(directory) else { return };
    for entry in entries.filter_map(Result::ok) {
        let path = entry.path();
        if entry.file_type().is_ok_and(|kind| kind.is_dir()) {
            desktop_files(&path, found);
        } else if path.extension().is_some_and(|extension| extension == "desktop") {
            found.push(path);
        }
    }
}

/// Earlier directories win, like everywhere else.
fn installed_apps() -> Apps {
    let mut apps = Apps { list: Vec::new(), index: HashMap::new() };
    let mut seen = HashSet::new();
    for base in std::iter::once(data_home()).chain(data_dirs()) {
        let root = base.join("applications");
        let mut paths = Vec::new();
        desktop_files(&root, &mut paths);
        paths.sort();
        for path in paths {
            let id = path.strip_prefix(&root).unwrap_or(&path).to_string_lossy().replace('/', "-");
            if seen.contains(&id) {
                continue;
            }
            let Some(entry) = parse_desktop_file(&path) else { continue };
            seen.insert(id.clone()); // Shadowed entries further down must stay hidden
            let get = |key: &str| entry.get(key).map_or("", String::as_str);
            if entry.get("Type").is_some_and(|kind| kind != "Application") || get("Hidden") == "true" {
                continue;
            }
            let try_exec = get("TryExec");
            if !try_exec.is_empty() {
                let expanded = expand_user(try_exec);
                if which(&expanded).is_none() && !Path::new(&expanded).is_file() {
                    continue;
                }
            }
            let name = localized(&entry, "Name");
            let generic = localized(&entry, "GenericName");
            let app = App {
                name: if name.is_empty() { id.strip_suffix(".desktop").unwrap_or(&id).to_string() } else { name },
                comment: if generic.is_empty() { localized(&entry, "Comment") } else { generic },
                icon: get("Icon").to_string(),
                exec: get("Exec").to_string(),
                terminal: get("Terminal") == "true",
                mimes: split_list(get("MimeType")).map(str::to_string).collect(),
                categories: split_list(get("Categories")).map(str::to_string).collect(),
                hidden: get("NoDisplay") == "true",
                path,
                id: id.clone(),
            };
            apps.index.insert(id, apps.list.len());
            apps.list.push(app);
        }
    }
    apps
}

// Running tools -------------------------------------------------------------------------------------

/// What a tool printed, or None if it couldn't run or didn't finish in time.
pub fn capture(program: &str, arguments: &[&str], timeout: Duration) -> Option<(bool, String)> {
    let mut child = Command::new(program).args(arguments).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok()?;
    let mut stdout = child.stdout.take()?;
    let (sender, receiver) = mpsc::channel();
    std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stdout.read_to_end(&mut bytes);
        let _ = sender.send(bytes);
    });
    let Ok(bytes) = receiver.recv_timeout(timeout) else {
        let _ = child.kill();
        let _ = child.wait();
        return None;
    };
    let success = child.wait().is_ok_and(|status| status.success());
    Some((success, String::from_utf8_lossy(&bytes).into_owned()))
}

/// A process of its own that outlives this one.
fn spawn(command: &mut Command) {
    command.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).current_dir(home());
    // SAFETY: setsid is async-signal-safe and touches no memory of this process.
    unsafe {
        command.pre_exec(|| {
            if libc::setsid() < 0 {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        });
    }
    if let Err(error) = command.spawn() {
        eprintln!("velora-helper apps: can't start {:?}: {error}", command.get_program());
    }
}

fn notify(title: &str, body: &str) {
    let _ = Command::new("notify-send").args(["-a", "Default apps", title, body]).status();
}

// URIs ----------------------------------------------------------------------------------------------

fn url_scheme(uri: &str) -> String {
    let Some(position) = uri.find(':') else { return String::new() };
    let scheme = &uri[..position];
    let valid = scheme.chars().next().is_some_and(|c| c.is_ascii_alphabetic())
        && scheme.chars().all(|c| c.is_ascii_alphanumeric() || "+-.".contains(c));
    if valid { scheme.to_ascii_lowercase() } else { String::new() }
}

fn unquote(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut position = 0;
    while position < bytes.len() {
        let hex = (bytes[position] == b'%').then(|| bytes.get(position + 1..position + 3)).flatten()
            .and_then(|pair| std::str::from_utf8(pair).ok()).and_then(|pair| u8::from_str_radix(pair, 16).ok());
        if let Some(value) = hex {
            decoded.push(value);
            position += 3;
        } else {
            decoded.push(bytes[position]);
            position += 1;
        }
    }
    String::from_utf8_lossy(&decoded).into_owned()
}

fn quote(text: &str, safe: &str) -> String {
    let mut quoted = String::with_capacity(text.len());
    for byte in text.bytes() {
        if byte.is_ascii_alphanumeric() || b"_.-~".contains(&byte) || safe.as_bytes().contains(&byte) {
            quoted.push(byte as char);
        } else {
            quoted.push_str(&format!("%{byte:02X}"));
        }
    }
    quoted
}

fn to_path(uri: &str) -> String {
    if url_scheme(uri) != "file" {
        return uri.to_string();
    }
    let mut rest = &uri[5..];
    if let Some(after) = rest.strip_prefix("//") {
        rest = after.find(['/', '?', '#']).map_or("", |position| &after[position..]);
    }
    let rest = rest.split('#').next().unwrap_or_default();
    unquote(rest.split('?').next().unwrap_or_default())
}

/// shlex.split: None for unbalanced quotes.
fn shell_split(text: &str) -> Option<Vec<String>> {
    let mut parts = Vec::new();
    let mut current: Option<String> = None;
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        match c {
            ' ' | '\t' | '\r' | '\n' => parts.extend(current.take()),
            '\'' => {
                let word = current.get_or_insert_with(String::new);
                loop {
                    match chars.next()? {
                        '\'' => break,
                        other => word.push(other),
                    }
                }
            }
            '"' => {
                let word = current.get_or_insert_with(String::new);
                loop {
                    match chars.next()? {
                        '"' => break,
                        '\\' => match chars.next()? {
                            escaped @ ('"' | '\\') => word.push(escaped),
                            other => {
                                word.push('\\');
                                word.push(other);
                            }
                        },
                        other => word.push(other),
                    }
                }
            }
            '\\' => current.get_or_insert_with(String::new).push(chars.next()?),
            other => current.get_or_insert_with(String::new).push(other),
        }
    }
    parts.extend(current);
    Some(parts)
}

// MIME database -------------------------------------------------------------------------------------

fn mime_dirs() -> Vec<PathBuf> {
    std::iter::once(data_home()).chain(data_dirs()).map(|base| base.join("mime")).filter(|dir| dir.is_dir()).collect()
}

fn read_pairs(name: &str) -> Vec<(String, String)> {
    let mut pairs = Vec::new();
    for directory in mime_dirs() {
        let Ok(text) = fs::read_to_string(directory.join(name)) else { continue };
        for line in text.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if let [first, second] = parts[..] {
                pairs.push((first.to_string(), second.to_string()));
            }
        }
    }
    pairs
}

fn aliases() -> &'static HashMap<String, String> {
    static ALIASES: OnceLock<HashMap<String, String>> = OnceLock::new();
    ALIASES.get_or_init(|| read_pairs("aliases").into_iter().collect())
}

fn parents() -> &'static HashMap<String, Vec<String>> {
    static PARENTS: OnceLock<HashMap<String, Vec<String>>> = OnceLock::new();
    PARENTS.get_or_init(|| {
        let mut parents: HashMap<String, Vec<String>> = HashMap::new();
        for (child, parent) in read_pairs("subclasses") {
            parents.entry(child).or_default().push(parent);
        }
        parents
    })
}

fn canonical(mime: &str) -> String {
    aliases().get(mime).map_or_else(|| mime.to_string(), Clone::clone)
}

/// The type, its aliases and every type it is a kind of (text/markdown -> text/plain), nearest first.
fn ancestors(mime: &str) -> Vec<String> {
    let mut order = vec![canonical(mime)];
    let mut position = 0;
    while position < order.len() {
        let current = order[position].clone();
        position += 1;
        let mut next = parents().get(&current).cloned().unwrap_or_default();
        if current.starts_with("text/") && current != "text/plain" {
            next.push("text/plain".to_string());
        }
        for parent in next {
            let parent = canonical(&parent);
            if !order.contains(&parent) {
                order.push(parent);
            }
        }
    }
    let mut result = Vec::new();
    for item in order {
        let mut names: Vec<&String> = aliases().iter().filter(|(_, target)| **target == item).map(|(alias, _)| alias).collect();
        names.sort();
        let names: Vec<String> = names.into_iter().cloned().collect();
        result.push(item);
        result.extend(names);
    }
    result
}

fn all_types() -> Vec<String> {
    let mut types = BTreeSet::new();
    for directory in mime_dirs() {
        if let Ok(text) = fs::read_to_string(directory.join("types")) {
            types.extend(text.lines().map(|line| line.trim().to_string()));
        }
    }
    // Removable media and special files aren't opened by double-clicking
    types.into_iter().filter(|t| !t.is_empty() && !t.starts_with("inode/") && !t.starts_with("x-content/") && !t.starts_with("all/")).collect()
}

/// The description and patterns from the shared MIME database, in the UI language when it has one.
fn mime_info(mime: &str, lang: &str) -> (String, Vec<String>) {
    const NAMESPACE: &str = "http://www.freedesktop.org/standards/shared-mime-info";
    const XML: &str = "http://www.w3.org/XML/1998/namespace";
    let wanted = if lang.is_empty() { Vec::new() } else { vec![lang.replace('_', "-"), lang.split('_').next().unwrap_or_default().to_string()] };
    for directory in mime_dirs() {
        let Ok(text) = fs::read_to_string(directory.join(format!("{}.xml", canonical(mime)))) else { continue };
        let Ok(document) = roxmltree::Document::parse(&text) else { continue };
        let mut comments = HashMap::new();
        let mut patterns = Vec::new();
        for node in document.root_element().children() {
            if node.has_tag_name((NAMESPACE, "comment")) {
                comments.insert(node.attribute((XML, "lang")).unwrap_or_default().to_string(), node.text().unwrap_or_default().to_string());
            } else if node.has_tag_name((NAMESPACE, "glob")) {
                patterns.extend(node.attribute("pattern").filter(|p| !p.is_empty()).map(str::to_string));
            }
        }
        let description = wanted.iter().find_map(|language| comments.get(language)).or_else(|| comments.get("")).cloned().unwrap_or_default();
        return (description, patterns);
    }
    (String::new(), Vec::new())
}

/// MIME types of a file: shared-mime-info's first, then file(1)'s when it differs (xdg-open uses that).
fn file_types(uri: &str) -> Vec<String> {
    let scheme = url_scheme(uri);
    if scheme.len() > 1 && scheme != "file" {
        return vec![format!("x-scheme-handler/{scheme}")];
    }
    let path = to_path(uri);
    let mut types = Vec::new();
    let timeout = Duration::from_secs(5);
    if let Some((_, output)) = capture("gio", &["info", "-a", "standard::content-type", &path], timeout) {
        for line in output.lines().filter(|line| line.contains("standard::content-type:")) {
            types.extend(line.splitn(4, ':').last().map(|value| value.trim().to_string()));
        }
    }
    if let Some((_, output)) = capture("xdg-mime", &["query", "filetype", &path], timeout) {
        let other = output.trim().split(';').next().unwrap_or_default().to_string();
        if !other.is_empty() && !types.contains(&other) {
            types.push(other);
        }
    }
    if types.is_empty() {
        types.push("application/octet-stream".to_string());
    }
    types
}

// mimeapps.list -------------------------------------------------------------------------------------

fn mimeapps_files() -> Vec<PathBuf> {
    let desktops = desktops();
    let mut files = Vec::new();
    for directory in std::iter::once(config_home()).chain(config_dirs()) {
        files.extend(desktops.iter().map(|desktop| directory.join(format!("{desktop}-mimeapps.list"))));
        files.push(directory.join("mimeapps.list"));
    }
    for directory in std::iter::once(data_home()).chain(data_dirs()) {
        let applications = directory.join("applications");
        files.extend(desktops.iter().map(|desktop| applications.join(format!("{desktop}-mimeapps.list"))));
        files.push(applications.join("mimeapps.list"));
        files.push(applications.join("defaults.list"));
    }
    files
}

type Sections = Vec<(String, Vec<String>)>;

/// Sections as ordered lists of raw lines, so rewriting keeps everything else intact. A file that isn't
/// valid text is an error rather than an empty file: writing would lose what's in it.
fn read_ini(path: &Path) -> Result<Sections> {
    let mut sections: Sections = vec![(String::new(), Vec::new())];
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(error) if error.kind() == io::ErrorKind::InvalidData => bail!("{} isn't valid UTF-8", path.display()),
        Err(_) => return Ok(sections),
    };
    for line in text.lines() {
        let stripped = line.trim();
        if stripped.starts_with('[') && stripped.ends_with(']') && stripped.len() >= 2 {
            sections.push((stripped[1..stripped.len() - 1].to_string(), Vec::new()));
        } else if let Some(last) = sections.last_mut() {
            last.1.push(line.to_string());
        }
    }
    Ok(sections)
}

fn key_of(line: &str) -> Option<(&str, &str)> {
    line.split_once('=').map(|(key, value)| (key.trim(), value))
}

fn ini_get(sections: &Sections, section: &str, wanted: &str) -> Option<String> {
    sections.iter().filter(|(name, _)| name == section).flat_map(|(_, lines)| lines)
        .find_map(|line| key_of(line).filter(|(key, _)| *key == wanted).map(|(_, value)| value.trim().to_string()))
}

/// Keys in file order; a repeated key keeps its place and takes the last value.
fn ini_keys(sections: &Sections, section: &str) -> Vec<(String, String)> {
    let mut keys: Vec<(String, String)> = Vec::new();
    let mut positions = HashMap::new();
    for line in sections.iter().filter(|(name, _)| name == section).flat_map(|(_, lines)| lines) {
        if line.trim_start().starts_with('#') {
            continue;
        }
        if let Some((key, value)) = key_of(line) {
            let value = value.trim().to_string();
            match positions.get(key) {
                Some(&position) => {
                    let entry: &mut (String, String) = &mut keys[position];
                    entry.1 = value;
                }
                None => {
                    positions.insert(key.to_string(), keys.len());
                    keys.push((key.to_string(), value));
                }
            }
        }
    }
    keys
}

fn default_for_mime(mime: &str, apps: &Apps) -> Result<Option<String>> {
    for path in mimeapps_files() {
        if !path.is_file() {
            continue;
        }
        if let Some(value) = ini_get(&read_ini(&path)?, "Default Applications", mime) {
            if let Some(id) = split_list(&value).find(|id| apps.contains(id)) {
                return Ok(Some(id.to_string()));
            }
        }
    }
    // Nothing explicit: ask xdg-mime, which also knows the MIME cache order
    let answer = capture("xdg-mime", &["query", "default", mime], Duration::from_secs(5));
    Ok(answer.map(|(_, output)| output.trim().to_string()).filter(|id| apps.contains(id)))
}

/// Pairs without repeated types; the last app given for a type wins.
fn pairs(mimes: impl IntoIterator<Item = String>, app: &str) -> Vec<(String, String)> {
    let mut seen = HashSet::new();
    mimes.into_iter().filter(|mime| seen.insert(mime.clone())).map(|mime| (mime, app.to_string())).collect()
}

/// Set [Default Applications] mime=app for each pair; with `associate` also put the app first in
/// [Added Associations], so it shows up for the type even if its desktop file doesn't list it.
fn update_mimeapps(path: &Path, defaults: &[(String, String)], associate: bool) -> Result<()> {
    let mut sections = read_ini(path)?;
    let wanted: &[&str] = if associate { &["Default Applications", "Added Associations"] } else { &["Default Applications"] };
    for section in wanted {
        if !sections.iter().any(|(name, _)| name == section) {
            sections.push((section.to_string(), Vec::new()));
        }
    }
    let mut changed = false;
    for (name, lines) in &mut sections {
        if !wanted.contains(&name.as_str()) {
            continue;
        }
        let mut existing = HashMap::new();
        for (position, line) in lines.iter().enumerate() {
            if let Some((key, _)) = key_of(line) {
                existing.insert(key.to_string(), position);
            }
        }
        let mut additions = Vec::new();
        for (mime, app) in defaults {
            let value = if name == "Default Applications" {
                format!("{mime}={app}")
            } else {
                let old = existing.get(mime).and_then(|&position| key_of(&lines[position])).map_or("", |(_, value)| value);
                let mut apps = vec![app.as_str()];
                apps.extend(split_list(old).filter(|item| item != app));
                format!("{mime}={};", apps.join(";"))
            };
            match existing.get(mime) {
                Some(&position) => {
                    if lines[position] != value {
                        lines[position] = value;
                        changed = true;
                    }
                }
                None => additions.push(value),
            }
        }
        if !additions.is_empty() {
            // Keep new keys above trailing blank lines
            let mut position = lines.len();
            while position > 0 && lines[position - 1].trim().is_empty() {
                position -= 1;
            }
            lines.splice(position..position, additions);
            changed = true;
        }
    }
    if !changed {
        return Ok(());
    }
    let mut out: Vec<String> = Vec::new();
    for (name, lines) in sections {
        if !name.is_empty() {
            if out.last().is_some_and(|line| !line.trim().is_empty()) {
                out.push(String::new());
            }
            out.push(format!("[{name}]"));
        }
        out.extend(lines);
    }
    write_text(path, &format!("{}\n", out.join("\n").trim_matches('\n')))
}

fn write_text(path: &Path, text: &str) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut temporary = path.as_os_str().to_owned();
    temporary.push(".tmp");
    fs::write(&temporary, text)?;
    fs::rename(&temporary, path)?;
    Ok(())
}

fn set_mime_defaults(defaults: &[(String, String)], associate: bool) -> Result<()> {
    update_mimeapps(&user_mimeapps(), defaults, associate)?;
    for desktop in desktops() {
        let path = config_home().join(format!("{desktop}-mimeapps.list"));
        if path.is_file() {
            update_mimeapps(&path, defaults, associate)?;
        }
    }
    Ok(())
}

// Store -----------------------------------------------------------------------------------------------

fn read_store() -> Map<String, Value> {
    fs::read_to_string(store_path()).ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_default()
}

fn write_store(store: &Map<String, Value>) -> Result<()> {
    use serde::Serialize as _;
    let mut bytes = Vec::new();
    let mut serializer = serde_json::Serializer::with_formatter(&mut bytes, serde_json::ser::PrettyFormatter::with_indent(b"    "));
    store.serialize(&mut serializer)?;
    write_text(&store_path(), &format!("{}\n", String::from_utf8(bytes)?))
}

fn truthy(value: Option<&Value>) -> bool {
    value.and_then(Value::as_str).is_some_and(|text| !text.is_empty())
}

fn kde_terminal() -> (Option<String>, Option<String>) {
    if which("kreadconfig6").is_none() {
        return (None, None);
    }
    let read = |key: &str| {
        let output = Command::new("kreadconfig6").args(["--file", "kdeglobals", "--group", "General", "--key", key]).stderr(Stdio::null()).output().ok()?;
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string()).filter(|value| !value.is_empty())
    };
    (read("TerminalService"), read("TerminalApplication"))
}

// Roles -----------------------------------------------------------------------------------------------

fn supports(app: &App, mime: &str) -> bool {
    ancestors(mime).iter().any(|item| app.mimes.contains(item))
}

fn candidates_for<'a>(role: &Role, apps: &'a Apps) -> Vec<&'a App> {
    let matches = |app: &App| {
        let by_mime = role.mimes.iter().any(|mime| app.mimes.contains(*mime));
        let by_category = role.categories.iter().any(|category| app.categories.contains(*category));
        match role.matching {
            Match::Mimes => by_mime,
            Match::Categories => by_category,
            Match::Either => by_mime || by_category,
        }
    };
    let mut found: Vec<&App> = apps.list.iter().filter(|app| app.choosable() && matches(app)).collect();
    // Apps made for the job first (categories are listed by importance), then the ones
    // that open the most of the role's file types, then by name
    found.sort_by_cached_key(|app| {
        let category = role.categories.iter().position(|category| app.categories.contains(*category)).unwrap_or(role.categories.len());
        let opened = role.mimes.iter().filter(|mime| app.mimes.contains(**mime)).count();
        (category, std::cmp::Reverse(opened), app.sort_name())
    });
    found
}

/// {"app": id} or {"command": cmd, "name": ...} or {"ask": true} or {}
fn current_for(role: &Role, apps: &Apps) -> Result<Map<String, Value>> {
    let object = |value: Value| value.as_object().cloned().unwrap_or_default();
    if let Some(first) = role.mimes.first() {
        return Ok(match default_for_mime(first, apps)?.as_deref() {
            Some(CHOOSER_ID) => object(json!({ "ask": true })),
            Some(WEBMAIL_ID) => {
                let store = read_store();
                let mail = store.get("mail").cloned().unwrap_or(Value::Null);
                match mail["browser"].as_str().filter(|browser| apps.contains(browser)) {
                    Some(browser) => {
                        let service = mail["webmail"].as_str().filter(|service| !service.is_empty()).unwrap_or(SEED_WEBMAIL);
                        object(json!({ "app": browser, "webmail": service }))
                    }
                    None => Map::new(),
                }
            }
            Some(id) => object(json!({ "app": id })),
            None => Map::new(),
        });
    }
    let stored = read_store().get(role.id).and_then(Value::as_object).cloned().unwrap_or_default();
    if stored.get("app").and_then(Value::as_str).is_some_and(|app| apps.contains(app)) || truthy(stored.get("command")) {
        return Ok(stored);
    }
    if role.id == "terminal" {
        let (service, command) = kde_terminal();
        if let Some(service) = service.filter(|service| apps.contains(service)) {
            return Ok(object(json!({ "app": service })));
        }
        if let Some(command) = command {
            return Ok(object(json!({ "command": command })));
        }
    }
    Ok(candidates_for(role, apps).first().map_or_else(Map::new, |app| object(json!({ "app": app.id }))))
}

/// File types the user picked an app for that aren't part of a role.
fn remembered_types(apps: &Apps, lang: &str) -> Result<Vec<Value>> {
    let mut types = Vec::new();
    for (mime, value) in ini_keys(&read_ini(&user_mimeapps())?, "Default Applications") {
        if ROLES.iter().any(|role| role.mimes.contains(&mime.as_str())) || mime.starts_with("x-scheme-handler/") || mime.starts_with("inode/") {
            continue;
        }
        let Some(app) = split_list(&value).find_map(|id| apps.get(id)).filter(|app| app.id != CHOOSER_ID) else { continue };
        let (description, patterns) = mime_info(&mime, lang);
        let description = if description.is_empty() { mime.clone() } else { description };
        let patterns: Vec<String> = patterns.into_iter().take(3).collect();
        types.push((description.to_lowercase(), json!({ "mime": mime, "description": description, "patterns": patterns, "app": app.public() })));
    }
    types.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(types.into_iter().map(|(_, entry)| entry).collect())
}

fn cmd_list(lang: &str) -> Result<()> {
    let apps = installed_apps();
    let mut roles = Vec::new();
    for role in ROLES {
        let mut current = current_for(role, &apps)?;
        let mut candidates = candidates_for(role, &apps);
        let chosen = current.get("app").and_then(Value::as_str).and_then(|id| apps.get(id));
        if let Some(app) = chosen {
            if !candidates.iter().any(|candidate| candidate.id == app.id) {
                candidates.insert(0, app);
            }
            current.insert("app".to_string(), app.public());
        }
        roles.push(json!({
            "id": role.id,
            "current": current,
            "candidates": candidates.iter().map(|app| app.public()).collect::<Vec<_>>(),
            "allowsCommand": role.command,
            "allowsAsk": !role.mimes.is_empty() && role.id != "browser" && role.id != "files",
        }));
    }
    let mut listed: Vec<&App> = apps.list.iter().filter(|app| app.choosable() && !OWN_IDS.contains(&app.id.as_str())).collect();
    listed.sort_by_cached_key(|app| app.sort_name());
    println!("{}", json!({
        "roles": roles,
        "apps": listed.iter().map(|app| app.public()).collect::<Vec<_>>(),
        "webmail": WEBMAIL.iter().map(|service| json!({ "id": service.0, "name": service.1 })).collect::<Vec<_>>(),
        "types": remembered_types(&apps, lang)?,
    }));
    Ok(())
}

fn set_kde_terminal(service: Option<&str>, command: &str) {
    if which("kwriteconfig6").is_none() {
        return;
    }
    let write = |key: &str, value: &str| {
        let _ = Command::new("kwriteconfig6").args(["--file", "kdeglobals", "--group", "General", "--key", key, value]).status();
    };
    write("TerminalApplication", command);
    write("TerminalService", service.unwrap_or("--delete"));
}

fn exec_program(app: &App) -> String {
    match shell_split(&app.exec) {
        Some(parts) => parts.into_iter().next().unwrap_or_default(),
        None => app.exec.split(' ').next().unwrap_or_default().to_string(),
    }
}

fn set_role_app(role: &Role, id: &str, apps: &Apps) -> Result<()> {
    let all = || role.mimes.iter().map(|mime| mime.to_string());
    if !role.mimes.is_empty() {
        if id == "ask" {
            return set_mime_defaults(&pairs(all(), CHOOSER_ID), false);
        }
        let app = apps.get(id).ok_or_else(|| anyhow!("No such app: {id}"))?;
        if role.id == "mail" && app.is_browser() && !role.mimes.iter().any(|mime| app.mimes.contains(*mime)) {
            let mut store = read_store();
            let service = store.get("mail").and_then(|mail| mail["webmail"].as_str()).filter(|service| !service.is_empty()).unwrap_or(SEED_WEBMAIL).to_string();
            store.insert("mail".to_string(), json!({ "browser": id, "webmail": service }));
            write_store(&store)?;
            write_own_entries()?;
            return set_mime_defaults(&pairs(["x-scheme-handler/mailto".to_string()], WEBMAIL_ID), true);
        }
        // Only the types the app can open; all of them when it doesn't say (picked from all apps)
        let mut mimes: Vec<String> = all().filter(|mime| supports(app, mime)).collect();
        if mimes.is_empty() {
            mimes = all().collect();
        }
        return set_mime_defaults(&pairs(mimes, id), true);
    }
    let mut store = read_store();
    store.insert(role.id.to_string(), json!({ "app": id }));
    write_store(&store)?;
    if role.id == "terminal" {
        let app = apps.get(id).ok_or_else(|| anyhow!("No such app: {id}"))?;
        set_kde_terminal(Some(id), &exec_program(app));
    }
    Ok(())
}

fn cmd_set(role_id: &str, id: &str) -> Result<()> {
    let apps = installed_apps();
    match role(role_id) {
        Some(role) if id == "ask" || apps.contains(id) => set_role_app(role, id, &apps),
        _ => bail!("Unknown role or app: {role_id} {id}"),
    }
}

fn cmd_set_command(role_id: &str, command: &str, name: &str) -> Result<()> {
    if !role(role_id).is_some_and(|role| role.command) || command.trim().is_empty() {
        bail!("{role_id} can't use a command");
    }
    let mut store = read_store();
    let mut entry = json!({ "command": command.trim() });
    if !name.is_empty() {
        entry["name"] = json!(name);
    }
    store.insert(role_id.to_string(), entry);
    write_store(&store)?;
    if role_id == "terminal" {
        set_kde_terminal(None, command.trim());
    }
    Ok(())
}

fn cmd_set_webmail(service: &str) -> Result<()> {
    if webmail(service).is_none() {
        bail!("Unknown web mail service: {service}");
    }
    let mut store = read_store();
    let mut mail = store.get("mail").and_then(Value::as_object).cloned().unwrap_or_default();
    mail.insert("webmail".to_string(), json!(service));
    store.insert("mail".to_string(), Value::Object(mail));
    write_store(&store)
}

// Launching -------------------------------------------------------------------------------------------

/// Command lines for the app's Exec with field codes filled in; one per file for %f/%u apps.
fn expand_exec(app: &App, uris: &[String]) -> Vec<Vec<String>> {
    let parts = shell_split(&app.exec).unwrap_or_else(|| app.exec.split_whitespace().map(str::to_string).collect());
    let has = |code: &str| parts.iter().any(|part| part.contains(code));
    let any_code = ["%f", "%F", "%u", "%U"].iter().any(|code| has(code));
    let single = (has("%f") || has("%u")) && !has("%F") && !has("%U");
    let groups: Vec<&[String]> = if single && uris.len() > 1 { uris.chunks(1).collect() } else { vec![uris] };
    let mut commands = Vec::new();
    for group in groups {
        let mut command = Vec::new();
        for part in &parts {
            match part.as_str() {
                "%F" => {
                    command.extend(group.iter().map(|uri| to_path(uri)));
                    continue;
                }
                "%U" => {
                    command.extend(group.iter().cloned());
                    continue;
                }
                "%i" => {
                    if !app.icon.is_empty() {
                        command.extend(["--icon".to_string(), app.icon.clone()]);
                    }
                    continue;
                }
                _ => {}
            }
            let first = group.first();
            let mut part = part.replace("%f", &first.map_or_else(String::new, |uri| to_path(uri)))
                .replace("%u", first.map_or("", String::as_str))
                .replace("%c", &app.name)
                .replace("%k", &app.path.to_string_lossy());
            for code in ["%d", "%D", "%n", "%N", "%v", "%m"] {
                part = part.replace(code, "");
            }
            let part = part.replace("%%", "%");
            if !part.is_empty() {
                command.push(part);
            }
        }
        if !any_code {
            command.extend(group.iter().cloned());
        }
        commands.push(command);
    }
    commands
}

fn open_app(id: &str, uris: &[String], apps: &Apps) -> Result<()> {
    let Some(app) = apps.get(id).or_else(|| apps.get(&format!("{id}.desktop"))) else { bail!("No such app: {id}") };
    let local = uris.iter().all(|uri| matches!(url_scheme(uri).as_str(), "" | "file"));
    if (local || app.terminal) && which("gio").is_some() {
        // gio also handles terminal apps, D-Bus activation and startup notification
        spawn(Command::new("gio").arg("launch").arg(&app.path).args(uris.iter().map(|uri| to_path(uri))));
        return Ok(());
    }
    for command in expand_exec(app, uris) {
        if let Some((program, arguments)) = command.split_first() {
            spawn(Command::new(program).args(arguments));
        }
    }
    Ok(())
}

fn cmd_launch(role_id: &str) -> Result<()> {
    let role = role(role_id).ok_or_else(|| anyhow!("Unknown role: {role_id}"))?;
    let apps = installed_apps();
    let current = current_for(role, &apps)?;
    let app = current.get("app").and_then(Value::as_str).unwrap_or_default();
    if let Some(command) = current.get("command").and_then(Value::as_str).filter(|command| !command.is_empty()) {
        spawn(Command::new("/bin/sh").args(["-c", command]));
    } else if let Some(service) = current.get("webmail").and_then(Value::as_str).filter(|service| !service.is_empty()) {
        let home = webmail(service).ok_or_else(|| anyhow!("Unknown web mail service: {service}"))?.2;
        open_app(app, &[home.to_string()], &apps)?;
    } else if !app.is_empty() {
        open_app(app, &[], &apps)?;
    } else {
        notify("No default app", &format!("Pick one for “{role_id}” in Settings > Default Apps"));
    }
    Ok(())
}

fn cmd_mailto(uri: &str) -> Result<()> {
    let apps = installed_apps();
    let store = read_store();
    let mail = store.get("mail").cloned().unwrap_or(Value::Null);
    let browser = match mail["browser"].as_str().filter(|browser| apps.contains(browser)) {
        Some(browser) => Some(browser.to_string()),
        None => default_for_mime("x-scheme-handler/https", &apps)?,
    };
    let service = mail["webmail"].as_str().and_then(webmail).or_else(|| webmail(SEED_WEBMAIL)).ok_or_else(|| anyhow!("no web mail service"))?;
    let url = if uri.starts_with("mailto:") { service.3.replace("{uri}", &quote(uri, "")) } else { service.2.to_string() };
    match browser {
        Some(browser) => open_app(&browser, &[url], &apps),
        None => {
            spawn(Command::new("xdg-open").arg(url));
            Ok(())
        }
    }
}

fn cmd_open_archive(uris: &[String]) {
    for uri in uris {
        let path = to_path(uri);
        let protocol = file_types(uri).iter().find_map(|mime| ARCHIVE_PROTOCOLS.iter().find(|(known, _)| known == mime)).map(|(_, protocol)| *protocol);
        let target = match protocol {
            Some(protocol) => format!("{protocol}:{}/", quote(&path, "/")),
            None => match Path::new(&path).parent() {
                Some(parent) if !parent.as_os_str().is_empty() => parent.to_string_lossy().into_owned(),
                _ => ".".to_string(),
            },
        };
        spawn(Command::new("dolphin").arg(target));
    }
}

// The chooser -------------------------------------------------------------------------------------------

/// What the chooser shows for files that share their first type.
fn describe(uris: &[String], apps: &Apps, lang: &str) -> Value {
    let mut types: Vec<String> = Vec::new();
    for uri in uris {
        for mime in file_types(uri) {
            if !types.contains(&mime) {
                types.push(mime);
            }
        }
    }
    let primary = types[0].clone();
    let mut lineage: Vec<String> = Vec::new();
    for mime in &types {
        for item in ancestors(mime) {
            if !lineage.contains(&item) {
                lineage.push(item);
            }
        }
    }
    let closeness = |app: &App| lineage.iter().position(|mime| app.mimes.contains(mime)).unwrap_or(lineage.len());
    let mut recommended: Vec<&App> = apps.list.iter().filter(|app| app.choosable() && lineage.iter().any(|mime| app.mimes.contains(mime))).collect();
    // Apps that open everything (application/octet-stream) come last
    recommended.sort_by_cached_key(|app| (closeness(app), app.sort_name()));
    let mut others: Vec<&App> = apps.list.iter().filter(|app| {
        app.choosable() && !OWN_IDS.contains(&app.id.as_str()) && !recommended.iter().any(|chosen| chosen.id == app.id)
    }).collect();
    others.sort_by_cached_key(|app| app.sort_name());
    let (description, _) = mime_info(&primary, lang);
    let path = to_path(&uris[0]);
    let file_name = Path::new(&path).file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
    let name = if file_name.is_empty() { uris[0].clone() } else { file_name };
    let suffix = name.trim_start_matches('.').rfind('.').map_or(String::new(), |position| name.trim_start_matches('.')[position..].to_string());
    json!({
        "uris": uris,
        "name": if uris.len() == 1 { name } else { format!("{name} (+{})", uris.len() - 1) },
        "extension": if suffix.chars().count() <= 12 { suffix.to_lowercase() } else { String::new() },
        "types": types,
        "description": if description.is_empty() { primary } else { description },
        "recommended": recommended.iter().map(|app| app.public()).collect::<Vec<_>>(),
        "others": others.iter().map(|app| app.public()).collect::<Vec<_>>(),
    })
}

fn shell_language() -> String {
    let config = fs::read_to_string(config_home().join("illogical-impulse/config.json")).ok().and_then(|text| serde_json::from_str::<Value>(&text).ok());
    if let Some(language) = config.as_ref().and_then(|config| config.pointer("/language/ui")).and_then(Value::as_str) {
        if !language.is_empty() && language != "auto" {
            return language.to_string();
        }
    }
    env_nonempty("LANG").unwrap_or_default().split('.').next().unwrap_or_default().to_string()
}

fn cmd_open_with(uris: &[String]) -> Result<()> {
    let apps = installed_apps();
    let lang = shell_language();
    // Files of one type go together, like the file manager handed them over
    let mut groups: Vec<(String, Vec<String>)> = Vec::new();
    for uri in uris {
        let first = file_types(uri).swap_remove(0);
        match groups.iter_mut().find(|(mime, _)| *mime == first) {
            Some((_, group)) => group.push(uri.clone()),
            None => groups.push((first, vec![uri.clone()])),
        }
    }
    for (_, group) in groups {
        let request = describe(&group, &apps, &lang);
        let recommended = request["recommended"].as_array().cloned().unwrap_or_default();
        let best = recommended.first().and_then(|app| app["id"].as_str());
        if recommended.len() == 1 {
            open_app(best.unwrap_or_default(), &group, &apps)?;
            continue;
        }
        let asked = capture("qs", &["-c", &qs_config(), "ipc", "call", "openWith", "ask", &request.to_string()], Duration::from_secs(5));
        if asked.is_some_and(|(success, _)| success) {
            continue;
        }
        // The shell isn't running: open with the best match instead of doing nothing
        match best {
            Some(best) => open_app(best, &group, &apps)?,
            None => notify("No app can open this file", request["name"].as_str().unwrap_or_default()),
        }
    }
    Ok(())
}

// Setup -----------------------------------------------------------------------------------------------

fn desktop_entry(lines: &[String]) -> String {
    format!("{GENERATED_MARK}\n[Desktop Entry]\n{}\n", lines.join("\n"))
}

fn write_if_changed(path: &Path, text: &str) -> Result<bool> {
    if fs::read_to_string(path).is_ok_and(|current| current == text) {
        return Ok(false);
    }
    write_text(path, text)?;
    Ok(true)
}

/// Exec= quoting from the desktop entry spec: double quotes, with \ " ` $ escaped.
fn desktop_quote(argument: &str) -> String {
    if !argument.chars().any(|c| " \t\n\"'\\><~|&;$*?#()`".contains(c)) {
        return argument.to_string();
    }
    let mut quoted = String::from("\"");
    for c in argument.chars() {
        if "\"`$\\".contains(c) {
            quoted.push('\\');
        }
        quoted.push(c);
    }
    quoted.push('"');
    quoted
}

fn write_own_entries() -> Result<bool> {
    let command = format!("{} apps", desktop_quote(&launcher().to_string_lossy()));
    let lines = |lines: &[&str]| lines.iter().map(|line| line.to_string()).collect::<Vec<_>>();
    let mut chooser = lines(&["Type=Application", "Name=Choose an app", "Name[ru]=Выбрать приложение",
        "Comment=Asks which app should open the file", "Comment[ru]=Спрашивает, каким приложением открыть файл", "Icon=document-open"]);
    chooser.push(format!("Exec={command} open-with %U"));
    chooser.extend(lines(&["NoDisplay=true", "Terminal=false"]));
    let mut changed = write_if_changed(&user_apps().join(CHOOSER_ID), &desktop_entry(&chooser))?;

    let mut mail = lines(&["Type=Application", "Name=Web mail", "Name[ru]=Веб-почта",
        "Comment=Opens email links in the web mail chosen in Settings", "Icon=internet-mail"]);
    mail.push(format!("Exec={command} mailto %u"));
    mail.extend(lines(&["MimeType=x-scheme-handler/mailto;", "NoDisplay=true", "Terminal=false"]));
    changed |= write_if_changed(&user_apps().join(WEBMAIL_ID), &desktop_entry(&mail))?;

    if which("dolphin").is_some() {
        let mut archive = lines(&["Type=Application", "Name=Dolphin", "GenericName=Opens archives as folders",
            "GenericName[ru]=Открывает архивы как папки", "Icon=org.kde.dolphin"]);
        archive.push(format!("Exec={command} open-archive %U"));
        let types: Vec<&str> = ARCHIVE_PROTOCOLS.iter().map(|(mime, _)| *mime).collect();
        archive.push(format!("MimeType={};", types.join(";")));
        archive.extend(lines(&["NoDisplay=true", "Terminal=false"]));
        changed |= write_if_changed(&user_apps().join(ARCHIVE_ID), &desktop_entry(&archive))?;
    }
    for id in HIDDEN_APPS {
        changed |= hide_app(id)?;
    }
    Ok(changed)
}

/// A copy of the system entry that stays out of menus and doesn't claim any file types.
fn hide_app(id: &str) -> Result<bool> {
    let target = user_apps().join(id);
    if target.is_file() {
        let current = String::from_utf8_lossy(&fs::read(&target)?).into_owned();
        if !current.starts_with(GENERATED_MARK) && !current.starts_with(OLD_GENERATED_MARK) {
            return Ok(false); // The user's own override wins
        }
    }
    let Some(source) = data_dirs().into_iter().map(|base| base.join("applications").join(id)).find(|path| path.is_file()) else {
        if target.is_file() {
            fs::remove_file(&target)?;
            return Ok(true);
        }
        return Ok(false);
    };
    let mut lines = vec![GENERATED_MARK.to_string()];
    let mut in_main = false;
    for line in String::from_utf8_lossy(&fs::read(&source)?).lines() {
        let stripped = line.trim();
        if stripped.starts_with('[') {
            if in_main {
                lines.push("NoDisplay=true".to_string());
            }
            in_main = stripped == "[Desktop Entry]";
        } else if in_main && matches!(stripped.split('=').next().unwrap_or_default().trim(), "NoDisplay" | "MimeType") {
            continue;
        }
        lines.push(line.to_string());
    }
    if in_main {
        lines.push("NoDisplay=true".to_string());
    }
    write_if_changed(&target, &format!("{}\n", lines.join("\n")))
}

fn seed(apps: &Apps) -> Result<()> {
    if read_store().get("seeded").is_some_and(|seeded| seeded.as_bool().unwrap_or(!seeded.is_null())) {
        return Ok(());
    }
    let explicit: HashMap<String, String> = ini_keys(&read_ini(&user_mimeapps())?, "Default Applications").into_iter().collect();
    let unset = |role: &Role| explicit.get(role.mimes[0]).is_none_or(|value| value == CHOOSER_ID);
    for (id, choices) in SEED {
        let Some(role) = role(id) else { continue };
        if let Some(choice) = choices.iter().find(|choice| apps.contains(choice)) {
            if unset(role) {
                set_role_app(role, choice, apps)?;
            }
        }
    }
    if let Some(mail) = role("mail").filter(|mail| unset(mail)) {
        if let Some(browser) = default_for_mime("x-scheme-handler/https", apps)? {
            if apps.get(&browser).is_some_and(App::is_browser) {
                set_role_app(mail, &browser, apps)?;
            }
        }
    }
    if which("kwriteconfig6").is_some() {
        let _ = Command::new("kwriteconfig6").args(["--file", "dolphinrc", "--group", "General", "--key", "BrowseThroughArchives", "true"]).status();
    }
    let mut store = read_store();
    store.insert("seeded".to_string(), json!(true));
    write_store(&store)
}

fn cmd_sync() -> Result<()> {
    let changed = write_own_entries()?;
    if changed && which("update-desktop-database").is_some() {
        let _ = Command::new("update-desktop-database").arg(user_apps()).stderr(Stdio::null()).status();
    }
    let apps = installed_apps();
    seed(&apps)?;
    // Every type that still has no app goes to the chooser
    let explicit: HashSet<String> = ini_keys(&read_ini(&user_mimeapps())?, "Default Applications").into_iter().map(|(mime, _)| mime).collect();
    let missing = pairs(all_types().into_iter().filter(|mime| !explicit.contains(mime)), CHOOSER_ID);
    if !missing.is_empty() {
        update_mimeapps(&user_mimeapps(), &missing, false)?;
    }
    if (changed || !missing.is_empty()) && which("kbuildsycoca6").is_some() {
        let _ = Command::new("kbuildsycoca6").stdout(Stdio::null()).stderr(Stdio::null()).status();
    }
    Ok(())
}

pub fn run(argv: Vec<String>) -> Result<()> {
    let arguments: Vec<&str> = argv.iter().map(String::as_str).collect();
    match arguments[..] {
        ["list"] => cmd_list(""),
        ["list", lang] => cmd_list(lang),
        ["set", role, id] => cmd_set(role, id),
        ["set-command", role, command] => cmd_set_command(role, command, ""),
        ["set-command", role, command, name] => cmd_set_command(role, command, name),
        ["set-webmail", service] => cmd_set_webmail(service),
        ["launch", role] => cmd_launch(role),
        ["open", id, ..] => open_app(id, &argv[2..], &installed_apps()),
        ["sync"] => cmd_sync(),
        ["open-with", _, ..] => cmd_open_with(&argv[1..]),
        ["set-mime", id, _, ..] => {
            if !installed_apps().contains(id) {
                bail!("No such app: {id}");
            }
            set_mime_defaults(&pairs(argv[2..].iter().cloned(), id), true)
        }
        ["unset-mime", _, ..] => set_mime_defaults(&pairs(argv[1..].iter().cloned(), CHOOSER_ID), false),
        ["mailto"] => cmd_mailto(""),
        ["mailto", uri] => cmd_mailto(uri),
        ["open-archive", _, ..] => {
            cmd_open_archive(&argv[1..]);
            Ok(())
        }
        _ => bail!("{USAGE}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(exec: &str) -> App {
        App {
            id: "a.desktop".into(), path: "/apps/a.desktop".into(), name: "A".into(), comment: String::new(), icon: "ic".into(),
            exec: exec.into(), terminal: false, mimes: HashSet::new(), categories: HashSet::new(), hidden: false,
        }
    }

    #[test]
    fn splits_like_a_shell() {
        assert_eq!(shell_split(r#"a "b c" 'd e' f\ g "h\"i" "j\k""#).unwrap(), ["a", "b c", "d e", "f g", "h\"i", "j\\k"]);
        assert_eq!(shell_split(r#"a """#).unwrap(), ["a", ""]);
        assert!(shell_split("a 'b").is_none());
    }

    #[test]
    fn uris_become_paths() {
        assert_eq!(to_path("file:///a%20b/c.txt"), "/a b/c.txt");
        assert_eq!(to_path("file://host/a#x"), "/a");
        assert_eq!(to_path("/plain/a:b"), "/plain/a:b");
        assert_eq!(url_scheme("HTTPS://x"), "https");
        assert_eq!(url_scheme("/a:b"), "");
        assert_eq!(url_scheme("1a:b"), "");
    }

    #[test]
    fn quoting_keeps_only_what_is_safe() {
        assert_eq!(quote("mailto:a b/ю", ""), "mailto%3Aa%20b%2F%D1%8E");
        assert_eq!(quote("/a b", "/"), "/a%20b");
    }

    #[test]
    fn exec_field_codes() {
        let uris = vec!["file:///x%20y".to_string(), "file:///z".to_string()];
        assert_eq!(expand_exec(&app("run %F"), &uris), [["run", "/x y", "/z"]]);
        assert_eq!(expand_exec(&app("run %U"), &uris), [["run", "file:///x%20y", "file:///z"]]);
        assert_eq!(expand_exec(&app("run %f"), &uris), [["run", "/x y"], ["run", "/z"]]);
        assert_eq!(expand_exec(&app("run"), &uris), [["run", "file:///x%20y", "file:///z"]]);
        assert_eq!(expand_exec(&app("run %i %c %% --x=%d"), &[]), [["run", "--icon", "ic", "A", "%", "--x="]]);
    }

    #[test]
    fn exec_paths_are_quoted_when_needed() {
        assert_eq!(desktop_quote("/a/b"), "/a/b");
        assert_eq!(desktop_quote("/a b/$c"), "\"/a b/\\$c\"");
    }
}
