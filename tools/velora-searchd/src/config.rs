use ignore::gitignore::{Gitignore, GitignoreBuilder};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    io::Read,
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
    sync::Arc,
};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct SourceReview {
    pub path: PathBuf,
    // Discovery stops at the threshold; this is a lower bound, not an exact total.
    pub files: usize,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub roots: Vec<PathBuf>,
    pub excludes: Vec<PathBuf>,
    pub large_folders: Vec<PathBuf>,
    pub source_reviews: Vec<SourceReview>,
    pub dataset_folders: Vec<PathBuf>,
    pub activity: bool,
    pub media: bool,
    pub semantic: bool,
    pub dataset_samples: bool,
    pub paused: bool,
    pub fast_indexing: bool,
    pub all_in: bool,
    pub max_files: usize,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            roots: vec![],
            excludes: vec![],
            large_folders: vec![],
            source_reviews: vec![],
            dataset_folders: vec![],
            activity: true,
            media: false,
            semantic: false,
            dataset_samples: false,
            paused: false,
            fast_indexing: false,
            all_in: false,
            max_files: 100_000,
        }
    }
}

impl Config {
    pub fn indexing_allowed(&self, on_battery: bool, idle: bool) -> bool {
        !self.paused && !on_battery && (idle || self.fast_indexing || self.all_in)
    }

    pub fn validate(&mut self) -> anyhow::Result<()> {
        self.large_folders.sort();
        self.large_folders.dedup();
        anyhow::ensure!(
            self.roots.len() <= 32
                && self.excludes.len() <= 256
                && self.large_folders.len() <= 256
                && self.dataset_folders.len() <= 256,
            "Too many sources"
        );
        anyhow::ensure!(
            (1..=100_000).contains(&self.max_files),
            "File limit must be between 1 and 100000"
        );
        for root in &mut self.roots {
            anyhow::ensure!(
                root.is_absolute() && root.is_dir(),
                "Sources must be existing absolute directories"
            );
            *root = root.canonicalize()?;
            anyhow::ensure!(
                !["/", "/proc", "/sys", "/dev", "/run", "/usr", "/etc", "/var"]
                    .iter()
                    .any(|p| root == Path::new(p)),
                "Choose personal directories, not a system root"
            );
            anyhow::ensure!(
                !blocked(root),
                "This directory contains private or generated data"
            );
        }
        let mut filter = SourceFilter::new(self);
        for root in &self.roots {
            anyhow::ensure!(
                !filter.in_environment(root),
                "Python and Conda environments are not search sources"
            );
        }
        self.roots.sort();
        self.roots.dedup();
        let mut roots: Vec<PathBuf> = Vec::new();
        for root in std::mem::take(&mut self.roots) {
            let selected_inside_review = self
                .source_reviews
                .iter()
                .any(|r| root != r.path && root.starts_with(&r.path));
            if selected_inside_review || !roots.iter().any(|p| root.starts_with(p)) {
                roots.push(root);
            }
        }
        self.roots = roots;
        for path in self
            .excludes
            .iter()
            .chain(&self.large_folders)
            .chain(&self.dataset_folders)
            .chain(self.source_reviews.iter().map(|r| &r.path))
        {
            anyhow::ensure!(
                path.is_absolute()
                    && !path
                        .components()
                        .any(|c| c == std::path::Component::ParentDir),
                "Folder choices must be absolute paths"
            );
        }
        for path in &mut self.dataset_folders {
            if path.is_dir() {
                *path = path.canonicalize()?;
            }
        }
        self.dataset_folders.sort();
        self.dataset_folders.dedup();
        self.large_folders.retain(|p| {
            self.roots.iter().any(|r| p.starts_with(r))
                && !self.excludes.iter().any(|r| p.starts_with(r))
        });
        self.source_reviews.retain(|review| {
            review.path.is_dir()
                && self.roots.iter().any(|r| review.path.starts_with(r))
                && !self
                    .excludes
                    .iter()
                    .chain(&self.large_folders)
                    .any(|r| review.path.starts_with(r))
        });
        Ok(())
    }

    pub fn allows(&self, path: &Path) -> bool {
        path.is_absolute()
            && !blocked(path)
            && self.roots.iter().any(|r| path.starts_with(r))
            && !self.excludes.iter().any(|r| path.starts_with(r))
            && !self.source_reviews.iter().any(|r| {
                path.starts_with(&r.path)
                    && !self.roots.iter().any(|root| {
                        root != &r.path && root.starts_with(&r.path) && path.starts_with(root)
                    })
            })
            && !path
                .components()
                .any(|c| c == std::path::Component::ParentDir)
    }

