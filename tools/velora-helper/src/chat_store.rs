//! Sidebar chat JSONL storage, including import of pre-conversation history.
use anyhow::{bail, ensure, Context, Result};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io::{BufRead, Write},
    os::unix::fs::DirBuilderExt,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

fn write(path: &Path, bytes: &[u8]) -> Result<()> {
    let dir = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(dir)?;
    let mut tmp = tempfile::Builder::new().prefix(".chat-").tempfile_in(dir)?;
    tmp.write_all(bytes)?;
    tmp.as_file().sync_all()?;
    tmp.persist(path)?;
    File::open(dir)?.sync_all()?;
    Ok(())
}
fn read(p: &Path) -> Result<Value> {
    Ok(serde_json::from_reader(File::open(p)?)?)
}
fn text<'a>(v: &'a Value, key: &str) -> &'a str {
    v[key].as_str().unwrap_or_default()
}
fn shortened(v: &Value, key: &str, limit: usize) -> String {
    text(v, key).chars().take(limit).collect()
}
fn list(v: &Value) -> impl Iterator<Item = &Value> {
    v.as_array().into_iter().flatten()
}

fn clean(messages: &Value) -> Result<Vec<Value>> {
    let items = messages.as_array().context("Invalid chat messages")?;
    Ok(items.iter().enumerate().filter_map(|(i,m)|{
        let role=text(m,"role");
        if !matches!(role,"user"|"assistant"){return None;}
        let content=m.get("text").or_else(||m.get("rawContent")).map_or(Some(""),Value::as_str)?;
        let mut out=json!({"uid":m["uid"].as_str().filter(|s|!s.is_empty()).map(str::to_owned).unwrap_or_else(||format!("message-{i}")),
            "role":role,"text":content,"model":text(m,"model"),"status":m["status"].as_str().unwrap_or("done"),
            "truncated":m["truncated"]==true,"hasActions":m["hasActions"]==true || m["functionCall"].as_object().is_some_and(|o|!o.is_empty()),
            "contextExcluded":m["contextExcluded"]==true || m["functionCall"]["name"]=="remote_context",
            "attachments":list(&m["attachments"]).filter_map(Value::as_str).collect::<Vec<_>>(),
            "steps":list(&m["steps"]).filter(|s|s.is_object()).map(|s|json!({"label":text(s,"label"),"path":text(s,"path")})).collect::<Vec<_>>(),
            "error":text(m,"error"),"rollbackAvailable":m["rollbackAvailable"]==true,
            "conflicts":list(&m["conflicts"]).filter_map(Value::as_str).take(1000).collect::<Vec<_>>(),
            "changes":list(&m["changes"]).filter(|c|c.is_object()).take(1000).map(|c|json!({"path":text(c,"path"),"change":text(c,"change")})).collect::<Vec<_>>()});
        for (key,n) in [("submissionId",100),("transactionId",100),("transactionState",40)]{out[key]=json!(shortened(m,key,n));}
        Some(out)
    }).collect())
}

