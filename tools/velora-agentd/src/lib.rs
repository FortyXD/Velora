pub mod process;
pub mod provider;
pub mod task;
pub mod tools;
pub mod transaction;

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const PROTOCOL: u32 = 3;

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
            context_tokens: 4096,
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
    pub presets: Vec<Value>,
    pub selection: Vec<String>,
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
            presets: vec![],
            selection: vec![],
            rollback_budget_bytes: 2 * 1024 * 1024 * 1024,
        }
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