    pub fn readable(&self, path: &Path) -> bool {
        SourceFilter::new(self).readable(path)
    }
}

// One filter per scan/reconciliation. Environment markers are checked once per
// directory, rather than statting every ancestor again for every installed package.
pub struct SourceFilter<'a> {
    config: &'a Config,
    environments: HashMap<PathBuf, bool>,
    directories: HashMap<PathBuf, DirectoryRules>,
    sample_directories: HashMap<PathBuf, bool>,
}

#[derive(Clone, Default)]
struct DirectoryRules {
    ignored: bool,
    // Ancestors first: a nearer rule, or .ignore after .gitignore, wins.
    rules: Vec<Arc<Gitignore>>,
}

impl DirectoryRules {
    fn ignores(&self, path: &Path, is_dir: bool) -> bool {
        self.ignored
            || self
                .rules
                .iter()
                .rev()
                .find_map(|rules| {
                    let matched = rules.matched(path, is_dir);
                    (!matched.is_none()).then(|| matched.is_ignore())
                })
                .unwrap_or(false)
    }
}

impl<'a> SourceFilter<'a> {
    pub fn new(config: &'a Config) -> Self {
        Self {
            config,
            environments: HashMap::new(),
            directories: HashMap::new(),
            sample_directories: HashMap::new(),
        }
    }

    fn in_environment(&mut self, path: &Path) -> bool {
        if let Some(excluded) = self.environments.get(path) {
            return *excluded;
        }
        let excluded = path
            .parent()
            .is_some_and(|parent| self.in_environment(parent))
            || path.join("pyvenv.cfg").is_file()
            || path.join("conda-meta").is_dir()
            || (path.parent().is_some()
                && path.join("lib/libpython3.so").is_file()
                && path.join("bin/python3").is_file())
            || path.join("tlpkg/texlive.tlpdb").is_file()
            || (path.join("CMakeCache.txt").is_file() && path.join("CMakeFiles").is_dir());
        self.environments.insert(path.to_owned(), excluded);
        excluded
    }

    pub fn allows(&mut self, path: &Path) -> bool {
        self.config.allows(path)
            && !self.in_environment(path)
            && !self.project_ignored(path)
            && !self.bulk_sample(path)
    }

    fn bulk_sample(&mut self, path: &Path) -> bool {
        if self.config.dataset_samples || path.is_dir() {
            return false;
        }
        if self
            .config
            .dataset_folders
            .iter()
            .any(|root| path.starts_with(root))
            && dataset_sample(path)
        {
            return true;
        }
        if !numpy_array(path) {
            return false;
        }
        let Some(parent) = path.parent() else {
            return false;
        };
        *self
            .sample_directories
            .entry(parent.to_owned())
            .or_insert_with(|| {
                // Keep small collections, folders and metadata searchable without
                // opening arrays. Count once per directory and stop at the threshold.
                std::fs::read_dir(parent).is_ok_and(|entries| {
                    entries
                        .filter_map(Result::ok)
                        .filter(|entry| {
                            numpy_array(&entry.path())
                                && entry.file_type().is_ok_and(|t| t.is_file())
                        })
                        .take(1_000)
                        .count()
                        == 1_000
                })
            })
    }

    fn directory_rules(&mut self, directory: &Path) -> DirectoryRules {
        if let Some(rules) = self.directories.get(directory) {
            return rules.clone();
        }
        // Only inspect ignore files inside selected sources. Explicit roots
        // remain searchable; their own rules govern their children.
        let mut rules = if self.config.roots.iter().any(|root| directory == root) {
            DirectoryRules::default()
        } else if let Some(parent) = directory.parent() {
            let mut inherited = self.directory_rules(parent);
            inherited.ignored = inherited.ignores(directory, true);
            inherited
        } else {
            return DirectoryRules::default();
        };
        if !rules.ignored {
            for name in [".gitignore", ".ignore"] {
                let path = directory.join(name);
                // Ignore rules are data. Do not follow links or block on a FIFO,
                // and bound their size before parsing them.
                let Ok(file) = std::fs::OpenOptions::new()
                    .read(true)
                    .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
                    .open(&path)
                else {
                    continue;
                };
                if !file
                    .metadata()
                    .is_ok_and(|m| m.is_file() && m.len() <= 1024 * 1024)
                {
                    continue;
                }
                let mut content = String::new();
                if file
                    .take(1024 * 1024 + 1)
                    .read_to_string(&mut content)
                    .is_err()
                    || content.len() > 1024 * 1024
                {
                    continue;
                }
                let mut builder = GitignoreBuilder::new(directory);
                for line in content.lines() {
                    // One invalid pattern must not disable valid exclusions.
                    let _ = builder.add_line(Some(path.clone()), line);
                }
                if let Ok(matcher) = builder.build() {
                    if !matcher.is_empty() {
                        rules.rules.push(Arc::new(matcher));
                    }
                }
            }
        }
        self.directories.insert(directory.to_owned(), rules.clone());
        rules
    }

