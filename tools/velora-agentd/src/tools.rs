use crate::{
    process::{self, args},
    transaction, Context as DesktopContext,
};
use anyhow::{bail, Context, Result};
use base64::Engine;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
use tokio::io::{AsyncWriteExt, BufReader};

pub struct ToolSpec {
    pub name: &'static str,
    pub description: &'static str,
    pub properties: Value,
    pub required: Vec<&'static str>,
    pub approval: bool,
}

#[derive(Debug)]
pub struct SelectionCancelled;
impl std::fmt::Display for SelectionCancelled {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("File selection cancelled")
    }
}
impl std::error::Error for SelectionCancelled {}
fn spec(
    name: &'static str,
    description: &'static str,
    properties: Value,
    required: &[&'static str],
    approval: bool,
) -> ToolSpec {
    ToolSpec {
        name,
        description,
        properties,
        required: required.to_vec(),
        approval,
    }
}
pub fn read_only(name: &str) -> bool {
    matches!(
        name,
        "tools_enable"
            | "task_plan"
            | "ask_user"
            | "search"
            | "files_choose"
            | "files_read"
            | "files_list"
            | "files_usage"
            | "system_status"
            | "apps_list"
            | "ui_inspect"
            | "ui_screenshot"
    )
}
pub fn supported(name: &str) -> bool {
    read_only(name)
        || matches!(
            name,
            "files_zip"
                | "files_mkdir"
                | "files_copy"
                | "files_move"
                | "files_trash"
                | "files_write"
                | "terminal_run"
        )
}
pub fn registry() -> Vec<ToolSpec> {
    let string = json!({"type":"string"});
    let refs = json!({"type":"array","items":{"type":"string"},"minItems":1,"maxItems":100});
    vec![
        spec("tools_enable","Load files, desktop (system diagnostics, brightness, audio, apps and workspaces), terminal (approved commands), or ui (inspection) tools.",json!({"group":{"type":"string","enum":["files","desktop","terminal","ui"]}}),&["group"],false),
        spec("task_plan","Track the steps of a multi-step task and how to verify the deliverable. completed is the number of finished steps.",json!({"steps":{"type":"array","items":{"type":"string"},"maxItems":12,"minItems":1},"completed":{"type":"integer","minimum":0,"maximum":12}}),&["steps","completed"],false),
        spec("ask_user","Ask a focused question only if required information or a choice cannot be obtained with tools. Use the user's language.",json!({"question":string}),&["question"],false),
        spec("search","Find a local file or folder by its short name. Use kind=folder for a directory. When trusted folders are configured, search defaults to them and scope=all asks to search outside them. Use the returned refs.",json!({"query":string,"scope":{"type":"string","enum":["trusted","all"]},"kind":{"type":"string","enum":["folder","any"]}}),&["query"],false),
        spec("files_choose","Ask the person to select files or a folder when no unambiguous source is available.",json!({"kind":{"type":"string","enum":["files","folder"]}}),&[],false),
        spec("files_read","Read a text or PDF excerpt by file ref. For text pass next_offset to continue; for PDF choose page (starting at 1).",json!({"ref":string,"offset":{"type":"integer","minimum":0},"page":{"type":"integer","minimum":1,"maximum":100000}}),&["ref"],false),
        spec("files_list","List children of a folder ref or desktop. Use returned refs to read, edit or enter subfolders. Pass next_cursor as after for the next page.",json!({"ref":string,"after":string}),&["ref"],false),
        spec("files_write","Save UTF-8 text. Create a file with parent folder ref and name, or edit an existing file by ref. The user reviews the diff.",json!({"parent":string,"name":string,"ref":string,"text":string}),&["text"],true),
        spec("files_usage","Measure disk space used by a directory ref and its largest children, in allocated bytes. A partial result is a lower bound.",json!({"ref":string}),&["ref"],false),
        spec("files_open","Open a selected or found file ref using its default app.",json!({"ref":string}),&["ref"],false),
        spec("files_zip","Create a ZIP on the XDG desktop, or inside a directory ref. Never overwrite. Sources are file refs.",json!({"sources":refs,"destination":string,"name":string}),&["sources"],false),
        spec("files_mkdir","Create a new folder inside a directory ref, or desktop.",json!({"parent":string,"name":string}),&["parent","name"],false),
        spec("files_copy","Copy a file or folder ref to a new name inside a directory ref. Never overwrite.",json!({"ref":string,"parent":string,"name":string}),&["ref","parent","name"],false),
        spec("files_move","Move or rename a file ref within its filesystem. Never overwrite.",json!({"ref":string,"parent":string,"name":string}),&["ref","parent","name"],false),
        spec("files_trash","Remove a file ref after confirmation, preserving its complete recoverable checkpoint.",json!({"ref":string}),&["ref"],true),
        spec("system_status","Inspect this computer now. failures checks failed system/user services and recent errors from this boot. Other topics report live system state.",json!({"topic":{"type":"string","enum":["failures","storage","memory","processes","network","power","audio","displays","workspaces"]}}),&["topic"],true),
        spec("desktop_adjust","Change brightness on the focused display or default speaker volume. Supply either a signed delta in percentage points or an absolute percent.",json!({"setting":{"type":"string","enum":["brightness","volume"]},"delta":{"type":"integer","minimum":-100,"maximum":100},"percent":{"type":"integer","minimum":0,"maximum":100}}),&["setting"],true),
        spec("apps_list","Find installed desktop IDs and windows by name or abbreviation. Omit query to browse. Pass next_offset as offset for more results.",json!({"query":string,"offset":{"type":"integer","minimum":0}}),&[],false),
        spec("app_open","Launch an installed desktop ID from apps_list, optionally on an absolute workspace number. Reuse a matching window, choosing its address when ambiguous.",json!({"app_id":string,"workspace":{"type":"integer","minimum":1,"maximum":1000},"window":string}),&["app_id"],false),
        spec("workspace_focus","Focus an absolute workspace number, not a relative group.",json!({"number":{"type":"integer","minimum":1,"maximum":1000}}),&["number"],false),
        spec("window_move","Move a known window address to an absolute workspace and focus it.",json!({"window":string,"number":{"type":"integer","minimum":1,"maximum":1000}}),&["window","number"],false),
        spec("preset_apply","Apply one of the desktop presets supplied in context.",json!({"id":string}),&["id"],false),
        spec("terminal_run","Run a shell command, code with language, or a script file ref in an offline sandbox. Python 3 includes the standard library. Use its built-in modules instead of installing packages. cwd defaults to the selected folder or scratch. Input refs appear read-only at /inputs/1, /inputs/2 in list order. Changes are reviewed before saving.",json!({"command":string,"code":string,"language":{"type":"string","enum":["python","bash","javascript"]},"file":string,"cwd":string,"inputs":refs,"network":{"type":"boolean"}}),&[],true),
        spec("ui_inspect","Inspect accessible elements in the focused application. Falls back to a screenshot if accessibility is unavailable and vision is supported.",json!({}),&[],false),
        spec("ui_action","Invoke a named action on a control from the latest ui_inspect. Use a returned node id and action.",json!({"node":string,"action":string}),&["node"],true),
        spec("ui_set_text","Replace text in an inspected editable control. Use its node id. Review before applying.",json!({"node":string,"text":string}),&["node","text"],true),
        spec("ui_screenshot","Capture only the focused window. Requires a vision-capable model.",json!({}),&[],false),
        spec("ui_click","Click window-local screenshot coordinates after confirmation. Requires a recent screenshot and unchanged window geometry.",json!({"x":{"type":"integer","minimum":0},"y":{"type":"integer","minimum":0},"button":{"type":"string","enum":["left","right"]}}),&["x","y"],true),
        spec("ui_type","Type text into the inspected window after confirmation, without using the clipboard.",json!({"text":string}),&["text"],true),
        spec("ui_key","Send one supported key to the inspected window after confirmation.",json!({"key":{"type":"string","enum":["Return","Tab","Escape","BackSpace","Up","Down","Left","Right","space","ctrl+a","ctrl+c","ctrl+v","ctrl+s"]}}),&["key"],true),
        spec("ui_scroll","Scroll the inspected window after confirmation.",json!({"direction":{"type":"string","enum":["up","down"]},"amount":{"type":"integer","minimum":1,"maximum":10}}),&["direction"],true),
    ]
}
impl ToolSpec {
    pub fn wire(&self) -> Value {
        json!({"type":"function","function":{"name":self.name,"description":self.description,"parameters":{"type":"object","properties":self.properties,"required":self.required,"additionalProperties":false}}})
    }
    pub fn validate(&self, value: &Value) -> Result<()> {
        let obj = value
            .as_object()
            .context("Tool arguments must be an object")?;
        for name in &self.required {
            anyhow::ensure!(obj.contains_key(*name), "Missing argument: {name}");
        }
        for (key, v) in obj {
            let schema = self.properties.get(key).context("Unknown tool argument")?;
            let valid = match schema["type"].as_str().unwrap_or("") {
                "string" => v
                    .as_str()
                    .is_some_and(|s| s.len() <= 32768 && !s.contains('\0')),
                "integer" => v.as_i64().is_some(),
                "boolean" => v.is_boolean(),
                "array" => v.as_array().is_some_and(|a| {
                    !a.is_empty() && a.len() <= 100 && a.iter().all(Value::is_string)
                }),
                _ => false,
            };
            anyhow::ensure!(valid, "Invalid argument type: {key}");
            if let Some(n) = v.as_i64() {
                if let Some(min) = schema["minimum"].as_i64() {
                    anyhow::ensure!(n >= min, "Argument out of range");
                }
                if let Some(max) = schema["maximum"].as_i64() {
                    anyhow::ensure!(n <= max, "Argument out of range");
                }
            }
            if let Some(choices) = schema["enum"].as_array() {
                anyhow::ensure!(choices.contains(v), "Unsupported argument value");
            }
        }
        Ok(())
    }
}

#[derive(Clone)]
struct Resource {
    path: PathBuf,
    device: u64,
    inode: u64,
}
#[derive(Clone)]
struct Screen {
    window: Value,
    monitors: Value,
    image: Option<String>,
    at: Instant,
    nodes: Value,
}
#[derive(Default, Clone)]
pub struct Executor {
    resources: HashMap<String, Resource>,
    screen: Option<Screen>,
    next: u64,
}

async fn search_lens(query: &str) -> Result<Value> {
    let socket = PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR").context("No desktop session")?)
        .join("velora-lens/search.sock");
    let run = async {
        let stream = tokio::net::UnixStream::connect(socket)
            .await
            .context("Lens index unavailable")?;
        let (read, mut write) = stream.into_split();
        let mut lines = BufReader::new(read);
        let hello: Value = serde_json::from_str(
            &process::line(&mut lines, 2 * 1024 * 1024)
                .await?
                .context("Lens disconnected")?,
        )?;
        anyhow::ensure!(hello["protocol"] == 1, "Unsupported Lens protocol");
        write
            .write_all(
                format!(
                    "{}\n",
                    json!({"id":1,"method":"search","params":{"query":query,"semantic":true}})
                )
                .as_bytes(),
            )
            .await?;
        while let Some(line) = process::line(&mut lines, 2 * 1024 * 1024).await? {
            let v: Value = serde_json::from_str(&line)?;
            if v["id"] == 1 {
                anyhow::ensure!(v["ok"] == true, "Lens could not resolve this request");
                return Ok(v["result"].clone());
            }
        }
        bail!("Lens disconnected")
    };
    tokio::time::timeout(Duration::from_secs(65), run)
        .await
        .context("Lens timed out")?
}

pub async fn hypr(kind: &str) -> Result<Value> {
    process::json("hyprctl", &args(&["-j", kind]), &Value::Null).await
}
async fn monitor_geometry() -> Result<Value> {
    let monitors = hypr("monitors").await?;
    Ok(json!(monitors.as_array().into_iter().flatten().map(|m|json!({"id":m["id"],"name":m["name"],"x":m["x"],"y":m["y"],"width":m["width"],"height":m["height"],"scale":m["scale"],"transform":m["transform"],"disabled":m["disabled"]})).collect::<Vec<_>>()))
}

fn name(v: &str) -> Result<&str> {
    anyhow::ensure!(
        !v.is_empty() && v != "." && v != ".." && !v.contains(['/', '\\', '\0']) && v.len() <= 200,
        "Choose a simple file name"
    );
    Ok(v)
}

impl Executor {
    pub fn known_objects(&self) -> Vec<Value> {
        let mut items = self.resources.iter().collect::<Vec<_>>();
        items.sort_by_key(|(id, _)| {
            std::cmp::Reverse(id.trim_start_matches('f').parse::<u64>().unwrap_or(0))
        });
        items
            .into_iter()
            .take(12)
            .map(|(id, r)| json!({"ref":id,"path":r.path}))
            .collect()
    }

    pub async fn approval_details(&self, tool: &str, args: &Value) -> Result<Value> {
        let mut details = args.clone();
        if tool == "terminal_run" {
            details["cwd"] = json!(self.directory(args["cwd"].as_str().unwrap_or("")).await?);
        }
        if matches!(tool, "files_trash" | "files_read" | "files_usage" | "files_list") {
            details["path"] = json!(self.resolve(args["ref"].as_str().unwrap_or("")).await?);
        }
        if tool.starts_with("ui_") {
            let screen = self.current_screen().await?;
            details["window_title"] = screen.window["title"].clone();
            if let Some(image) = screen.image {
                details["preview"] = json!(image);
            }
            if tool == "ui_action" {
                details["control"] = screen
                    .nodes
                    .as_array()
                    .into_iter()
                    .flatten()
                    .find(|n| n["id"] == args["node"])
                    .cloned()
                    .unwrap_or(Value::Null);
            }
        }
        Ok(details)
    }

    fn remember(&mut self, path: &Path) -> Result<Value> {
        anyhow::ensure!(
            !path
                .ancestors()
                .any(|p| std::fs::symlink_metadata(p).is_ok_and(|m| m.file_type().is_symlink())),
            "Symbolic links are not permitted"
        );
        let path = path.canonicalize().context("File is unavailable")?;
        let m = path.metadata()?;
        let existing = self
            .resources
            .iter()
            .find(|(_, r)| r.path == path)
            .map(|(k, _)| k.clone());
        let id = existing.unwrap_or_else(|| {
            self.next += 1;
            format!("f{}", self.next)
        });
        self.resources.insert(
            id.clone(),
            Resource {
                path: path.clone(),
                device: m.dev(),
                inode: m.ino(),
            },
        );
        Ok(
            json!({"ref":id,"name":path.file_name().unwrap_or_default().to_string_lossy(),"path":path,"directory":m.is_dir()}),
        )
    }
    pub fn selection(&mut self, paths: &[String]) -> Result<Vec<Value>> {
        paths
            .iter()
            .take(100)
            .map(|p| self.remember(Path::new(p)))
            .collect()
    }
    fn resource(&self, id: &str) -> Result<&Resource> {
        if let Some(resource) = self.resources.get(id) { return Ok(resource); }
        let path = Path::new(id);
        let mut known = self.resources.values().filter(|r| r.path == path
            || r.path.file_name().is_some_and(|name| name == id));
        let resource = known.next().context("Unknown file reference. List the selected folder or search for the file, then use its returned ref")?;
        anyhow::ensure!(known.next().is_none(), "Multiple known files have this name. Use a specific file ref");
        Ok(resource)
    }
    async fn resolve(&self, id: &str) -> Result<PathBuf> {
        if id == "desktop" {
            let data = process::output("xdg-user-dir", &args(&["DESKTOP"]), &[], 3, 4096).await?;
            let p = PathBuf::from(String::from_utf8(data)?.trim());
            anyhow::ensure!(
                p.is_absolute() && p.is_dir(),
                "Configure an existing desktop directory first"
            );
            let p = p.canonicalize()?;
            transaction::check(&p, true).await?;
            return Ok(p);
        }
        let r = self.resource(id)?;
        let m = r.path.metadata().context("File no longer exists")?;
        anyhow::ensure!(
            m.dev() == r.device && m.ino() == r.inode,
            "File was replaced; select it again"
        );
        anyhow::ensure!(r.path.canonicalize()? == r.path, "File location changed");
        transaction::check(&r.path, false).await?;
        Ok(r.path.clone())
    }
    async fn directory(&self, id: &str) -> Result<PathBuf> {
        let p = self.resolve(id).await?;
        anyhow::ensure!(p.is_dir(), "Expected a folder");
        Ok(p)
    }
    async fn script(&self, input: Value) -> Result<Value> {
        let result = process::json(
            "/usr/bin/python3",
            &[
                "-I".into(),
                crate::tool_script().to_string_lossy().into_owned(),
            ],
            &input,
        )
        .await?;
        if let Some(error) = result["error"].as_str() {
            bail!("{}", error);
        }
        Ok(result)
    }
    async fn current_screen(&self) -> Result<Screen> {
        let s = self
            .screen
            .as_ref()
            .context("Inspect the target window first")?;
        anyhow::ensure!(
            s.at.elapsed() < Duration::from_secs(120),
            "The screen snapshot expired; inspect again"
        );
        let current = hypr("activewindow").await?;
        anyhow::ensure!(
            monitor_geometry().await? == s.monitors,
            "Monitor configuration changed; inspect again"
        );
        for k in ["address", "at", "size", "pid"] {
            anyhow::ensure!(
                current[k] == s.window[k],
                "The target window changed; inspect again"
            );
        }
        Ok(s.clone())
    }
    pub fn prepare_control(&self, tool: &str, args: &Value) -> Result<Value> {
        let snapshot = self.screen.as_ref().context("Use ui_inspect on the target window first")?;
        anyhow::ensure!(snapshot.at.elapsed() < Duration::from_secs(120), "The inspection expired. Inspect the window again");
        let node = snapshot.nodes.as_array().and_then(|nodes| nodes.iter().find(|n| n["id"] == args["node"]))
            .context("Inspect the window and choose a returned node id")?;
        let mut details = json!({"window_title":snapshot.window["title"],"window":snapshot.window["address"],
            "pid":snapshot.window["pid"],"control":node});
        if tool == "ui_set_text" {
            anyhow::ensure!(node["editable"] == true, "Choose an editable field from the inspection");
            details["text"] = args["text"].clone();
        } else {
            let actions = node["actions"].as_array().context("Control has no actions")?;
            let action = match args["action"].as_str() {
                Some(name) => actions.iter().find(|a| a.as_str() == Some(name)),
                None if actions.len() == 1 => actions.first(),
                _ => None,
            }.context("Choose one of this control's named actions")?;
            details["action"] = action.clone();
        }
        Ok(details)
    }
    pub async fn apply_control(&mut self, tool: &str, details: &Value) -> Result<Value> {
        let snapshot = self.current_screen().await?;
        anyhow::ensure!(snapshot.window["address"] == details["window"] && snapshot.window["pid"] == details["pid"],
            "The approved window changed");
        let operation = if tool == "ui_set_text" { "set_text" } else { "action" };
        let request = json!({"operation":operation,"pid":details["pid"],"title":details["window_title"],
            "node":details["control"],"action":details["action"],"text":details["text"]});
        self.screen = None;
        let result = self.script(request).await?;
        anyhow::ensure!(result["accepted"] == true, "The application did not accept the change");
        Ok(json!({"accepted":true,"control":details["control"]["name"],"observe_next":"ui_inspect"}))
    }
    async fn snapshot(&mut self, vision: bool) -> Result<Value> {
        anyhow::ensure!(vision, "Choose a vision-capable model for screenshots");
        let w = hypr("activewindow").await?;
        let x = w["at"][0].as_i64().context("No focused window")?;
        let y = w["at"][1].as_i64().context("No focused window")?;
        let width = w["size"][0].as_i64().unwrap_or(0);
        let height = w["size"][1].as_i64().unwrap_or(0);
        anyhow::ensure!(
            width > 0 && height > 0 && width * height <= 32_000_000,
            "Invalid capture geometry"
        );
        let image = process::output(
            "grim",
            &[
                "-s".into(),
                "1".into(),
                "-g".into(),
                format!("{x},{y} {width}x{height}"),
                "-".into(),
            ],
            &[],
            10,
            16 * 1024 * 1024,
        )
        .await?;
        anyhow::ensure!(
            image.starts_with(b"\x89PNG\r\n\x1a\n") && image.len() > 24,
            "Invalid screenshot"
        );
        let iw = u32::from_be_bytes(image[16..20].try_into().unwrap()) as i64;
        let ih = u32::from_be_bytes(image[20..24].try_into().unwrap()) as i64;
        anyhow::ensure!(
            iw == width && ih == height,
            "Capture scale changed; inspect again"
        );
        let image = base64::engine::general_purpose::STANDARD.encode(image);
        self.screen = Some(Screen {
            image: Some(image.clone()),
            window: w.clone(),
            monitors: monitor_geometry().await?,
            at: Instant::now(),
            nodes: json!([]),
        });
        Ok(json!({"window":w["address"],"width":width,"height":height,"image":image}))
    }
    pub async fn prepare_change(&self, tool: &str, a: &Value, tx: &str) -> Result<Value> {
        let s = |k: &str| a[k].as_str().unwrap_or("");
        let (kind, args) = match tool {
            "files_write" => {
                let target = if a.get("ref").is_some() {
                    anyhow::ensure!(a.get("parent").is_none() && a.get("name").is_none(), "Use ref to edit, or parent and name to create a file");
                    let resource = self.resource(s("ref"))?;
                    json!({"target":self.resolve(s("ref")).await?, "device":resource.device, "inode":resource.inode})
                } else {
                    json!({"target":self.directory(s("parent")).await?.join(name(s("name"))?)})
                };
                let mut plan = transaction::call("prepare_write", json!({"transaction_id":tx,"file":target,"text":a["text"]})).await?;
                plan["path"] = target["target"].clone();
                return Ok(plan);
            }
            "files_mkdir" => (
                "mkdir",
                json!({"target":self.directory(s("parent")).await?.join(name(s("name"))?)}),
            ),
            "files_copy" | "files_move" => (
                if tool == "files_copy" { "copy" } else { "move" },
                json!({"source":self.resolve(s("ref")).await?,"target":self.directory(s("parent")).await?.join(name(s("name"))?)}),
            ),
            "files_trash" => ("trash", json!({"source":self.resolve(s("ref")).await?})),
            "files_zip" => {
                let mut paths = vec![];
                for id in a["sources"].as_array().context("Choose source files")? {
                    paths.push(self.resolve(id.as_str().unwrap_or("")).await?);
                }
                // Validate every descendant before handing sources to the archive helper.
                for path in &paths {
                    transaction::call("validate_tree", json!({"path":path})).await?;
                }
                let parent = self
                    .directory(if s("destination").is_empty() {
                        "desktop"
                    } else {
                        s("destination")
                    })
                    .await?;
                let base = if s("name").is_empty() {
                    "Archive"
                } else {
                    name(s("name"))?
                }
                .trim_end_matches(".zip");
                name(base)?;
                let target = (0..10000)
                    .map(|i| {
                        parent.join(if i == 0 {
                            format!("{base}.zip")
                        } else {
                            format!("{base} ({i}).zip")
                        })
                    })
                    .find(|p| !p.exists())
                    .context("No free archive name")?;
                let temp = tempfile::NamedTempFile::new()?;
                self.script(json!({"operation":"zip","paths":paths,"output":temp.path()}))
                    .await?;
                let mut plan = transaction::call("prepare_files", json!({"transaction_id":tx,"kind":"publish","args":{"source":temp.path(),"target":target}})).await?;
                plan["path"] = json!(target);
                return Ok(plan);
            }
            _ => bail!("This action has no verified rollback adapter and is blocked"),
        };
        let mut plan = transaction::call(
            "prepare_files",
            json!({"transaction_id":tx,"kind":kind,"args":args}),
        )
        .await?;
        if let Some(target) = args.get("target") {
            plan["path"] = target.clone();
        }
        Ok(plan)
    }

    pub async fn apply_change(&mut self, plan: &Value, tx: &str) -> Result<Value> {
        let mut result =
            transaction::call("apply", json!({"transaction_id":tx,"plan":plan["plan"]})).await?;
        if let Some(path) = plan["path"].as_str() {
            let reference = self.remember(Path::new(path))?;
            for (k, v) in reference.as_object().unwrap() {
                result[k] = v.clone();
            }
        }
        if let Some(diff) = plan["diff"].as_array() {
            let outputs: Vec<_> = diff.iter().filter(|change| change["change"] != "delete").take(32)
                .filter_map(|change| self.remember(Path::new(change["path"].as_str()?)).ok()).collect();
            if !outputs.is_empty() { result["outputs"] = json!(outputs); }
        }
        Ok(result)
    }

    pub async fn terminal_details(&self, a: &Value) -> Result<Value> {
        anyhow::ensure!(
            a["network"] != true,
            "Network access is prohibited for agent commands"
        );
        let modes = ["command", "code", "file"]
            .iter()
            .filter(|k| a.get(**k).is_some())
            .count();
        anyhow::ensure!(
            modes == 1,
            "Provide exactly one command, code body or script file"
        );
        let mut details = json!({"network":false,"isolated":true,"cwd":"/work","temporary":true});
        if let Some(inputs) = a["inputs"].as_array() {
            anyhow::ensure!(inputs.len() <= 32, "Choose up to 32 input files");
            let mut mounts = Vec::new();
            for (index, input) in inputs.iter().enumerate() {
                let id = input.as_str().context("Use an input file ref")?;
                let path = self.resolve(id).await?;
                let info = path.symlink_metadata()?;
                anyhow::ensure!(info.is_file() && info.nlink() == 1, "Choose an ordinary input file");
                mounts.push(json!({"path":path,"mount":format!("/inputs/{}",index+1),"device":info.dev(),
                    "inode":info.ino(),"mtime_ns":info.mtime() as i128 * 1_000_000_000 + info.mtime_nsec() as i128,
                    "ctime_ns":info.ctime() as i128 * 1_000_000_000 + info.ctime_nsec() as i128}));
            }
            details["inputs"] = json!(mounts);
        }
        if let Some(id) = a["cwd"].as_str().filter(|id| !id.is_empty()) {
            details["cwd"] = json!(self.directory(id).await?);
            details["temporary"] = json!(false);
        }
        if let Some(id) = a["file"].as_str() {
            let path = self.resolve(id).await?;
            let resource = self.resource(id)?;
            let language = match path.extension().and_then(|ext| ext.to_str()) {
                Some("py") => "python",
                Some("sh" | "bash") => "bash",
                Some("js" | "mjs" | "cjs") => "javascript",
                _ => bail!("Select a Python, Bash or JavaScript source file"),
            };
            let script = transaction::call(
                "read_script",
                json!({"path":path,"device":resource.device,"inode":resource.inode}),
            )
            .await?;
            details["code"] = script["code"].clone();
            details["language"] = json!(language);
            details["file"] = json!(path);
        } else if a.get("code").is_some() {
            anyhow::ensure!(a["language"].is_string(), "Choose a script language");
            details["language"] = a["language"].clone();
            details["code"] = a["code"].clone();
        } else {
            details["command"] = a["command"].clone();
        }
        let source = details["code"]
            .as_str()
            .or(details["command"].as_str())
            .unwrap_or("");
        anyhow::ensure!(
            !source.trim().is_empty()
                && source.len() <= 32768
                && !source.replace("\r\n", "\n").contains('\r')
                && !source
                    .chars()
                    .any(|c| (c.is_control() && !matches!(c, '\n' | '\t' | '\r'))
                        || matches!(c,'\u{061c}'|'\u{200e}'|'\u{200f}'|'\u{202a}'..='\u{202e}'|'\u{2066}'..='\u{2069}')),
            "Choose nonempty, reviewable command or script text (32 KiB maximum)"
        );
        let argv = match (details["command"].is_string(), details["language"].as_str()) {
            (true, _) => args(&["/bin/bash", "--noprofile", "--norc", "-c"]),
            (_, Some("python")) => args(&["/usr/bin/python3", "-I", "-"]),
            (_, Some("bash")) => args(&["/bin/bash", "--noprofile", "--norc", "-s"]),
            (_, Some("javascript"))
                if details["file"]
                    .as_str()
                    .is_some_and(|p| p.ends_with(".mjs")) =>
            {
                args(&["/usr/bin/node", "--input-type=module", "-"])
            }
            (_, Some("javascript")) => args(&["/usr/bin/node", "-"]),
            _ => bail!("Unsupported interpreter"),
        };
        details["interpreter"] = json!(argv[0]);
        details["argv"] = json!(argv);
        Ok(details)
    }

    pub async fn stage_terminal(
        &self,
        details: &Value,
        tx: &str,
    ) -> Result<(Option<Value>, i32, String)> {
        let stage = if details["temporary"] == true {
            Value::Null
        } else {
            transaction::call("stage", json!({"transaction_id":tx,"cwd":details["cwd"]})).await?
        };
        let mut command = args(&[
            "--die-with-parent",
            "--unshare-all",
            "--unshare-user",
            "--new-session",
            "--clearenv",
            "--cap-drop",
            "ALL",
            "--disable-userns",
            "--proc",
            "/proc",
            "--dev",
            "/dev",
            "--size",
            "134217728",
            "--tmpfs",
            "/tmp",
        ]);
        for p in ["/usr", "/bin", "/lib", "/lib64"] {
            if Path::new(p).exists() {
                command.extend(args(&["--ro-bind", p, p]));
            }
        }
        let mut input_snapshot = None;
        if let Some(inputs) = details["inputs"].as_array().filter(|items| !items.is_empty()) {
            let snapshot = transaction::call("snapshot_inputs",json!({"transaction_id":tx,"inputs":inputs})).await?;
            command.extend(args(&["--ro-bind",snapshot["path"].as_str().context("Missing inputs")?,"/inputs"]));
            input_snapshot = Some(snapshot["stage"].clone());
        }
        let ld_cache = "/etc/ld.so.cache";
        if Path::new(ld_cache).exists() {
            command.extend(args(&["--ro-bind", ld_cache, ld_cache]));
        }
        if !stage.is_null() {
            let work = stage["path"].as_str().context("No isolated working copy")?;
            command.extend(args(&[
                "--bind",
                work,
                details["cwd"].as_str().context("No working folder")?,
                "--bind",
                work,
                "/work",
            ]));
        } else {
            command.extend(args(&["--size", "134217728", "--tmpfs", "/work"]));
        }
        command.extend(args(&["--chdir","/work","--setenv","HOME","/work","--setenv","PATH","/usr/bin:/bin","--","/usr/bin/python3","-I","-c","import os,resource,sys; os.dup2(1,2); resource.setrlimit(resource.RLIMIT_CPU,(60,60)); resource.setrlimit(resource.RLIMIT_FSIZE,(2147483648,2147483648)); resource.setrlimit(resource.RLIMIT_NOFILE,(256,256)); resource.setrlimit(resource.RLIMIT_NPROC,(64,64)); resource.setrlimit(resource.RLIMIT_AS,(2147483648,2147483648)); os.execv(sys.argv[1],sys.argv[1:])"]));
        command.extend(serde_json::from_value::<Vec<String>>(
            details["argv"].clone(),
        )?);
        if let Some(shell) = details["command"].as_str() {
            command.push(shell.into());
        }
        let input = details["code"].as_str().unwrap_or("").as_bytes();
        let execution = process::output_status("bwrap", &command, input, 60, 128 * 1024);
        tokio::pin!(execution);
        let (status, output) = loop {
            tokio::select! {
                result = &mut execution => break result?,
                _ = tokio::time::sleep(Duration::from_millis(250)) => { transaction::call("budget", json!({"transaction_id":tx})).await?; }
            }
        };
        let stdout = String::from_utf8_lossy(&output).into_owned();
        if let Some(stage) = input_snapshot {
            transaction::call("discard_stage",json!({"transaction_id":tx,"stage":stage})).await?;
        }
        let exit_code = status.code().unwrap_or(-1);
        if stage.is_null() {
            return Ok((None, exit_code, stdout));
        }
        if !status.success() {
            transaction::call("discard_stage", json!({"transaction_id":tx,"stage":stage["stage"]})).await?;
            return Ok((None, exit_code, stdout));
        }
        let plan = transaction::call(
            "prepare_stage",
            json!({"transaction_id":tx,"stage":stage["stage"]}),
        )
        .await?;
        Ok((Some(plan), exit_code, stdout))
    }

    async fn search_hits(&mut self, result: &Value) -> Result<Vec<Value>> {
        let paths: Vec<_> = result["results"]
            .as_array()
            .into_iter()
            .flatten()
            .take(12)
            .filter_map(|h| h["path"].as_str())
            .collect();
        let allowed = transaction::call("check_paths", json!({"paths":paths})).await?;
        let mut hits = vec![];
        for h in result["results"].as_array().into_iter().flatten().take(12) {
            if h["kind"] == "app" {
                continue;
            }
            if let Some(p) = h["path"].as_str() {
                if !allowed["paths"]
                    .as_array()
                    .is_some_and(|paths| paths.iter().any(|v| v.as_str() == Some(p)))
                {
                    continue;
                }
                if let Ok(mut r) = self.remember(Path::new(p)) {
                    // Index excerpts may predate the current file/path permissions.
                    // Contents must pass the guarded descriptor read separately.
                    if h["score"].is_number() {
                        r["relevance"] = h["score"].clone();
                    }
                    hits.push(r);
                }
            }
        }
        Ok(hits)
    }

    pub async fn execute(&mut self, tool: &str, a: &Value, ctx: &DesktopContext) -> Result<Value> {
        anyhow::ensure!(!ctx.locked, "Desktop is locked");
        let s = |k: &str| a[k].as_str().unwrap_or("");
        anyhow::ensure!(
            matches!(
                tool,
                "search"
                    | "files_choose"
                    | "files_read"
                    | "files_list"
                    | "files_usage"
                    | "system_status"
                    | "apps_list"
                    | "ui_inspect"
                    | "ui_screenshot"
            ),
            "This action has no verified rollback adapter and is blocked"
        );
        match tool {
            "search" => {
                let folder = s("kind") == "folder";
                if ctx.scoped_search(a) {
                    let mut matches = vec![];
                    let mut partial = false;
                    for root in ctx.trusted_read_folders.iter().take(16) {
                        let data = transaction::call("lookup_name", json!({"query":s("query"),"kind":s("kind"),"root":root})).await;
                        match data {
                            Ok(value) => {
                                partial |= value["partial"] == true;
                                matches.extend(value["results"].as_array().into_iter().flatten().cloned());
                            }
                            Err(_) => partial = true,
                        }
                    }
                    matches.sort_by(|a,b| a["path"].as_str().cmp(&b["path"].as_str()));
                    matches.dedup();
                    matches.truncate(12);
                    let hits = self.search_hits(&json!({"results":matches})).await?;
                    return Ok(json!({"results":hits,"source":"trusted folders","partial":partial,"untrusted":true}));
                }
                if !folder {
                    if let Ok(index) = search_lens(s("query")).await {
                        let hits = self.search_hits(&index).await?;
                        if !hits.is_empty() {
                            return Ok(json!({"results":hits,"source":"lens","untrusted":true}));
                        }
                    }
                }
                let local =
                    transaction::call("lookup_name", json!({"query":s("query"),"kind":s("kind")}))
                        .await?;
                let hits = self.search_hits(&local).await?;
                Ok(
                    json!({"results":hits,"source":"filesystem","partial":local["partial"],"untrusted":true}),
                )
            }
            "files_list" => {
                let folder = self.directory(s("ref")).await?;
                let meta = folder.metadata()?;
                let listing = transaction::call("list_directory", json!({"path":folder,"device":meta.dev(),"inode":meta.ino(),"after":s("after")})).await?;
                let entries: Vec<_> = listing["entries"].as_array().context("No directory listing")?.iter()
                    .filter_map(|item| self.remember(&folder.join(item.as_str()?)).ok()).collect();
                Ok(json!({"folder":folder,"entries":entries,"next_cursor":listing["next_cursor"],"untrusted":true}))
            }
            "files_usage" => {
                let reference = s("ref");
                let path = self.directory(reference).await?;
                let (device, inode) = if let Some(resource) = self.resources.get(reference) {
                    (resource.device, resource.inode)
                } else {
                    let info = path.symlink_metadata()?;
                    (info.dev(), info.ino())
                };
                transaction::call(
                    "folder_usage",
                    json!({"path":path,"device":device,"inode":inode}),
                )
                .await
            }
            "files_choose" => {
                let options = if s("kind") == "folder" {
                    args(&["--getexistingdirectory", "."])
                } else {
                    args(&[
                        "--getopenfilename",
                        ".",
                        "*",
                        "--multiple",
                        "--separate-output",
                    ])
                };
                let data = match process::output("kdialog", &options, &[], 300, 65536).await {
                    Ok(data) => data,
                    Err(error)
                        if error
                            .downcast_ref::<process::ProcessExit>()
                            .is_some_and(|e| e.0.code() == Some(1)) =>
                    {
                        return Err(SelectionCancelled.into())
                    }
                    Err(error) => {
                        return Err(error
                            .context("File picker failed; check KDialog or select files again"))
                    }
                };
                let paths = String::from_utf8(data)?
                    .lines()
                    .map(str::to_owned)
                    .collect::<Vec<_>>();
                Ok(json!({"files":self.selection(&paths)?}))
            }
            "files_read" => {
                let path = self.resolve(s("ref")).await?;
                let resource = self.resource(s("ref"))?;
                transaction::call(
                    "read_file",
                    json!({"path":path,"device":resource.device,"inode":resource.inode,"offset":a["offset"].as_u64().unwrap_or(0), "page":a.get("page")}),
                )
                .await
            }
            "system_status" => crate::desktop::status(s("topic")).await,
            "apps_list" => crate::desktop::apps(ctx, s("query"), a["offset"].as_u64().unwrap_or(0) as usize).await,
            "ui_screenshot" => self.snapshot(ctx.profile.vision).await,
            "ui_inspect" => {
                let w = hypr("activewindow").await?;
                match self
                    .script(json!({"operation":"inspect","pid":w["pid"],"title":w["title"]}))
                    .await
                {
                    Ok(tree) if tree["nodes"].as_array().is_some_and(|n| !n.is_empty()) => {
                        self.screen = Some(Screen {
                            image: None,
                            window: w,
                            monitors: monitor_geometry().await?,
                            at: Instant::now(),
                            nodes: tree["nodes"].clone(),
                        });
                        Ok(tree)
                    }
                    _ => self.snapshot(ctx.profile.vision).await,
                }
            }
            _ => bail!("Unknown tool"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tools_reject_extra_fields_and_invalid_types() {
        let tools = registry();
        let t = tools.iter().find(|t| t.name == "workspace_focus").unwrap();
        assert!(t.validate(&json!({"number":3})).is_ok());
        for v in [
            json!({"number":"3"}),
            json!({"number":-1}),
            json!({"number":3,"command":"evil"}),
        ] {
            assert!(t.validate(&v).is_err());
        }
    }
    #[test]
    fn names_cannot_escape_parent() {
        for s in ["../x", "/tmp/x", ".", "..", "a/b"] {
            assert!(name(s).is_err());
        }
        assert!(name("архив #1").is_ok());
    }
    #[tokio::test]
    async fn replaced_resource_requires_reselection() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("f");
        std::fs::write(&p, "old").unwrap();
        let mut e = Executor::default();
        let r = e.remember(&p).unwrap();
        std::fs::rename(&p, dir.path().join("old")).unwrap();
        std::fs::write(&p, "new").unwrap();
        assert!(e.resolve(r["ref"].as_str().unwrap()).await.is_err());
    }
}

/// Coarse routing is based only on the user's text, never retrieved instructions.
pub fn relevant_groups(text: &str) -> Vec<String> {
    let q = text.to_lowercase();
    let mut groups = Vec::new();
    for (group, words) in [
        (
            "files",
            vec![
                "файл",
                "папк",
                "проект",
                "архив",
                "зип",
                "найд",
                "file",
                "folder",
                "project",
                "zip",
                "search",
                "find ",
                "read ",
            ],
        ),
        (
            "desktop",
            vec![
                "откр",
                "запуст",
                "окн",
                "прилож",
                "десктоп",
                "оформ",
                "громкост",
                "яркост",
                "батаре",
                "open",
                "launch",
                "workspace",
                "application",
                "window",
                "preset",
                "volume",
                "brightness",
                "battery",
            ],
        ),
        (
            "terminal",
            vec![
                "терминал",
                "команд",
                "собер",
                "скрипт",
                "terminal",
                "command",
                "build",
                "script",
            ],
        ),
        (
            "ui",
            vec![
                "нажм",
                "клик",
                "кнопк",
                "слайд",
                "экран",
                "введ",
                "click",
                "button",
                "slide",
                "screen",
                "type",
            ],
        ),
    ] {
        if words.iter().any(|w| q.contains(w)) {
            groups.push(group.into());
        }
    }
    if !groups.iter().any(|g| g == "desktop") && q.split(|c: char| !c.is_alphabetic()).any(|word|
        matches!(word, "app" | "apps" | "стол" | "стола" | "столе" | "столу" | "столом" | "столы" | "столов"
            | "столам" | "столами" | "столах" | "тема" | "темы" | "тему" | "темой" | "теме")) {
        groups.push("desktop".into());
    }
    if groups.iter().any(|g| g == "files")
        && ![
            "рабоч",
            "стол",
            "десктоп",
            "окн",
            "оформ",
            "window",
            "workspace",
            "preset",
            "app",
            "прилож",
        ]
        .iter()
        .any(|w| q.contains(w))
    {
        groups.retain(|g| g != "desktop");
    }
    // “on the desktop” is a ZIP destination, not a request to control windows.
    if groups.iter().any(|g| g == "files")
        && ["zip", "зип", "архив"].iter().any(|w| q.contains(w))
        && !["окн", "workspace", "прилож"].iter().any(|w| q.contains(w))
    {
        groups.retain(|g| g != "desktop");
    }
    groups
}
pub fn group(name: &str) -> &'static str {
    if name == "search" || name.starts_with("files_") {
        "files"
    } else if name.starts_with("ui_") {
        "ui"
    } else if name.starts_with("terminal_") {
        "terminal"
    } else {
        "desktop"
    }
}
pub fn summary(tool: &str, result: &Value) -> String {
    if result["awaiting_window"] == true {
        return format!("Запуск {} запрошен. Окно пока не появилось. Можно проверить ещё раз.", result["application"].as_str().unwrap_or(""));
    }
    if let Some(windows) = result["needs_selection"].as_array() {
        let prompt = if let Some(name) = result["identify_application"].as_str() {
            format!("Какое из появившихся окон относится к {name}?")
        } else { "Найдено несколько окон. Укажите нужное:".to_owned() };
        return format!(
            "{prompt}\n{}",
            windows
                .iter()
                .map(|w| format!(
                    "• {} ({})",
                    w["title"].as_str().unwrap_or("Окно"),
                    w["address"].as_str().unwrap_or("")
                ))
                .collect::<Vec<_>>()
                .join("\n")
        );
    }
    match tool {
        "terminal_run" => {
            let code = result["exit_code"].as_i64().unwrap_or(-1);
            let output = result["stdout"].as_str().unwrap_or("").trim_end();
            let mut text = format!("Код завершения: {code}.");
            if !output.is_empty() {
                text.push_str("\n\n");
                text.push_str(output);
            }
            if result["stdout_truncated"] == true {
                text.push_str("\n…");
            }
            text
        }
        "files_zip" => format!("Архив создан: {}", result["path"].as_str().unwrap_or("")),
        "workspace_focus" => format!("Открыт рабочий стол №{}.", result["workspace"]),
        "app_open" | "window_move" => {
            if let Some(n) = result["workspace"].as_i64() {
                format!("Окно открыто на рабочем столе №{n}.")
            } else {
                "Окно открыто.".into()
            }
        }
        _ => format!("Выполнено: {result}"),
    }
}
