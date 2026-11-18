use super::control::{command, Options, Owner};
use anyhow::{bail, ensure, Context, Result};
use serde_json::{json, Value};

pub async fn sources() -> Result<Vec<Value>> {
    let value: Value =
        serde_json::from_str(&command("pactl", &["--format=json", "list", "sources"]).await?)?;
    value.as_array().context("Unexpected source list")?.iter().map(|v|{
        let name=v["name"].as_str().context("Missing source name")?;
        let sink=&v["monitor_of_sink"];
        Ok(json!({"value":name,"displayName":v["description"].as_str().filter(|s|!s.is_empty()).unwrap_or(name),
            "monitor":name.ends_with(".monitor")||!sink.is_null()&&*sink!=4294967295u64&&*sink!="4294967295"}))
    }).collect()
}

pub async fn source(opts: &Options, kind: &str) -> Result<Option<String>> {
    if kind == "none" {
        return Ok(None);
    }
    let system = kind == "system";
    let mut name = if system {
        opts.system.clone()
    } else {
        opts.mic.clone()
    };
    if name.is_empty() {
        name = if system {
            format!("{}.monitor", command("pactl", &["get-default-sink"]).await?)
        } else {
            command("pactl", &["get-default-source"]).await?
        };
    }
    ensure!(
        sources()
            .await?
            .iter()
            .any(|v| v["value"] == name && v["monitor"] == system),
        "Selected audio device is unavailable or has the wrong type: {name}"
    );
    Ok(Some(name))
}

async fn owned_modules(sink: &str) -> Result<Vec<(bool, u64)>> {
    let s = command("pactl", &["list", "short", "modules"]).await?;
    let mut records: Vec<(u64, String, String)> = vec![];
    for line in s.lines().filter(|l| !l.trim().is_empty()) {
        let mut parts = line.split('\t');
        let (id, name, arg) = (
            parts.next().and_then(|s| s.parse().ok()),
            parts.next(),
            parts.next(),
        );
        match (id, name, arg) {
            (Some(i), Some(name), Some(arg)) if !name.is_empty() => {
                records.push((i, name.into(), arg.into()))
            }
            _ if records.is_empty()
                || line
                    .split('\t')
                    .any(|s| matches!(s, "module-null-sink" | "module-loopback")) =>
            {
                bail!("Unexpected pactl module-list format; cannot safely clean audio mixer")
            }
            _ => {
                records.last_mut().unwrap().2.push('\n');
                records.last_mut().unwrap().2.push_str(line);
            }
        }
    }
    let mut result: Vec<_> = records
        .iter()
        .filter(|(_, name, args)| {
            matches!(name.as_str(), "module-null-sink" | "module-loopback")
                && args
                    .split_whitespace()
                    .filter_map(|a| a.split_once('='))
                    .any(|(k, v)| matches!(k, "sink_name" | "sink") && v == sink)
        })
        .map(|(id, name, _)| (name == "module-null-sink", *id))
        .collect();
    result.sort_by_key(|(null, id)| (*null, std::cmp::Reverse(*id)));
    Ok(result)
}

impl Owner {
    pub async fn mix(&mut self, options: &Options) -> Result<String> {
        let system = source(options, "system").await?.unwrap();
        let mic = source(options, "microphone").await?.unwrap();
        let previous = command("pactl", &["get-default-sink"]).await?;
        let tag = tempfile::NamedTempFile::new_in(&self.dir)?;
        let sink = format!(
            "velora_recording_{}_{}",
            std::process::id(),
            tag.path()
                .file_name()
                .unwrap()
                .to_string_lossy()
                .trim_start_matches('.')
        );
        self.state["mixerSink"] = json!(sink);
        self.persist()?;
        let id = command(
            "pactl",
            &[
                "load-module",
                "module-null-sink",
                &format!("sink_name={sink}"),
                "sink_properties=device.description=Velora-Recording device.class=filter",
            ],
        )
        .await?;
        self.state["modules"] = json!([id]);
        self.persist()?;
        if command("pactl", &["get-default-sink"]).await? == sink {
            command("pactl", &["set-default-sink", &previous]).await?;
        }
        for src in [system, mic] {
            let id = command(
                "pactl",
                &[
                    "load-module",
                    "module-loopback",
                    &format!("source={src}"),
                    &format!("sink={sink}"),
                    "source_dont_move=true",
                    "sink_dont_move=true",
                    "latency_msec=20",
                ],
            )
            .await?;
            self.state["modules"]
                .as_array_mut()
                .unwrap()
                .push(json!(id));
            self.persist()?;
        }
        Ok(format!("{sink}.monitor"))
    }
    pub async fn cleanup_audio(&mut self) -> Result<()> {
        let sink = self.state["mixerSink"].as_str().unwrap_or("");
        if sink.is_empty() {
            return Ok(());
        }
        for (_, id) in owned_modules(sink).await? {
            let _ = command("pactl", &["unload-module", &id.to_string()]).await;
        }
        ensure!(
            owned_modules(sink).await?.is_empty(),
            "Audio mixer cleanup failed; press Stop again to retry"
        );
        self.state["mixerSink"] = json!("");
        self.state["modules"] = json!([]);
        self.persist()
    }
}