    fn project_ignored(&mut self, path: &Path) -> bool {
        if self.config.roots.iter().any(|root| root == path) {
            return false;
        }
        path.parent()
            .is_some_and(|parent| self.directory_rules(parent).ignores(path, path.is_dir()))
    }

    pub fn readable(&mut self, path: &Path) -> bool {
        // Canonicalize on every open; a symlink must never escape a configured source.
        self.allows(path)
            && path.canonicalize().is_ok_and(|p| self.allows(&p))
            && path
                .symlink_metadata()
                .is_ok_and(|m| !m.file_type().is_symlink())
            && if path.is_dir() {
                std::fs::read_dir(path).is_ok()
            } else {
                std::fs::File::open(path).is_ok()
            }
    }
}

fn numpy_array(path: &Path) -> bool {
    path.extension()
        .and_then(|s| s.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("npy") || ext.eq_ignore_ascii_case("npz"))
}

fn dataset_sample(path: &Path) -> bool {
    // Explicit dataset folders only: ordinary photo libraries keep media search.
    // Keep code, notebooks, README files, manifests and tabular metadata.
    matches!(
        path.extension()
            .and_then(|s| s.to_str())
            .unwrap_or_default()
            .to_ascii_lowercase()
            .as_str(),
        "jpg"
            | "jpeg"
            | "png"
            | "webp"
            | "bmp"
            | "tif"
            | "tiff"
            | "gif"
            | "avif"
            | "heic"
            | "mp4"
            | "mkv"
            | "webm"
            | "mov"
            | "avi"
            | "m4v"
            | "wav"
            | "mp3"
            | "flac"
            | "ogg"
            | "npy"
            | "npz"
            | "pkl"
            | "pickle"
            | "pt"
            | "pth"
            | "ckpt"
            | "safetensors"
            | "onnx"
            | "h5"
            | "hdf5"
            | "arrow"
            | "parquet"
            | "tfrecord"
            | "tfrecords"
            | "bin"
            | "idx"
    )
}

