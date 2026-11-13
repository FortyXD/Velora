//! Provider adapters normalize calls before the executor ever sees them.
use crate::{process, Profile};
use anyhow::{bail, Context, Result};
use serde_json::{json, Value};
use std::{collections::BTreeMap, ffi::OsString, path::PathBuf, time::Duration};
use tokio::{
    io::{AsyncWriteExt, BufReader},
    process::Command,
    sync::mpsc,
};

#[derive(Default)]
pub struct ModelProvider {
    runtime: tokio::sync::Mutex<Option<process::Running>>,
}
impl ModelProvider {
    pub async fn prepare(&self, profile: &Profile, policy: u8, battery: bool) -> Result<()> {
        validate(profile, policy)?;
        // Custom endpoints are user-managed. Only the standard loopback backend is
        // started here, and only after an explicit request/probe/download.
        if profile.provider != "ollama"
            || !matches!(
                profile.endpoint.trim_end_matches('/'),
                "http://127.0.0.1:11434" | "http://localhost:11434"
            )
        {
            return Ok(());
        }
        if tokio::net::TcpStream::connect("127.0.0.1:11434")
            .await
            .is_ok()
        {
            return Ok(());
        }
        let mut runtime = self.runtime.lock().await;
        if runtime.is_none() {
            let mut cmd = Command::new("ollama");
            cmd.arg("serve")
                .env("OLLAMA_HOST", "127.0.0.1:11434")
                .env("OLLAMA_NO_CLOUD", "1")
                .env("OLLAMA_NOPRUNE", "1")
                .env("OLLAMA_NUM_PARALLEL", "1")
                .env("OLLAMA_MAX_LOADED_MODELS", "1");
            let directories = std::env::var_os("HOME")
                .map(|home| PathBuf::from(home).join(".ollama/models"))
                .into_iter()
                .chain([
                    PathBuf::from("/var/lib/ollama"),
                    PathBuf::from("/usr/share/ollama/.ollama/models"),
                ]);
            if let Some(directory) =
                ollama_models_directory(std::env::var_os("OLLAMA_MODELS"), directories)
            {
                cmd.env("OLLAMA_MODELS", directory);
            }
            if battery || !profile.gpu {
                cmd.env("CUDA_VISIBLE_DEVICES", "-1")
                    .env("ROCR_VISIBLE_DEVICES", "-1")
                    .env("OLLAMA_VULKAN", "0");
            }
            let mut child =
                process::spawn(&mut cmd).context("Install Ollama from Assistant settings first")?;
            child.stdin.take();
            if let Some(mut stdout) = child.stdout.take() {
                tokio::spawn(async move {
                    let _ = tokio::io::copy(&mut stdout, &mut tokio::io::sink()).await;
                });
            }
            *runtime = Some(child);
        }
        for _ in 0..40 {
            if tokio::net::TcpStream::connect("127.0.0.1:11434")
                .await
                .is_ok()
            {
                return Ok(());
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        *runtime = None;
        bail!("Ollama could not start; check its installation and endpoint")
    }
    pub async fn stop(&self) {
        *self.runtime.lock().await = None;
    }
}

// Keep store precedence aligned with the sidebar launcher and model catalogue.
fn ollama_models_directory(
    configured: Option<OsString>,
    directories: impl IntoIterator<Item = PathBuf>,
) -> Option<PathBuf> {
    configured
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| {
            directories
                .into_iter()
                .find(|directory| directory.join("manifests").is_dir())
        })
}

/// All shell processes share this lease; no second generation runs concurrently.
struct GenerationLease(std::fs::File);
impl GenerationLease {
    fn acquire() -> Result<Self> {
        use std::os::{
            fd::AsRawFd,
            unix::fs::{MetadataExt, OpenOptionsExt},
        };
        let runtime = std::path::PathBuf::from(
            std::env::var_os("XDG_RUNTIME_DIR").context("No desktop runtime directory")?,
        );
        let path = runtime.join("velora-agent-generation.lock");
        let file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(path)?;
        anyhow::ensure!(
            file.metadata()?.uid() == unsafe { libc::geteuid() },
            "Invalid generation lock owner"
        );
        anyhow::ensure!(
            unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0,
            "Another assistant request is generating; wait or stop it first"
        );
        Ok(Self(file))
    }
}
impl Drop for GenerationLease {
    fn drop(&mut self) {
        use std::os::fd::AsRawFd;
        unsafe {
            libc::flock(self.0.as_raw_fd(), libc::LOCK_UN);
        }
    }
}

#[derive(Clone, Debug)]
pub struct Call {
    pub id: String,
    pub name: String,
    pub args: Value,
}
#[derive(Default)]
pub struct Reply {
    pub text: String,
    pub calls: Vec<Call>,
    pub parts: Vec<Value>,
    pub truncated: bool,
}

// Parse the authority, not a substring: localhost.evil and user@localhost are remote.
pub fn local_endpoint(endpoint: &str) -> bool {
    let Some((scheme, rest)) = endpoint.split_once("://") else {
        return false;
    };
    if !matches!(scheme, "http" | "https") {
        return false;
    }
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    if authority.contains('@') {
        return false;
    }
    let (host, port) = if let Some(rest) = authority.strip_prefix('[') {
        let Some((host, suffix)) = rest.split_once(']') else {
            return false;
        };
        if !suffix.is_empty() && !suffix.starts_with(':') {
            return false;
        }
        (host, suffix.strip_prefix(':').unwrap_or(""))
    } else {
        authority.split_once(':').unwrap_or((authority, ""))
    };
    if !port.is_empty() && port.parse::<u16>().is_err() {
        return false;
    }
    host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|ip| ip.is_loopback())
}

