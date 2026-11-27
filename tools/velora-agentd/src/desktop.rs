//! Interactive desktop tools. Only the executor can construct host commands.
use crate::{process, tools::hypr, App, Context as DesktopContext};
use anyhow::{bail, ensure, Context, Result};
use serde_json::{json, Value};
use std::time::Duration;

mod launch;
pub use launch::Launches;

pub fn is_control(tool: &str) -> bool {
    matches!(
        tool,
        "desktop_adjust" | "app_open" | "workspace_focus" | "window_move"
    )
}

async fn output(program: &str, args: &[&str]) -> Result<String> {
    let bytes = process::output(program, &process::args(args), &[], 6, 512 * 1024)
        .await
        .with_context(|| format!("Could not read or apply {program} request"))?;
    Ok(String::from_utf8_lossy(&bytes).trim().to_owned())
}

async fn sample(program: &str, args: &[&str]) -> Value {
    match output(program, args).await {
        Ok(text) => {
            let lines: Vec<_> = text
                .lines()
                .take(16)
                .map(|s| s.chars().take(240).collect::<String>())
                .collect();
            json!({"available":true,"lines":lines,"truncated":text.lines().count()>16 || text.lines().take(16).any(|s|s.chars().count()>240)})
        }
        Err(_) => json!({"available":false}),
    }
}

pub async fn status(topic: &str) -> Result<Value> {
    let data = match topic {
        "failures" => {
            let (system, user, journal) = tokio::join!(
                sample("systemctl", &["list-units","--state=failed","--no-legend","--no-pager","--plain"]),
                sample("systemctl", &["--user","list-units","--state=failed","--no-legend","--no-pager","--plain"]),
                sample("journalctl", &["--boot","--priority=err","--lines=12","--no-pager","--output=short-iso"]),
            );
            json!({"failed_system_units":system,"failed_user_units":user,"recent_error_messages_this_boot":journal})
        }
        "storage" => sample("df", &["-h","-l","-x","tmpfs","-x","devtmpfs"]).await,
        "memory" => sample("free", &["-h"]).await,
        "processes" => sample("ps", &["-eo","pid,comm,%cpu,%mem","--sort=-pcpu"]).await,
        "network" => sample("nmcli", &["--colors","no","device","status"]).await,
        "power" => sample("upower", &["-i","/org/freedesktop/UPower/devices/DisplayDevice"]).await,
        "audio" => sample("wpctl", &["status"]).await,
        "displays" => json!(hypr("monitors").await?.as_array().context("No monitor information")?.iter()
            .map(|m|json!({"name":m["name"],"focused":m["focused"],"width":m["width"],"height":m["height"],"workspace":m["activeWorkspace"]["id"]})).collect::<Vec<_>>()),
        "workspaces" => hypr("workspaces").await?,
        _ => bail!("Unknown diagnostic topic"),
    };
    Ok(json!({"topic":topic,"observations":data,"untrusted":true}))
}

fn window_info(w: &Value) -> Value {
    json!({"address":w["address"],"pid":w["pid"],"class":w["class"],"title":w["title"].as_str().unwrap_or("").chars().take(120).collect::<String>(),
           "workspace":w["workspace"]["id"]})
}

fn app_key(value: &str) -> String {
    let mut key = value.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase();
    if key.ends_with(".desktop") {
        key.truncate(key.len() - ".desktop".len());
    }
    key
}

fn app_alias(key: &str) -> Option<&'static str> {
    match key {
        "vs code" | "vscode" | "code" | "visual studio code" | "visual-studio-code"
        | "com.microsoft.vscode" | "вс код" | "вс-код" | "вскод" | "ви эс код" => Some("vscode"),
        "firefox" | "mozilla firefox" | "org.mozilla.firefox"
        | "фаерфокс" | "фаирфокс" | "файрфокс" | "файерфокс" => Some("firefox"),
        _ => None,
    }
}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum AppMatch {
    Id,
    NameOrClass,
    Alias,
    Substring,
    Keywords,
}