pub fn blocked(path: &Path) -> bool {
    let parts: Vec<_> = path
        .components()
        .filter_map(|c| c.as_os_str().to_str())
        .map(str::to_lowercase)
        .collect();
    // Electron applications keep large browser databases next to their settings.
    // Scope these names to .config; a project's source folder named History or
    // WebStorage is still useful. User/settings.json and snippets stay searchable.
    let app_state = parts.iter().position(|s| s == ".config").is_some_and(|i| {
        parts.iter().skip(i + 2).any(|s| {
            matches!(
                s.as_str(),
                "cache"
                    | "caches"
                    | "cache2"
                    | "code cache"
                    | "gpucache"
                    | "cacheddata"
                    | "cachedconfigurations"
                    | "cachedextensions"
                    | "cachedextensionvsixs"
                    | "dawncache"
                    | "dawngraphitecache"
                    | "dawnwebgpucache"
                    | "shadercache"
                    | "grshadercache"
                    | "crashpad"
                    | "crash reports"
                    | "webstorage"
                    | "partitions"
                    | "indexeddb"
                    | "local storage"
                    | "session storage"
                    | "service worker"
                    | "blob_storage"
                    | "workspacestorage"
                    | "globalstorage"
                    | "history"
                    | "logs"
            )
        })
    });
    app_state
        || parts.iter().any(|s| {
            matches!(
                s.as_str(),
                ".git"
                    | ".hg"
                    | ".svn"
                    | ".bzr"
                    | ".ssh"
                    | ".gnupg"
                    | ".aws"
                    | ".azure"
                    | ".kube"
                    | ".pki"
                    | ".cache"
                    | ".codex"
                    | ".agents"
                    | ".docker"
                    | ".envrc"
                    | ".password-store"
                    | ".venv"
                    | ".python"
                    | "venv"
                    | ".virtualenvs"
                    | ".conda"
                    | ".pixi"
                    | ".tox"
                    | ".nox"
                    | "__pypackages__"
                    | "site-packages"
                    | "dist-packages"
                    | "node_modules"
                    | "bower_components"
                    | "vendor"
                    | ".npm"
                    | ".yarn"
                    | ".pnpm-store"
                    | ".bun"
                    | ".cargo"
                    | ".rustup"
                    | ".gradle"
                    | ".m2"
                    | ".bundle"
                    | ".dart_tool"
                    | ".pub-cache"
                    | "__pycache__"
                    | ".pytest_cache"
                    | ".mypy_cache"
                    | ".ruff_cache"
                    | ".hypothesis"
                    | ".ipynb_checkpoints"
                    | ".next"
                    | ".nuxt"
                    | ".svelte-kit"
                    | ".angular"
                    | ".turbo"
                    | ".parcel-cache"
                    | ".sass-cache"
                    | ".nyc_output"
                    | "target"
                    | "build"
                    | "dist"
                    | "artifacts"
                    | "coverage"
                    | "cmakefiles"
                    | ".local"
                    | "keyrings"
                    | "kwalletd"
                    | "chromium"
                    | "google-chrome"
                    | "brave-browser"
                    | ".mozilla"
                    | "mozilla"
                    | "firefox"
                    | "vivaldi"
                    | "opera"
                    | "passwords"
                    | "credentials"
                    | "secrets"
                    | ".netrc"
                    | ".npmrc"
                    | ".pypirc"
                    | ".bash_history"
                    | ".zsh_history"
                    | "fish_history"
                    | "velora-lens"
            ) || s == ".env"
                || s.starts_with(".env.")
                || s.starts_with("cmake-build-")
                || s.ends_with(".egg-info")
                || s.ends_with(".dist-info")
                || s.ends_with(".pyc")
                || s.ends_with(".pyo")
                || s.ends_with(".tsbuildinfo")
                || s.ends_with(".pem")
                || s.ends_with(".key")
                || s.ends_with(".p12")
                || s.ends_with(".kdbx")
                || s.starts_with("id_rsa")
                || s.starts_with("id_ed25519")
        })
}

pub fn kind(path: &Path) -> &'static str {
    if path.is_dir() {
        return "folder";
    }
    match path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase()
        .as_str()
    {
        "jpg" | "jpeg" | "png" | "webp" | "bmp" | "tif" | "tiff" | "gif" => "photo",
        "mp4" | "mkv" | "webm" | "mov" | "avi" | "m4v" => "video",
        "lua" if path.components().any(|c| c.as_os_str() == ".config") => "config",
        "ini" | "conf" | "cfg" => "config",
        "toml" | "yaml" | "yml" | "json" => {
            let name = path
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_lowercase();
            if path.components().any(|c| {
                matches!(
                    c.as_os_str().to_str(),
                    Some(".config" | ".vscode" | "config" | "configs" | "settings")
                )
            }) || name.contains("config")
                || name.contains("settings")
                || matches!(
                    name.as_str(),
                    "cargo.toml"
                        | "pyproject.toml"
                        | "package.json"
                        | "docker-compose.yml"
                        | "compose.yaml"
                )
            {
                "config"
            } else {
                "file"
            }
        }
        "pdf" | "txt" | "md" | "rst" | "org" | "ipynb" | "py" | "rs" | "c" | "h" | "cpp"
        | "hpp" | "js" | "jsx" | "ts" | "tsx" | "go" | "java" | "kt" | "sh" | "zsh" | "fish"
        | "qml" | "lua" | "html" | "css" | "tex" | "csv" => "file",
        "" if path.metadata().is_ok_and(|m| m.len() <= 2 * 1024 * 1024) => "file",
        _ => "name",
    }
}