pub fn validate(profile: &Profile, policy: u8) -> Result<()> {
    anyhow::ensure!(policy != 0, "AI is disabled");
    anyhow::ensure!(
        matches!(profile.provider.as_str(), "ollama" | "openai" | "gemini"),
        "Unsupported provider"
    );
    anyhow::ensure!(
        !profile.model.ends_with(":cloud") && !profile.model.ends_with("-cloud"),
        "Cloud models must use an explicitly configured remote provider"
    );
    anyhow::ensure!(
        !profile.model.is_empty() && profile.model.len() <= 256,
        "Choose a model"
    );
    anyhow::ensure!(
        !profile.endpoint.chars().any(char::is_control),
        "Invalid endpoint"
    );
    anyhow::ensure!(
        profile.endpoint.starts_with("https://") || local_endpoint(&profile.endpoint),
        "Remote endpoints require HTTPS"
    );
    anyhow::ensure!(
        policy != 2 || local_endpoint(&profile.endpoint),
        "Local-only policy prevents this connection"
    );
    anyhow::ensure!(
        !profile.key.chars().any(char::is_control),
        "Invalid API key"
    );
    Ok(())
}

fn quote(value: &str) -> String {
    format!(
        "\"{}\"",
        value
            .replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('\n', "\\n")
            .replace('\r', "\\r")
            .replace('\t', "\\t")
    )
}

pub fn request_config(profile: &Profile, path: &str, body: Option<&Value>) -> String {
    let endpoint = if path.is_empty() && profile.provider == "gemini" {
        let model = profile
            .model
            .bytes()
            .map(|b| {
                if b.is_ascii_alphanumeric() || b"-_.".contains(&b) {
                    (b as char).to_string()
                } else {
                    format!("%{b:02X}")
                }
            })
            .collect::<String>();
        if profile.endpoint.contains(":streamGenerateContent") {
            profile.endpoint.replace("{model}", &model)
        } else {
            format!(
                "{}/models/{model}:streamGenerateContent?alt=sse",
                profile.endpoint.trim_end_matches('/')
            )
        }
    } else if path.is_empty() {
        profile.endpoint.clone()
    } else {
        format!("{}{}", profile.endpoint.trim_end_matches('/'), path)
    };
    let mut config = format!(
        "url = {}\nheader = \"Content-Type: application/json\"\n",
        quote(&endpoint)
    );
    if local_endpoint(&endpoint) {
        config.push_str("noproxy = \"*\"\n");
    }
    if !profile.key.is_empty() {
        let header = if profile.provider == "gemini" {
            format!("x-goog-api-key: {}", profile.key)
        } else {
            format!("Authorization: Bearer {}", profile.key)
        };
        config.push_str(&format!("header = {}\n", quote(&header)));
    }
    if let Some(body) = body {
        config.push_str(&format!("data = {}\n", quote(&body.to_string())));
    }
    config
}