fn match_query(app: &App, query: &str) -> Option<AppMatch> {
    if query.is_empty() {
        return Some(AppMatch::Substring);
    }
    let id = app_key(&app.id);
    if id == query {
        return Some(AppMatch::Id);
    }
    let name = app_key(&app.name);
    let class = app_key(&app.class);
    if name == query || class == query {
        return Some(AppMatch::NameOrClass);
    }
    let keys = [id, name, class];
    if let Some(alias) = app_alias(query) {
        if keys.iter().any(|k| app_alias(k) == Some(alias)) {
            return Some(AppMatch::Alias);
        }
    }
    if keys.iter().any(|k| k.contains(query)) {
        return Some(AppMatch::Substring);
    }
    let words: Vec<_> = keys[1].split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()).collect();
    let initials: String = words.iter().filter_map(|w| w.chars().next()).collect();
    let terms: Vec<_> = query.split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()).collect();
    ((words.len() >= 2 && initials == query)
        || (terms.len() >= 2 && terms.iter().all(|term| words.iter().any(|word| word.starts_with(term)))))
        .then_some(AppMatch::Keywords)
}

pub async fn apps(ctx: &DesktopContext, query: &str, offset: usize) -> Result<Value> {
    let query = app_key(query);
    let mut candidates: Vec<_> = ctx.apps.iter()
        .filter_map(|app| match_query(app, &query).map(|rank| (rank, app)))
        .collect();
    candidates.sort_by(|(rank, app), (other_rank, other)| (rank, &app.name, &app.id).cmp(&(other_rank, &other.name, &other.id)));
    let windows = clients().await.ok();
    let matching_windows: Vec<_> = windows.iter().flatten().filter(|w| {
        ["class", "initialClass", "title"].iter().any(|k|
            w[*k].as_str().is_some_and(|s| s.to_lowercase().contains(&query)))
            || candidates.iter().any(|(_, app)| app_matches(app, w))
    }).take(12).map(window_info).collect();
    let mut result = json!({
        "apps":candidates.iter().skip(offset).take(20).map(|(_,a)|json!({"id":a.id,"name":a.name})).collect::<Vec<_>>(),
        "total_matching_apps":candidates.len(),"windows":matching_windows,"windows_available":windows.is_some(),"untrusted":true
    });
    if offset.saturating_add(20) < candidates.len() {
        result["next_offset"] = json!(offset + 20);
    }
    if candidates.is_empty() && !ctx.apps.is_empty() && !query.is_empty() {
        result["next"] = json!("Search again using a shorter name or list apps without a query. Use a returned desktop ID.");
    }
    Ok(result)
}

fn app_matches(app: &App, w: &Value) -> bool {
    let id = app.id.trim_end_matches(".desktop");
    [w["class"].as_str(), w["initialClass"].as_str()]
        .into_iter()
        .flatten()
        .any(|class| {
            let key = app_key(class);
            let alias = app_alias(&key);
            !key.is_empty()
                && [
                    id,
                    id.rsplit('.').next().unwrap_or(id),
                    &app.class,
                    &app.name,
                ]
                .iter()
                .any(|s| {
                    let candidate = app_key(s);
                    key == candidate || (alias.is_some() && alias == app_alias(&candidate))
                })
        })
}

pub fn installed<'a>(ctx: &'a DesktopContext, query: &str) -> Result<&'a App> {
    if let Some(app) = ctx.apps.iter().find(|app| app.id == query && !query.is_empty()) {
        return Ok(app);
    }
    let query = app_key(query);
    let mut matches: Vec<_> = ctx.apps.iter()
        .filter_map(|app| {
            let rank = match_query(app, &query)?;
            (rank < AppMatch::Substring).then_some((rank, app))
        })
        .collect();
    matches.sort_by_key(|(rank, _)| *rank);
    let &(rank, first) = matches.first().context("No matching installed application. Use apps_list to find its desktop ID")?;
    ensure!(matches.get(1).is_none_or(|(next, _)| *next != rank),
        "Multiple installed applications match. Choose a specific desktop ID from apps_list");
    Ok(first)
}

