pub mod desktop;
pub mod process;
pub mod provider;
pub mod task;
pub mod tools;
pub mod transaction;

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const PROTOCOL: u32 = 6;

#[derive(Clone, Deserialize, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct Profile {
    pub provider: String,
    pub endpoint: String,
    pub model: String,
    pub strong_model: String,
    // Never derive Debug for credentials or task context.
    #[serde(skip_serializing)]
    pub key: String,
    pub vision: bool,
    pub gpu: bool,
    pub context_tokens: usize,
    pub idle_seconds: Option<u64>,
}
impl Profile {
    pub fn select_local_backend(&mut self, on_battery: bool) {
        if self.provider == "ollama" && (on_battery || !self.gpu) && matches!(
            self.endpoint.trim_end_matches('/'),
            "http://127.0.0.1:11434" | "http://localhost:11434" | "http://[::1]:11434"
        ) {
            self.endpoint = "http://127.0.0.1:11435".into();
        }
    }

    pub fn keep_alive(&self, battery: bool) -> u64 {
        self.idle_seconds.unwrap_or(if battery { 30 * 60 } else { 60 * 60 }).min(86400)
    }
}
impl Default for Profile {
    fn default() -> Self {
        Self {
            provider: "ollama".into(),
            endpoint: "http://127.0.0.1:11434".into(),
            model: String::new(),
            strong_model: String::new(),
            key: String::new(),
            vision: false,
            gpu: false,
            context_tokens: 16384,
            idle_seconds: None,
        }
    }
}

#[derive(Clone, Deserialize, Default)]
#[serde(default, deny_unknown_fields)]
pub struct App {
    pub id: String,
    pub name: String,
    pub class: String,
}

#[derive(Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Context {
    pub locked: bool,
    /// The shell acknowledges hiding its interactive overlays before UI tools run.
    pub shell_ui: bool,
    pub on_battery: bool,
    pub policy: u8,
    pub profile: Profile,
    pub apps: Vec<App>,
    pub terminal_command: String,
    pub presets: Vec<Value>,
    pub selection: Vec<String>,
    pub auto_local_search: bool,
    pub trusted_read_folders: Vec<String>,
    pub rollback_budget_bytes: u64,
}
impl Default for Context {
    fn default() -> Self {
        Self {
            locked: true,
            shell_ui: false,
            on_battery: true,
            policy: 2,
            profile: Profile::default(),
            apps: vec![],
            terminal_command: String::new(),
            presets: vec![],
            selection: vec![],
            auto_local_search: true,
            trusted_read_folders: vec![],
            rollback_budget_bytes: 2 * 1024 * 1024 * 1024,
        }
    }
}

impl Context {
    fn local_ollama(&self) -> bool {
        self.profile.provider == "ollama" && provider::local_endpoint(&self.profile.endpoint)
    }

    fn scoped_search(&self, args: &Value) -> bool {
        self.local_ollama() && !self.trusted_read_folders.is_empty() && args["scope"] != "all"
    }

    fn permits_search(&self, tool: &str, args: &Value) -> bool {
        self.auto_local_search && self.local_ollama()
            && (tool == "apps_list" || (tool == "search"
                && (self.trusted_read_folders.is_empty() || self.scoped_search(args))))
    }
}

pub fn helper() -> String {
    std::env::var("VELORA_HELPER").unwrap_or_else(|_| {
        let p = std::path::PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
            .join(".local/bin/velora-helper");
        if p.is_file() {
            p.to_string_lossy().into_owned()
        } else {
            "velora-helper".into()
        }
    })
}

pub fn tool_script() -> std::path::PathBuf {
    let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("python/tools.py");
    let installed = std::path::Path::new("/usr/share/velora/tools/velora-agentd/python/tools.py");
    if source.is_file() {
        source
    } else {
        installed.into()
    }
}