pub async fn http(profile: &Profile, path: &str, body: Option<&Value>) -> Result<Value> {
    let data = process::output(
        "curl",
        &process::args(&[
            "--disable",
            "--silent",
            "--write-out",
            "\n%{http_code}",
            "--proto",
            "=http,https",
            "--connect-timeout",
            "8",
            "--max-time",
            "60",
            "--config",
            "-",
        ]),
        request_config(profile, path, body).as_bytes(),
        65,
        2 * 1024 * 1024,
    )
    .await
    .context("Could not reach the model provider; check that Ollama is running and the endpoint is correct")?;
    http_response(profile, path, &data)
}

fn http_response(profile: &Profile, path: &str, data: &[u8]) -> Result<Value> {
    let split = data
        .iter()
        .rposition(|b| *b == b'\n')
        .context("Provider returned no HTTP status")?;
    let status: u16 = std::str::from_utf8(&data[split + 1..])?
        .trim()
        .parse()
        .context("Provider returned an invalid HTTP status")?;
    // Do not expose response bodies: a proxy or provider can echo credentials or prompts.
    if profile.provider == "ollama" && path == "/api/show" && status == 404 {
        bail!("Ollama model '{}' is not installed on this server. Choose an installed model in the model picker or download it in Settings → AI → Desktop actions.", profile.model);
    }
    anyhow::ensure!(
        (200..300).contains(&status),
        "Model provider returned HTTP {status}; check the endpoint, model and access settings"
    );
    let value: Value =
        serde_json::from_slice(&data[..split]).context("Provider returned invalid JSON")?;
    anyhow::ensure!(
        value.get("error").is_none(),
        "The model provider rejected the request"
    );
    Ok(value)
}

pub fn body(
    profile: &Profile,
    messages: &[Value],
    tools: &[Value],
    battery: bool,
    extended: bool,
) -> Value {
    let output = if extended { 2048 } else { 1024 };
    if profile.provider == "gemini" {
        let contents: Vec<_> = messages.iter().filter(|m| m["role"] != "system").map(|m| {
            let mut parts = Vec::new();
            if let Some(original)=m["gemini_parts"].as_array() {return json!({"role":"model","parts":original});}
            if m["role"] == "tool" {
                parts.push(json!({"functionResponse":{"name":m["name"],"response":{"result":m["content"]}}}));
            } else {
                if let Some(t) = m["content"].as_str().filter(|t| !t.is_empty()) { parts.push(json!({"text":t})); }
                for c in m["tool_calls"].as_array().into_iter().flatten() {
                    let arguments: Value = serde_json::from_str(c["function"]["arguments"].as_str().unwrap_or("{}")).unwrap_or(json!({}));
                    parts.push(json!({"functionCall":{"name":c["function"]["name"],"args":arguments}}));
                }
            }
            for image in m["images"].as_array().into_iter().flatten() { parts.push(json!({"inlineData":{"mimeType":"image/png","data":image}})); }
            json!({"role":if m["role"]=="assistant" {"model"} else {"user"},"parts":parts})
        }).collect();
        return json!({"systemInstruction":{"parts":[{"text":messages.first().and_then(|v|v["content"].as_str()).unwrap_or("")}]},"contents":contents,"tools":[{"functionDeclarations":tools.iter().map(|t|t["function"].clone()).collect::<Vec<_>>()}],"generationConfig":{"maxOutputTokens":output,"temperature":0.1}});
    }
    let mapped: Vec<_> = messages.iter().map(|m| {
        let mut m = m.clone();
        m.as_object_mut().unwrap().remove("gemini_parts");
        m.as_object_mut().unwrap().remove("observation");
        if profile.provider == "ollama" {
            if let Some(calls) = m["tool_calls"].as_array_mut() {
                for c in calls { if let Some(s)=c["function"]["arguments"].as_str() { c["function"]["arguments"] = serde_json::from_str(s).unwrap_or(json!({})); } }
            }
            if m["role"] == "tool" { m["tool_name"] = m["name"].clone(); }
        } else if let Some(images) = m.as_object_mut().and_then(|v| v.remove("images")) {
            let mut parts = vec![json!({"type":"text","text":m["content"]})];
            for image in images.as_array().into_iter().flatten().filter_map(Value::as_str) {
                parts.push(json!({"type":"image_url","image_url":{"url":format!("data:image/png;base64,{image}")}}));
            }
            m["content"] = json!(parts);
        }
        m.as_object_mut().unwrap().remove("name");
        m
    }).collect();
    if profile.provider == "ollama" {
        json!({"model":profile.model,"messages":mapped,"tools":tools,"stream":true,"think":false,
            "keep_alive":if battery {"60s"} else {"5m"},
            "options":{"num_ctx":profile.context_tokens.clamp(4096,32768),"num_predict":output,"temperature":0.1,
                "num_gpu":if profile.gpu && !battery {-1} else {0},"num_thread":std::thread::available_parallelism().map_or(2,|n|n.get().clamp(1,4))}})
    } else {
        // Current reasoning models may reject temperature and the legacy token limit.
        let mut request =
            json!({"model":profile.model,"messages":mapped,"tools":tools,"stream":true});
        let limit = if profile.endpoint.starts_with("https://api.openai.com/") {
            "max_completion_tokens"
        } else {
            "max_tokens"
        };
        request[limit] = json!(output);
        request
    }
}