struct Store {
    root: PathBuf,
}
impl Store {
    fn path(&self, id: &str) -> Result<PathBuf> {
        ensure!(
            !id.is_empty()
                && id.len() <= 100
                && id
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-'),
            "Invalid chat identifier"
        );
        Ok(self.root.join(format!("{id}.json")))
    }
    fn save(&self, chat: &Value) -> Result<Value> {
        let path = self.path(text(chat, "id"))?;
        let now = json!(SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis() as u64);
        let value = json!({"version":2,"id":chat["id"],"title":shortened(chat,"title",200),"createdAt":chat.get("createdAt").unwrap_or(&now),
            "updatedAt":chat.get("updatedAt").unwrap_or(&now),"mode":if chat["mode"]=="assistant"{"assistant"}else{"chat"},
            "model":text(chat,"model"),"draft":text(chat,"draft"),"messages":clean(chat.get("messages").unwrap_or(&json!([])))?});
        write(&path, &serde_json::to_vec(&value)?)?;
        Ok(chat["id"].clone())
    }
    fn load(&self, id: &str) -> Result<Value> {
        let mut chat = read(&self.path(id)?)?;
        ensure!(
            matches!(chat["version"].as_u64(), Some(1 | 2)),
            "Unsupported chat version"
        );
        let mut msgs = clean(chat.get("messages").unwrap_or(&json!([])))?;
        for m in &mut msgs {
            if matches!(
                text(m, "status"),
                "preparing" | "streaming" | "waiting" | "approval" | "rolling_back"
            ) {
                m["status"] = json!("interrupted");
            }
        }
        chat["messages"] = Value::Array(msgs);
        Ok(chat)
    }
    fn migrate(&self) -> Result<()> {
        let marker = self.root.join(".imported.json");
        // Two shell instances may list during the first import. Serialize marker updates.
        let guard = File::open(&self.root)?;
        rustix::fs::flock(&guard, rustix::fs::FlockOperation::LockExclusive)?;
        let mut imported: Vec<String> = if marker.exists() {
            serde_json::from_reader(File::open(&marker)?)?
        } else {
            vec![]
        };
        let mut paths = fs::read_dir(self.root.parent().unwrap())?
            .filter_map(Result::ok)
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|e| e == "json"))
            .collect::<Vec<_>>();
        paths.sort();
        for path in paths {
            let name = path.file_name().unwrap().to_string_lossy();
            if imported.iter().any(|n| *n == name) {
                continue;
            }
            let Ok(messages) = read(&path).and_then(|v| clean(&v)) else {
                continue;
            };
            let digest = format!("{:x}", Sha256::digest(name.as_bytes()));
            let id = format!("legacy-{}", &digest[..24]);
            if !self.path(&id)?.exists() {
                let t = path
                    .metadata()?
                    .modified()?
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis() as u64;
                self.save(&json!({"id":id,"title":path.file_stem().unwrap_or_default().to_string_lossy(),"createdAt":t,"updatedAt":t,"messages":messages}))?;
            }
            imported.push(name.into_owned());
            write(&marker, &serde_json::to_vec(&imported)?)?;
        }
        Ok(())
    }
    fn dispatch(&self, r: &Value) -> Result<Value> {
        let d = &r["params"];
        let id = text(d, "id");
        match text(r, "method") {
            "list" => {
                self.migrate()?;
                let query = gio::glib::casefold(text(d, "query").trim());
                let mut result = Vec::new();
                for entry in fs::read_dir(&self.root)? {
                    let path = entry?.path();
                    if path.extension().is_none_or(|e| e != "json") {
                        continue;
                    }
                    let Ok(chat) = read(&path) else { continue };
                    if !matches!(chat["version"].as_u64(), Some(1 | 2))
                        || !chat["messages"].is_array()
                    {
                        continue;
                    }
                    if !query.is_empty()
                        && !gio::glib::casefold(text(&chat, "title")).contains(query.as_str())
                        && !list(&chat["messages"]).any(|m| {
                            m.get("text")
                                .or_else(|| m.get("rawContent"))
                                .and_then(Value::as_str)
                                .is_some_and(|s| gio::glib::casefold(s).contains(query.as_str()))
                        })
                    {
                        continue;
                    }
                    let mut summary = json!({});
                    for key in ["id", "title", "createdAt", "updatedAt", "mode", "model"] {
                        summary[key] = chat[key].clone();
                    }
                    result.push(summary);
                }
                result.sort_by(|a, b| {
                    b["updatedAt"]
                        .as_f64()
                        .unwrap_or_default()
                        .total_cmp(&a["updatedAt"].as_f64().unwrap_or_default())
                });
                Ok(result.into())
            }
            "save" => self.save(d),
            "load" => self.load(id),
            "delete" => {
                match fs::remove_file(self.path(id)?) {
                    Ok(()) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => return Err(e.into()),
                };
                Ok(json!(true))
            }
            "rename" => {
                let mut v = self.load(id)?;
                v["title"] = json!(text(d, "title").trim());
                self.save(&v)
            }
            "export" => {
                let chat = self.load(id)?;
                let mut body = format!("# {}", text(&chat, "title"));
                for m in list(&chat["messages"]) {
                    body.push_str(&format!(
                        "\n\n## {}\n\n{}",
                        if m["role"] == "user" {
                            "User"
                        } else {
                            "Velora"
                        },
                        text(m, "text")
                    ));
                }
                body.push('\n');
                write(Path::new(text(d, "path")), body.as_bytes())?;
                Ok(json!(true))
            }
            "write" => {
                write(
                    Path::new(text(d, "path")),
                    d["text"].as_str().context("missing text")?.as_bytes(),
                )?;
                Ok(json!(true))
            }
            "files" => {
                let mut paths = vec![];
                for n in list(&d["paths"]) {
                    let p = Path::new(n.as_str().context("Invalid path")?);
                    ensure!(
                        p.is_absolute() && p.is_file(),
                        "Choose an existing local file"
                    );
                    paths.push(p);
                }
                Ok(json!(paths))
            }
            _ => bail!("Unknown chat storage operation"),
        }
    }
}
pub fn run(argv: Vec<String>) -> Result<()> {
    ensure!(argv.len() == 1, "chat-store needs a chat directory");
    let store = Store {
        root: Path::new(&argv[0]).join("conversations"),
    };
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&store.root)?;
    for line in std::io::stdin().lock().lines() {
        let msg = line?;
        let mut id = Value::Null;
        let result = serde_json::from_str::<Value>(&msg)
            .map_err(anyhow::Error::from)
            .and_then(|r| {
                id = r.get("id").context("missing request id")?.clone();
                store.dispatch(&r)
            });
        let reply = match result {
            Ok(v) => json!({"id":id,"ok":true,"result":v}),
            Err(e) => json!({"id":id,"ok":false,"error":e.to_string()}),
        };
        println!("{reply}");
    }
    Ok(())
}