pub fn scrub(text: &str) -> String {
    // Fail closed for multi-line credentials, and never retain credential-looking lines.
    static SECRET: std::sync::OnceLock<regex::Regex> = std::sync::OnceLock::new();
    let pattern = SECRET.get_or_init(|| regex::Regex::new(r#"(?i)(\b[a-z0-9_.-]*(?:password|passwd|secret|tokens?|api[_-]?key|authorization|private[_-]?key|credentials?)\b["']?\s*[:=]|\bbearer\s+[a-z0-9._~+/-]{8,}|https?://[^\s/:]+:[^\s/@]+@)"#).unwrap());
    if text.contains("PRIVATE KEY-----") {
        return String::new();
    }
    let mut lines = Vec::new();
    let mut skip_indent = None;
    for line in text.lines() {
        let indent = line.len() - line.trim_start().len();
        if let Some(level) = skip_indent {
            if line.trim().is_empty() || indent > level {
                continue;
            }
            skip_indent = None;
        }
        if pattern.is_match(line) {
            skip_indent = Some(indent);
            continue;
        }
        lines.push(line.chars().take(4096).collect::<String>());
    }
    lines.join("\n").chars().take(128_000).collect()
}

pub fn data_dir() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/share")
        })
        .join("velora-lens")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn neural_indexing_is_opt_in() {
        let defaults = Config::default();
        assert!(!defaults.semantic && !defaults.media);
        let missing: Config = serde_json::from_str("{}").unwrap();
        assert!(!missing.semantic && !missing.media);
        let saved: Config = serde_json::from_str(r#"{"semantic":true,"media":true,"activity":true}"#).unwrap();
        assert!(saved.semantic && saved.media && saved.activity);
    }

    #[test]
    fn preserves_subject_matter_while_scrubbing_credential_assignments() {
        let prose="Language modeling predicts the next token.\nThe tokenizer converts words into token identifiers.\ntoken_embeddings = model.encode(words)\nA secret sharing algorithm splits a message.";
        assert_eq!(scrub(prose), prose);
        for secret in [
            "api_key = abc",
            "export OPENAI_API_KEY=abc",
            "accessToken: abc",
            "\"clientSecret\": \"abc\"",
            "password: |\n  line one\n  line two",
            "Authorization: Bearer abcdefghi",
            "https://user:pass@example.test/",
        ] {
            assert_eq!(
                scrub(&format!("{secret}\nvisible = true")),
                "visible = true",
                "{secret}"
            );
        }
    }
    #[test]
    fn excludes_secrets_and_generated_content() {
        for p in [
            "/home/me/.ssh/config",
            "/home/me/p/.env.local",
            "/home/me/p/node_modules/a",
            "/home/me/p/.venv/lib/python3.14/package.py",
            "/home/me/p/.next/dev/cache/entry",
            "/home/me/p/.mypy_cache/cache.json",
            "/home/me/p/.gradle/caches/entry",
            "/home/me/p/cmake-build-debug/output",
            "/home/me/p/library.egg-info/PKG-INFO",
            "/home/me/p/artifacts/audit/rust-target/output",
            "/home/me/p/package.pyc",
            "/home/me/.config/chromium/Preferences",
            "/home/me/.config/Code/WebStorage/entry",
            "/home/me/.config/Code/CachedConfigurations/folder/configuration.json",
            "/home/me/.config/Code/Partitions/entry",
            "/home/me/.config/Code/User/workspaceStorage/entry",
            "/home/me/.config/discord/Code Cache/entry",
        ] {
            assert!(blocked(Path::new(p)), "{p}");
        }
        for p in [
            "/home/me/.config/hypr/hyprland.lua",
            "/home/me/.config/Code/User/settings.json",
            "/home/me/.config/Code/User/keybindings.json",
            "/home/me/.config/Code/User/snippets/python.json",
            "/home/me/project/.vscode/settings.json",
            "/home/me/project/package-lock.json",
            "/home/me/project/poetry.lock",
            "/home/me/project/node_modules.md",
            "/home/me/project/WebStorage/storage.ts",
            "/home/me/Documents/History/notes.md",
            "/home/me/llvm-project/llvm/test/example.ll",
        ] {
            assert!(!blocked(Path::new(p)), "{p}");
        }
        assert_eq!(
            scrub("bind = SUPER, A\napi_key = abc\npassword: abc"),
            "bind = SUPER, A"
        );
    }
    #[test]
    fn recognizes_environments_by_markers_not_only_folder_names() {
        let t = tempfile::tempdir().unwrap();
        let config = Config {
            roots: vec![t.path().to_owned()],
            ..Config::default()
        };
        for (name, environment) in [
            ("python-tools", "venv"),
            (".conda-eval", "conda"),
            ("runtime", "python"),
            ("native-output", "cmake"),
        ] {
            let root = t.path().join(name);
            std::fs::create_dir_all(root.join("lib")).unwrap();
            let file = root.join("lib/package.py");
            std::fs::write(&file, "package source").unwrap();
            assert!(config.readable(&file));
            if environment == "cmake" {
                std::fs::write(root.join("CMakeCache.txt"), "generated").unwrap();
                std::fs::create_dir(root.join("CMakeFiles")).unwrap();
            } else if environment == "conda" {
                std::fs::create_dir(root.join("conda-meta")).unwrap();
            } else if environment == "python" {
                std::fs::create_dir(root.join("bin")).unwrap();
                std::fs::write(root.join("bin/python3"), "binary").unwrap();
                std::fs::write(root.join("lib/libpython3.so"), "binary").unwrap();
            } else {
                std::fs::write(root.join("pyvenv.cfg"), "home = /usr/bin").unwrap();
            }
            assert!(!config.readable(&root));
            assert!(!config.readable(&file));
            let mut explicit = Config {
                roots: vec![root.join("lib")],
                ..Config::default()
            };
            assert!(
                explicit.validate().is_err(),
                "cannot add a subtree of an environment"
            );
        }
        let ordinary = t.path().join("environment-notes.md");
        std::fs::write(&ordinary, "documentation").unwrap();
        assert!(config.readable(&ordinary));
    }
    #[test]
    fn dataset_folders_skip_samples_but_preserve_work_and_ordinary_photos() {
        let t = tempfile::tempdir().unwrap();
        let root = t.path();
        let dataset = root.join("training-data");
        for relative in [
            "training-data/train/class/001.JPEG",
            "training-data/test/array.npy",
            "training-data/weights.safetensors",
            "training-data/train/labels.csv",
            "training-data/README.md",
            "training-data/analysis.ipynb",
            "training-data/prepare.py",
            "training-data/manifest.json",
            "training-data/report.pdf",
            "training-data-extra/photo.jpg",
            "Photos/holiday.jpg",
            "training-data/.env",
        ] {
            let file = root.join(relative);
            std::fs::create_dir_all(file.parent().unwrap()).unwrap();
            std::fs::write(file, "fixture").unwrap();
        }
        std::fs::create_dir(dataset.join("photos.png")).unwrap();
        let mut config = Config {
            roots: vec![root.to_owned()],
            dataset_folders: vec![dataset.clone()],
            ..Config::default()
        };
        config.validate().unwrap();
        let mut filter = SourceFilter::new(&config);
        for relative in [
            "train/class/001.JPEG",
            "test/array.npy",
            "weights.safetensors",
        ] {
            assert!(!filter.readable(&dataset.join(relative)), "{relative}");
        }
        for relative in [
            "",
            "train",
            "photos.png",
            "train/labels.csv",
            "README.md",
            "analysis.ipynb",
            "prepare.py",
            "manifest.json",
            "report.pdf",
        ] {
            assert!(filter.readable(&dataset.join(relative)), "{relative}");
        }
        for relative in ["Photos/holiday.jpg", "training-data-extra/photo.jpg"] {
            assert!(filter.readable(&root.join(relative)), "{relative}");
        }
        config.dataset_samples = true;
        assert!(config.readable(&dataset.join("train/class/001.JPEG")));
        assert!(!config.readable(&dataset.join(".env")));
        config.dataset_samples = false;
        config.dataset_folders.clear();
        assert!(config.readable(&dataset.join("train/class/001.JPEG")));
        config.dataset_folders.push(root.join("../outside"));
        assert!(config.validate().is_err());
        assert!(serde_json::from_str::<Config>("{}")
            .unwrap()
            .dataset_folders
            .is_empty());
    }

    #[test]
    fn bulk_arrays_preserve_folders_metadata_and_small_collections() {
        let t = tempfile::tempdir().unwrap();
        let root = t.path();
        let samples = root.join("samples");
        std::fs::create_dir(&samples).unwrap();
        let mut config = Config {
            roots: vec![root.to_owned()],
            ..Config::default()
        };
        for n in 0..999 {
            std::fs::write(samples.join(format!("{n}.npy")), "array").unwrap();
        }
        assert!(config.readable(&samples.join("0.npy")));
        std::fs::write(samples.join("last.NPZ"), "array").unwrap();
        std::fs::write(samples.join("README.md"), "dataset description").unwrap();
        std::fs::write(root.join("single.npy"), "array").unwrap();
        // A directory named like an array is still a directory.
        std::fs::create_dir(samples.join("notes.npy")).unwrap();
        let mut filter = SourceFilter::new(&config);
        assert!(!filter.readable(&samples.join("0.npy")));
        assert!(!filter.readable(&samples.join("last.NPZ")));
        for path in [
            &samples,
            &samples.join("README.md"),
            &samples.join("notes.npy"),
            &root.join("single.npy"),
        ] {
            assert!(filter.readable(path), "{}", path.display());
        }
        config.dataset_samples = true;
        assert!(config.readable(&samples.join("0.npy")));
        // Existing saved configurations get the conservative default.
        assert!(
            !serde_json::from_str::<Config>("{}")
                .unwrap()
                .dataset_samples
        );
    }

    #[test]
    fn project_ignore_rules_keep_sources_and_cannot_override_private_exclusions() {
        let t = tempfile::tempdir().unwrap();
        let root = t.path();
        for relative in [
            "cache/copy.py",
            "src/cache/useful.py",
            "src/hidden.tmp",
            "src/keep.tmp",
            "src/nested/.gitignore",
            "src/nested/example.tmp",
            "private-copy/report.md",
            "private-copy/.gitignore",
            "local-output/item.txt",
            "node_modules/pkg.js",
        ] {
            let file = root.join(relative);
            std::fs::create_dir_all(file.parent().unwrap()).unwrap();
            std::fs::write(file, "fixture").unwrap();
        }
        std::fs::write(
            root.join(".gitignore"),
            "/cache/\n*.tmp\n!keep.tmp\n/private-copy/\n!node_modules/\n",
        )
        .unwrap();
        std::fs::write(root.join(".ignore"), "/local-output/\n").unwrap();
        std::fs::write(root.join("src/nested/.gitignore"), "!example.tmp\n").unwrap();
        // Git cannot re-include a child of an excluded directory.
        std::fs::write(root.join("private-copy/.gitignore"), "!report.md\n").unwrap();
        let config = Config {
            roots: vec![root.to_owned()],
            ..Config::default()
        };
        let mut filter = SourceFilter::new(&config);
        for relative in [
            "cache/copy.py",
            "src/hidden.tmp",
            "private-copy/report.md",
            "local-output/item.txt",
            "node_modules/pkg.js",
        ] {
            assert!(!filter.readable(&root.join(relative)), "{relative}");
        }
        for relative in [
            "src/cache/useful.py",
            "src/keep.tmp",
            "src/nested/example.tmp",
        ] {
            assert!(filter.readable(&root.join(relative)), "{relative}");
        }
        // Each reconciliation picks up rule changes, without stale global caches.
        std::fs::write(root.join(".gitignore"), "").unwrap();
        assert!(config.readable(&root.join("cache/copy.py")));
        std::fs::remove_file(root.join(".ignore")).unwrap();
        assert!(config.readable(&root.join("local-output/item.txt")));
    }

    #[test]
    fn ignore_files_do_not_follow_links_or_read_outside_selected_roots() {
        let t = tempfile::tempdir().unwrap();
        let root = t.path().join("selected");
        std::fs::create_dir(&root).unwrap();
        std::fs::write(t.path().join(".gitignore"), "*\n").unwrap();
        let file = root.join("notes.md");
        std::fs::write(&file, "notes").unwrap();
        std::os::unix::fs::symlink(t.path().join(".gitignore"), root.join(".ignore")).unwrap();
        let config = Config {
            roots: vec![root],
            ..Config::default()
        };
        assert!(config.readable(&file));
    }

    #[test]
    fn does_not_follow_a_symlink_out_of_scope() {
        let t = tempfile::tempdir().unwrap();
        let root = t.path().join("root");
        std::fs::create_dir(&root).unwrap();
        let outside = t.path().join("outside");
        std::fs::write(&outside, "private").unwrap();
        std::os::unix::fs::symlink(&outside, root.join("link")).unwrap();
        let c = Config {
            roots: vec![root.clone()],
            ..Config::default()
        };
        assert!(!c.readable(&root.join("link")));
    }
}