#[derive(Default)]
pub struct Decoder {
    pub text: String,
    calls: BTreeMap<usize, (String, String, String)>,
    parts: Vec<Value>,
    truncated: bool,
}
impl Decoder {
    pub fn feed(&mut self, value: &Value, format: &str) -> Result<String> {
        anyhow::ensure!(
            value.get("error").is_none(),
            "The model provider rejected the request"
        );
        self.truncated |= value["choices"][0]["finish_reason"] == "length"
            || value["candidates"][0]["finishReason"] == "MAX_TOKENS"
            || value["done_reason"] == "length";
        let mut delta = String::new();
        if format == "gemini" {
            for part in value["candidates"][0]["content"]["parts"]
                .as_array()
                .into_iter()
                .flatten()
            {
                self.parts.push(part.clone());
                if part["thought"] == true {
                    continue;
                }
                if let Some(t) = part["text"].as_str() {
                    delta.push_str(t);
                }
                if let Some(c) = part.get("functionCall") {
                    let i = self.calls.len();
                    anyhow::ensure!(i < 16, "Too many tool calls");
                    self.calls.insert(
                        i,
                        (
                            format!("call_{i}"),
                            c["name"].as_str().unwrap_or("").into(),
                            c["args"].to_string(),
                        ),
                    );
                }
            }
        } else {
            let message = if format == "ollama" {
                &value["message"]
            } else {
                if value["choices"][0]["delta"].is_object() {
                    &value["choices"][0]["delta"]
                } else {
                    &value["choices"][0]["message"]
                }
            };
            delta.push_str(message["content"].as_str().unwrap_or(""));
            for (index, c) in message["tool_calls"]
                .as_array()
                .into_iter()
                .flatten()
                .enumerate()
            {
                let i = c["index"].as_u64().unwrap_or(index as u64) as usize;
                anyhow::ensure!(i < 16, "Too many tool calls");
                let entry = self
                    .calls
                    .entry(i)
                    .or_insert_with(|| (format!("call_{i}"), String::new(), String::new()));
                if let Some(id) = c["id"].as_str() {
                    entry.0 = id.into();
                }
                if let Some(name) = c["function"]["name"].as_str() {
                    entry.1.push_str(name);
                }
                let arguments = &c["function"]["arguments"];
                if let Some(s) = arguments.as_str() {
                    entry.2.push_str(s);
                } else if arguments.is_object() {
                    entry.2 = arguments.to_string();
                }
                anyhow::ensure!(entry.2.len() <= 65536, "Tool arguments are too large");
            }
        }
        self.text.push_str(&delta);
        anyhow::ensure!(self.text.len() <= 128 * 1024, "Model response is too large");
        Ok(delta)
    }
    pub fn finish(self) -> Result<Reply> {
        // A partial answer is still useful, but a partial action is never executable,
        // even when its arguments happen to form valid JSON before the limit.
        anyhow::ensure!(
            !self.truncated || self.calls.is_empty(),
            "Model reached its output limit before completing a tool call"
        );
        let mut calls = vec![];
        for (_, (id, name, arguments)) in self.calls {
            anyhow::ensure!(!name.is_empty(), "Incomplete tool call");
            let args =
                serde_json::from_str(&arguments).context("Incomplete or invalid tool arguments")?;
            calls.push(Call { id, name, args });
        }
        Ok(Reply {
            text: self.text,
            calls,
            parts: self.parts,
            truncated: self.truncated,
        })
    }
}