async fn clients() -> Result<Vec<Value>> {
    hypr("clients")
        .await?
        .as_array()
        .cloned()
        .context("No window list")
}

fn address(w: &Value) -> Result<&str> {
    let addr = w["address"]
        .as_str()
        .context("Window address unavailable")?;
    ensure!(
        addr.strip_prefix("0x").is_some_and(|hex| !hex.is_empty()
            && hex.len() <= 16
            && hex.bytes().all(|c| c.is_ascii_hexdigit())),
        "Invalid window address"
    );
    Ok(addr)
}

async fn dispatch(expression: String) -> Result<()> {
    ensure!(
        output("hyprctl", &["dispatch", &expression])
            .await?
            .eq_ignore_ascii_case("ok"),
        "The compositor rejected this action"
    );
    Ok(())
}

async fn level(setting: &str, target: &str) -> Result<i64> {
    let value = if setting == "brightness" {
        output(
            "qs",
            &["-c", "ii", "ipc", "call", "brightness", "get", target],
        )
        .await?
        .parse::<i64>()?
    } else {
        let text = output("wpctl", &["get-volume", target]).await?;
        (text
            .strip_prefix("Volume:")
            .and_then(|s| s.split_whitespace().next())
            .context("No volume value")?
            .parse::<f64>()?
            * 100.)
            .round() as i64
    };
    ensure!(
        (0..=150).contains(&value),
        "The selected device is unavailable"
    );
    Ok(value)
}

async fn audio_sink() -> Result<String> {
    let info = output("wpctl", &["inspect", "@DEFAULT_AUDIO_SINK@"]).await?;
    let id = info
        .lines()
        .next()
        .and_then(|s| s.trim().strip_prefix("id "))
        .and_then(|s| s.split(',').next())
        .context("No default audio sink")?;
    Ok(id.trim().parse::<u32>()?.to_string())
}

pub async fn prepare(tool: &str, a: &Value, ctx: &DesktopContext, launches: &Launches, chosen: Option<&Value>) -> Result<Value> {
    match tool {
        "desktop_adjust" => {
            let setting = a["setting"]
                .as_str()
                .context("Choose brightness or volume")?;
            let target = if setting == "brightness" {
                hypr("monitors")
                    .await?
                    .as_array()
                    .into_iter()
                    .flatten()
                    .find(|m| m["focused"] == true)
                    .and_then(|m| m["name"].as_str())
                    .context("No focused monitor")?
                    .to_owned()
            } else {
                audio_sink().await?
            };
            let before = level(setting, &target).await?;
            let after = match (a["percent"].as_i64(), a["delta"].as_i64()) {
                (Some(value), None) => value,
                (None, Some(delta)) => (before + delta).clamp(0, 100),
                _ => bail!("Choose either a target percent or a relative change"),
            };
            Ok(json!({"setting":setting,"target":target,"before":before,"after":after}))
        }
        "workspace_focus" => Ok(json!({"workspace":a["number"]})),
        "window_move" => {
            let window = clients()
                .await?
                .into_iter()
                .find(|w| w["address"] == a["window"])
                .context("Window no longer exists")?;
            address(&window)?;
            Ok(json!({"window":window_info(&window),"workspace":a["number"]}))
        }
        "app_open" => {
            let app = installed(ctx, a["app_id"].as_str().unwrap_or(""))?;
            // A window identified by the user is bound to its PID, address and class.
            // An address supplied by the model still has to match the application.
            let mut matches: Vec<_> = if let Some(window) = chosen {
                vec![check_window(window).await?]
            } else {
                clients().await?.into_iter().filter(|w| launches.matches(app, w)).collect()
            };
            if let Some(target) = a["window"].as_str() {
                matches.retain(|w| w["address"] == target);
                ensure!(
                    matches.len() == 1,
                    "The selected application window changed"
                );
            } else if matches.len() > 1 {
                return Ok(
                    json!({"needs_selection":matches.iter().map(window_info).collect::<Vec<_>>()}),
                );
            }
            let window = matches.first();
            if let Some(w) = window {
                address(w)?;
            }
            Ok(
                json!({"app_id":app.id,"name":app.name,"workspace":a["workspace"],"window":window.map(window_info)}),
            )
        }
        _ => bail!("Unknown desktop control"),
    }
}

