use super::{address, app_matches, clients, output, window_info, App};
use anyhow::{bail, ensure, Context, Result};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::time::{Duration, Instant};

#[derive(Default)]
pub struct Launches(HashMap<String, Launch>);

#[derive(PartialEq, Eq, Hash)]
struct Window {
    address: String,
    pid: u64,
    class: String,
}

impl Window {
    fn from_client(w: &Value) -> Option<Self> {
        Some(Self {
            address: address(w).ok()?.to_owned(),
            pid: w["pid"].as_u64()?,
            class: w["class"].as_str()?.to_owned(),
        })
    }
}

struct Launch {
    before: HashSet<Window>,
    token: String,
    pid: Option<(u64, u64)>,
    initial_title: Option<String>,
    started: Instant,
    confirmed: Option<Window>,
}

fn start_time(pid: u64) -> Option<u64> {
    let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    stat.rsplit_once(')')?
        .1
        .split_whitespace()
        .nth(19)?
        .parse()
        .ok()
}

impl Launch {
    fn pending(&self) -> bool {
        self.confirmed.is_none() && self.started.elapsed() < Duration::from_secs(120)
    }

    fn matches(&self, client: &Value, window: &Window) -> bool {
        if let Some(confirmed) = &self.confirmed {
            return confirmed == window;
        }
        if self.before.contains(window) {
            return false;
        }
        if self.initial_title.as_ref().is_some_and(|title| {
            ["initialTitle", "title"]
                .iter()
                .any(|k| client[*k].as_str() == Some(title.as_str()))
        }) {
            return true;
        }
        if self
            .pid
            .is_some_and(|(pid, ticks)| pid == window.pid && start_time(pid) == Some(ticks))
        {
            return true;
        }
        // Forwarding launchers can fork before a window maps. Only the exact marker
        // is used; process environments never leave the executor.
        let Ok(file) = std::fs::File::open(format!("/proc/{}/environ", window.pid)) else {
            return false;
        };
        let mut data = Vec::new();
        file.take(256 * 1024).read_to_end(&mut data).is_ok()
            && data
                .split(|b| *b == 0)
                .any(|var| var == self.token.as_bytes())
    }
}

impl Launches {
    pub(super) fn matches(&self, app: &App, client: &Value) -> bool {
        app_matches(app, client)
            || self.0.get(&app.id).is_some_and(|launch| {
                Window::from_client(client).is_some_and(|window| launch.matches(client, &window))
            })
    }

    pub(super) fn confirm(&mut self, app: &App, client: &Value) {
        if let Some(launch) = self.0.get_mut(&app.id) {
            launch.confirmed = Window::from_client(client);
            launch.before.clear();
        }
    }

    pub(super) async fn locate_or_start(
        &mut self,
        app: &App,
        terminal: &str,
        check_only: bool,
    ) -> Result<Value> {
        let before = clients().await?;
        let matches: Vec<_> = before.iter().filter(|w| self.matches(app, w)).collect();
        if !matches.is_empty() {
            return Ok(window_or_choice(&matches));
        }
        if !check_only && !self.0.get(&app.id).is_some_and(Launch::pending) {
            let response = output(
                &crate::helper(),
                &["apps", "open-tracked", &app.id, terminal],
            )
            .await?;
            let receipt: Value = serde_json::from_str(&response)
                .context("Invalid response from the desktop launcher")?;
            if let Some(error) = receipt["error"].as_str() {
                bail!("{error}");
            }
            let token = receipt["token"]
                .as_str()
                .context("Missing launch identifier")?;
            ensure!(
                token.len() == 36 && token.bytes().all(|b| b == b'-' || b.is_ascii_hexdigit()),
                "Invalid launch identifier"
            );
            let pid = receipt["pid"]
                .as_u64()
                .and_then(|pid| Some((pid, start_time(pid)?)));
            self.0.insert(
                app.id.clone(),
                Launch {
                    before: before.iter().filter_map(Window::from_client).collect(),
                    token: format!("VELORA_LAUNCH_ID={token}"),
                    pid,
                    initial_title: receipt["initial_title"].as_str().map(str::to_owned),
                    started: Instant::now(),
                    confirmed: None,
                },
            );
        }
        // Slow applications can map well after their launcher exits.
        let started = Instant::now();
        let deadline = started + Duration::from_secs(if check_only { 2 } else { 25 });
        loop {
            let windows = clients().await?;
            let matches: Vec<_> = windows.iter().filter(|w| self.matches(app, w)).collect();
            if !matches.is_empty() {
                return Ok(window_or_choice(&matches));
            }
            if Instant::now() >= deadline {
                let new: Vec<_> = windows
                    .iter()
                    .filter(|w| {
                        self.0.get(&app.id).is_some_and(|launch| {
                            Window::from_client(w).is_some_and(|key| !launch.before.contains(&key))
                        })
                    })
                    .collect();
                if !new.is_empty() {
                    return Ok(
                        json!({"identify_application":app.name, "needs_selection":new.iter().take(24).map(|w| window_info(w)).collect::<Vec<_>>()}),
                    );
                }
                return Ok(json!({"awaiting_window":true,"application":app.name}));
            }
            let interval = if started.elapsed() < Duration::from_secs(2) {
                120
            } else {
                450
            };
            tokio::time::sleep(Duration::from_millis(interval)).await;
        }
    }
}

fn window_or_choice(matches: &[&Value]) -> Value {
    if let [window] = matches {
        window_info(window)
    } else {
        json!({"needs_selection":matches.iter().map(|w|window_info(w)).collect::<Vec<_>>()})
    }
}