fn generation_timeout(profile: &Profile, battery: bool, extended: bool) -> u64 {
    if profile.provider == "ollama" && local_endpoint(&profile.endpoint) {
        if battery || !profile.gpu {
            if extended {
                1200
            } else {
                600
            }
        } else {
            300
        }
    } else {
        180
    }
}

pub async fn generate(
    profile: &Profile,
    messages: &[Value],
    tools: &[Value],
    battery: bool,
    extended: bool,
    events: &mpsc::Sender<Value>,
    task: u64,
) -> Result<Reply> {
    let _lease = GenerationLease::acquire()?;
    let path = if profile.provider == "ollama" {
        "/api/chat"
    } else {
        ""
    };
    let body = body(profile, messages, tools, battery, extended);
    // Secrets and prompts are written only to stdin, never argv, a file or a log.
    let config = request_config(profile, path, Some(&body));
    let seconds = generation_timeout(profile, battery, extended);
    let mut cmd = Command::new("curl");
    cmd.args([
        "--disable",
        "--silent",
        "--fail",
        "--no-buffer",
        "--proto",
        "=http,https",
        "--connect-timeout",
        "8",
        "--max-time",
        &seconds.to_string(),
        "--config",
        "-",
    ]);
    let mut child = process::spawn(&mut cmd)?;
    let mut input = child.stdin.take().context("Missing provider pipe")?;
    input.write_all(config.as_bytes()).await?;
    input.shutdown().await?;
    drop(input);
    let mut lines = BufReader::new(child.stdout.take().context("Missing provider output")?);
    let run = async {
        let mut decoder = Decoder::default();
        let mut received = 0usize;
        let mut complete = false;
        let mut generating = false;
        loop {
            // CPU model loading/prompt evaluation can be slow. Once the stream
            // starts, a stalled connection must still fail promptly.
            let idle = if received == 0 { seconds.min(300) } else { 60 };
            let Some(line) = tokio::time::timeout(
                Duration::from_secs(idle),
                process::line(&mut lines, 256 * 1024),
            )
            .await
            .context("The model stopped responding; try a smaller local model or send again")??
            else {
                break;
            };
            received += line.len();
            anyhow::ensure!(received <= 2 * 1024 * 1024, "Provider output is too large");
            let line = line.strip_prefix("data:").unwrap_or(&line).trim();
            if line == "[DONE]" {
                complete = true;
                continue;
            }
            if line.is_empty() || line.starts_with(':') || line.starts_with("event:") {
                continue;
            }
            let value: Value = serde_json::from_str(line).context("Invalid provider stream")?;
            complete |= value["done"] == true
                || value["choices"][0]["finish_reason"].is_string()
                || value["candidates"][0]["finishReason"].is_string();
            let delta = decoder.feed(&value, &profile.provider)?;
            if !generating && (!delta.is_empty() || !decoder.calls.is_empty()) {
                generating = true;
                let _ = events
                    .send(json!({"type":"phase","task":task,"phase":"generating"}))
                    .await;
            }
            if !delta.is_empty() {
                let _ = events
                    .send(json!({"type":"delta","task":task,"text":delta}))
                    .await;
            }
        }
        let status = child.wait().await?;
        anyhow::ensure!(
            status.code() != Some(28),
            "Model request timed out; try a smaller model or shorten the request"
        );
        anyhow::ensure!(
            status.success(),
            "Model request failed; check the endpoint, model and key"
        );
        anyhow::ensure!(
            complete,
            "Provider disconnected before completing the response"
        );
        decoder.finish()
    };
    tokio::time::timeout(Duration::from_secs(seconds + 5), run)
        .await
        .context("Model request timed out")?
}