async fn check_window(expected: &Value) -> Result<Value> {
    clients()
        .await?
        .into_iter()
        .find(|w| {
            w["address"] == expected["address"]
                && w["pid"] == expected["pid"]
                && w["class"] == expected["class"]
        })
        .context("The approved window changed")
}

async fn place(window: &Value, workspace: Option<i64>, focus: bool) -> Result<Value> {
    let addr = address(window)?;
    let old = check_window(window).await?;
    if let Some(number) = workspace {
        if old["workspace"]["id"] != number {
            dispatch(format!("hl.dsp.window.move({{ workspace = \"{number}\", follow = false, window = \"address:{addr}\" }})")).await?;
        }
    }
    if focus {
        dispatch(format!("hl.dsp.focus({{ window = \"address:{addr}\" }})")).await?;
    }
    for _ in 0..12 {
        let current = check_window(window).await?;
        if workspace.is_none_or(|n| current["workspace"]["id"] == n)
            && (!focus || hypr("activewindow").await?["address"] == addr)
        {
            return Ok(
                json!({"verified":true,"window":addr,"workspace":current["workspace"]["id"]}),
            );
        }
        tokio::time::sleep(Duration::from_millis(80)).await;
    }
    bail!("Could not verify the requested window placement")
}

pub async fn apply(tool: &str, plan: &Value, ctx: &DesktopContext, launches: &mut Launches) -> Result<Value> {
    match tool {
        "desktop_adjust" => {
            let setting = plan["setting"].as_str().unwrap_or("");
            let target = plan["target"].as_str().context("Missing device")?;
            ensure!(
                level(setting, target).await? == plan["before"],
                "The level changed while awaiting approval"
            );
            let target_percent = plan["after"].as_i64().context("Missing level")?;
            if setting == "brightness" {
                output(
                    "qs",
                    &[
                        "-c",
                        "ii",
                        "ipc",
                        "call",
                        "brightness",
                        "set",
                        target,
                        &target_percent.to_string(),
                    ],
                )
                .await?;
            } else {
                output(
                    "wpctl",
                    &["set-volume", target, &format!("{target_percent}%")],
                )
                .await?;
            }
            for _ in 0..12 {
                if level(setting, target).await? == target_percent {
                    return Ok(
                        json!({"verified":true,"setting":setting,"target":target,"percent":target_percent}),
                    );
                }
                tokio::time::sleep(Duration::from_millis(80)).await;
            }
            bail!("Could not verify the requested level")
        }
        "workspace_focus" => {
            let n = plan["workspace"].as_i64().context("Missing workspace")?;
            dispatch(format!("hl.dsp.focus({{ workspace = \"{n}\" }})")).await?;
            let workspace = hypr("activeworkspace").await?;
            ensure!(
                workspace["id"] == n,
                "Could not verify the focused workspace"
            );
            Ok(json!({"workspace":n,"verified":true}))
        }
        "window_move" => place(&plan["window"], plan["workspace"].as_i64(), true).await,
        "app_open" => {
            let app = installed(ctx, plan["app_id"].as_str().unwrap_or(""))?;
            let window = if plan["window"].is_object() {
                plan["window"].clone()
            } else {
                launches.locate_or_start(app, &ctx.terminal_command, plan["check_only"] == true).await?
            };
            if window["needs_selection"].is_array() || window["awaiting_window"] == true { return Ok(window); }
            let mut result = place(&window, plan["workspace"].as_i64(), true).await?;
            launches.confirm(app, &window);
            result["app_id"] = json!(app.id);
            result["name"] = json!(app.name);
            Ok(result)
        }
        _ => bail!("Unknown desktop control"),
    }
}