pub async fn probe(profile: &Profile) -> Result<Value> {
    if profile.provider == "ollama" {
        let result = ollama_capabilities(profile).await?;
        anyhow::ensure!(
            result["tools"] == true,
            "This model does not advertise tool support"
        );
        Ok(result)
    } else {
        let (tx, mut rx) = mpsc::channel(256);
        let drain = tokio::spawn(async move { while rx.recv().await.is_some() {} });
        let tool = json!({"type":"function","function":{"name":"connection_check","description":"Verify tool calling","parameters":{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"],"additionalProperties":false}}});
        let reply=generate(profile,&[json!({"role":"system","content":"Call connection_check with ok=true. Do not answer in text."}),json!({"role":"user","content":"Check connection"})],&[tool],true,false,&tx,0).await;
        drop(tx);
        let _ = drain.await;
        let reply = reply?;
        anyhow::ensure!(
            reply
                .calls
                .iter()
                .any(|c| c.name == "connection_check" && c.args["ok"] == true),
            "This model did not return a valid structured call"
        );
        Ok(json!({"tools":true,"vision":profile.vision}))
    }
}

pub async fn ollama_capabilities(profile: &Profile) -> Result<Value> {
    let result = http(profile, "/api/show", Some(&json!({"model":profile.model}))).await?;
    anyhow::ensure!(
        result["remote_model"].as_str().is_none_or(str::is_empty)
            && result["remote_host"].as_str().is_none_or(str::is_empty),
        "Configure cloud models through an explicit remote provider"
    );
    let capabilities = result["capabilities"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    Ok(json!({"tools":capabilities.iter().any(|v|v=="tools"),
        "vision":capabilities.iter().any(|v|v=="vision"),"details":result["details"]}))
}

pub async fn pull(profile: &Profile, events: &mpsc::Sender<Value>, task: u64) -> Result<()> {
    anyhow::ensure!(
        profile.provider == "ollama" && local_endpoint(&profile.endpoint),
        "Download requires local Ollama"
    );
    let config = request_config(
        profile,
        "/api/pull",
        Some(&json!({"model":profile.model,"stream":true})),
    );
    let mut cmd = Command::new("curl");
    cmd.args([
        "--disable",
        "--silent",
        "--fail",
        "--no-buffer",
        "--max-time",
        "7200",
        "--config",
        "-",
    ]);
    let mut child = process::spawn(&mut cmd)?;
    let mut input = child.stdin.take().unwrap();
    input.write_all(config.as_bytes()).await?;
    drop(input);
    let mut lines = BufReader::new(child.stdout.take().unwrap());
    while let Some(line) = process::line(&mut lines, 256 * 1024).await? {
        anyhow::ensure!(line.len() < 65536, "Invalid download response");
        let v: Value = serde_json::from_str(&line)?;
        if v.get("error").is_some() {
            bail!("Model download failed");
        }
        let _=events.send(json!({"type":"download","task":task,"status":v["status"],"total":v["total"],"completed":v["completed"]})).await;
    }
    anyhow::ensure!(child.wait().await?.success(), "Model download failed");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn model_store_matches_catalogue_precedence() {
        let root = tempfile::tempdir().unwrap();
        let home = root.path().join("home");
        let system = root.path().join("system");
        let explicit = root.path().join("custom");
        let directories = || [home.clone(), system.clone()];
        assert_eq!(ollama_models_directory(None, directories()), None);
        std::fs::create_dir_all(system.join("manifests")).unwrap();
        assert_eq!(
            ollama_models_directory(None, directories()),
            Some(system.clone())
        );
        std::fs::create_dir_all(home.join("manifests")).unwrap();
        assert_eq!(
            ollama_models_directory(Some(OsString::new()), directories()),
            Some(home.clone())
        );
        // Even an empty or missing explicit store must not expose other stores.
        assert_eq!(
            ollama_models_directory(Some(explicit.clone().into_os_string()), directories()),
            Some(explicit)
        );
    }

    #[test]
    fn cloud_requests_use_supported_limits_and_default_sampling() {
        let mut profile = Profile {
            provider: "openai".into(),
            endpoint: "https://api.openai.com/v1/chat/completions".into(),
            ..Default::default()
        };
        let openai = body(
            &profile,
            &[json!({"role":"user","content":"hello"})],
            &[],
            false,
            true,
        );
        assert_eq!(openai["max_completion_tokens"], 2048);
        assert!(openai.get("max_tokens").is_none());
        assert!(openai.get("temperature").is_none());
        profile.endpoint = "https://api.anthropic.com/v1/chat/completions".into();
        let compatible = body(&profile, &[], &[], false, false);
        assert_eq!(compatible["max_tokens"], 1024);
        assert!(compatible.get("temperature").is_none());
    }
    #[test]
    fn cpu_generation_has_time_for_loading_and_preserves_cpu_only_options() {
        let mut profile = Profile::default();
        assert_eq!(generation_timeout(&profile, false, false), 600);
        assert_eq!(generation_timeout(&profile, false, true), 1200);
        let request = body(&profile, &[], &[], false, false);
        assert_eq!(request["options"]["num_gpu"], 0);
        assert_eq!(request["options"]["num_predict"], 1024);
        profile.gpu = true;
        assert_eq!(generation_timeout(&profile, false, false), 300);
        assert_eq!(generation_timeout(&profile, true, false), 600);
        assert_eq!(
            body(&profile, &[], &[], true, false)["options"]["num_gpu"],
            0
        );
        profile.endpoint = "https://example.invalid".into();
        assert_eq!(generation_timeout(&profile, true, false), 180);
    }
    #[test]
    fn output_limit_preserves_text_but_never_exposes_partial_tools() {
        for format in ["ollama", "openai", "gemini"] {
            let (answer, call) = match format {
                "ollama" => (
                    json!({"message":{"content":"Useful partial answer"},"done":true,"done_reason":"length"}),
                    json!({"message":{"tool_calls":[{"function":{"name":"files_zip","arguments":{"sources":["f1"]}}}]},"done":true,"done_reason":"length"}),
                ),
                "openai" => (
                    json!({"choices":[{"delta":{"content":"Useful partial answer"},"finish_reason":"length"}]}),
                    json!({"choices":[{"delta":{"tool_calls":[{"function":{"name":"files_zip","arguments":"{\"sources\":[\"f1\"]}"}}]},"finish_reason":"length"}]}),
                ),
                _ => (
                    json!({"candidates":[{"content":{"parts":[{"text":"Useful partial answer"}]},"finishReason":"MAX_TOKENS"}]}),
                    json!({"candidates":[{"content":{"parts":[{"functionCall":{"name":"files_zip","args":{"sources":["f1"]}}}]},"finishReason":"MAX_TOKENS"}]}),
                ),
            };
            let mut decoder = Decoder::default();
            decoder.feed(&answer, format).unwrap();
            let reply = decoder.finish().unwrap();
            assert!(reply.truncated);
            assert_eq!(reply.text, "Useful partial answer");
            let mut decoder = Decoder::default();
            decoder.feed(&call, format).unwrap();
            assert!(decoder.finish().is_err());
        }
    }
    #[test]
    fn local_policy_checks_authority() {
        for good in [
            "http://localhost:11434",
            "http://127.0.0.1/v1",
            "http://[::1]:8080",
        ] {
            assert!(local_endpoint(good));
        }
        for bad in [
            "http://localhost.evil",
            "http://localhost@evil",
            "http://evil/localhost",
            "file:///tmp/a",
            "http://[::1]evil",
        ] {
            assert!(!local_endpoint(bad), "{bad}");
        }
    }
    #[test]
    fn fragmented_parallel_calls_are_only_parsed_when_complete() {
        let mut d = Decoder::default();
        d.feed(&json!({"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"files_zip","arguments":"{\"sources\":"}},{"index":1,"id":"b","function":{"name":"workspace_focus","arguments":"{\"number\":"}}]}}]}),"openai").unwrap();
        d.feed(&json!({"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"[\"f1\"]}"}},{"index":1,"function":{"arguments":"3}"}}]}}]}),"openai").unwrap();
        let r = d.finish().unwrap();
        assert_eq!(r.calls.len(), 2);
        assert_eq!(r.calls[1].args["number"], 3);
    }
    #[test]
    fn invalid_arguments_never_become_calls() {
        let mut d = Decoder::default();
        d.feed(
            &json!({"message":{"tool_calls":[{"function":{"name":"files_zip","arguments":"{"}}]}}),
            "ollama",
        )
        .unwrap();
        assert!(d.finish().is_err());
    }
    #[test]
    fn credentials_and_data_cannot_add_curl_options() {
        let p = Profile {
            key: "secret\"\\data".into(),
            ..Default::default()
        };
        let s = request_config(
            &p,
            "/api/chat",
            Some(&json!({"text":"a\nurl = file:///etc/passwd"})),
        );
        assert_eq!(s.lines().count(), 5);
        assert!(s.contains("\\\""));
    }
}
