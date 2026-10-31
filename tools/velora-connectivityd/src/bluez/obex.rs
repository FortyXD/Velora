//! Files over Bluetooth, through BlueZ's obexd on the session bus. Incoming files land in obexd's own cache, the
//! only place it may write, and move to the chosen folder when complete, as in bluedevil.

use crate::prompts::{Answer, Prompts};
use crate::protocol::{ApiError, ErrorCode, Outgoing};
use crate::values::{self, Props};
use futures_util::StreamExt;
use serde::Deserialize;
use serde_json::json;
use std::collections::HashMap;
use std::num::NonZeroUsize;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use zbus::message::Type as MessageType;
use zbus::{interface, Connection, MatchRule, MessageStream, ObjectPath, OwnedObjectPath, OwnedVariant, Variant};

const BUS_NAME: &str = "org.bluez.obex";
const ROOT_PATH: &str = "/org/bluez/obex";
const IFACE_CLIENT: &str = "org.bluez.obex.Client1";
const IFACE_PUSH: &str = "org.bluez.obex.ObjectPush1";
const IFACE_TRANSFER: &str = "org.bluez.obex.Transfer1";
const IFACE_SESSION: &str = "org.bluez.obex.Session1";
pub const AGENT_PATH: &str = "/org/velora/bluetooth/obex";

/// More files within this time of the last one from a device needn't ask again, as a batch counts as one.
const BATCH_WINDOW: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ReceivePolicy {
    Ask,
    Trusted,
    Always,
}

#[derive(zbus::DBusError, Debug)]
#[zbus(prefix = "org.bluez.obex.Error")]
pub enum ObexError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Rejected(String),
    Canceled(String),
}

/// Whether a file can come in without asking.
pub fn auto_accept(policy: ReceivePolicy, trusted: bool, recently_accepted: bool) -> bool {
    recently_accepted || policy == ReceivePolicy::Always || (policy == ReceivePolicy::Trusted && trusted)
}

/// A name for what a device says its file is called, kept inside the receiving folder whatever it claims.
pub fn safe_file_name(name: &str) -> String {
    let base = name.rsplit(['/', '\\']).next().unwrap_or_default().trim_matches(|c: char| c.is_control() || c == ' ');
    let cleaned: String = base.chars().filter(|c| !c.is_control()).collect();
    if cleaned.is_empty() || cleaned == "." || cleaned == ".." {
        "received-file".to_string()
    } else {
        cleaned
    }
}

/// A path in `folder` that doesn't exist yet: `photo.jpg`, then `photo (1).jpg`.
pub fn unique_path(folder: &Path, name: &str) -> PathBuf {
    let candidate = folder.join(name);
    if !candidate.exists() {
        return candidate;
    }
    let path = Path::new(name);
    let stem = path.file_stem().map(|stem| stem.to_string_lossy().into_owned()).unwrap_or_else(|| name.to_string());
    let extension = path.extension().map(|extension| format!(".{}", extension.to_string_lossy())).unwrap_or_default();
    (1..).map(|number| folder.join(format!("{stem} ({number}){extension}"))).find(|candidate| !candidate.exists()).expect("some number is free")
}

fn cache_directory() -> PathBuf {
    let cache = std::env::var_os("XDG_CACHE_HOME").map_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".cache"), PathBuf::from);
    cache.join("obexd")
}

fn obex_error(failure: &zbus::Error) -> ApiError {
    match failure {
        zbus::Error::MethodError(name, message, _) => {
            let short = name.rsplit('.').next().unwrap_or_default();
            match short {
                "ServiceUnknown" | "NameHasNoOwner" => ApiError::new(ErrorCode::Unavailable, "File transfer over Bluetooth isn't installed"),
                _ => ApiError::new(ErrorCode::Failed, message.clone().unwrap_or_else(|| "The file couldn't be sent".to_string())),
            }
        }
        zbus::Error::FDO(inner) if matches!(**inner, zbus::fdo::Error::ServiceUnknown(_) | zbus::fdo::Error::NameHasNoOwner(_)) => ApiError::new(ErrorCode::Unavailable, "File transfer over Bluetooth isn't installed"),
        other => ApiError::new(ErrorCode::Failed, other.to_string()),
    }
}

#[derive(Clone)]
pub struct ReceiveSettings {
    pub policy: ReceivePolicy,
    pub folder: PathBuf,
}

/// An incoming file being received.
struct Incoming {
    temporary: PathBuf,
    name: String,
    device: String,
}

pub struct ObexShared {
    pub settings: Mutex<ReceiveSettings>,
    incoming: Mutex<HashMap<String, Incoming>>,
    accepted_at: Mutex<HashMap<String, Instant>>,
}

impl ObexShared {
    pub fn new(settings: ReceiveSettings) -> Arc<Self> {
        Arc::new(Self { settings: Mutex::new(settings), incoming: Mutex::default(), accepted_at: Mutex::default() })
    }
}

pub struct ObexAgent {
    pub session: Connection,
    pub system: Connection,
    pub prompts: Arc<Prompts>,
    pub shared: Arc<ObexShared>,
}

impl ObexAgent {
    async fn props(&self, path: &str, interface: &str) -> Props {
        let reply = self.session.call_method(Some(BUS_NAME), path, Some("org.freedesktop.DBus.Properties"), "GetAll", &(interface,)).await;
        reply.ok().and_then(|reply| reply.body().deserialize().ok()).unwrap_or_default()
    }

    /// The device a session is with, by asking BlueZ for what it knows of that address.
    async fn device_props(&self, address: &str) -> Props {
        let Ok(reply) = self.system.call_method(Some("org.bluez"), "/", Some("org.freedesktop.DBus.ObjectManager"), "GetManagedObjects", &()).await else { return Props::new() };
        let Ok(objects): zbus::Result<HashMap<OwnedObjectPath, crate::values::Interfaces>> = reply.body().deserialize() else { return Props::new() };
        objects.into_values().filter_map(|mut interfaces| interfaces.remove(super::model::IFACE_DEVICE)).find(|props| values::text_or_empty(props, "Address").eq_ignore_ascii_case(address)).unwrap_or_default()
    }
}

#[interface(name = "org.bluez.obex.Agent1")]
impl ObexAgent {
    #[zbus(name = "Release")]
    fn release(&self) {}

    #[zbus(name = "AuthorizePush")]
    async fn authorize_push(&self, transfer: ObjectPath<'_>) -> Result<String, ObexError> {
        let transfer_props = self.props(transfer.as_str(), IFACE_TRANSFER).await;
        let name = safe_file_name(&values::text_or_empty(&transfer_props, "Name"));
        let size = values::number(&transfer_props, "Size").unwrap_or(0);
        let session = values::text_or_empty(&transfer_props, "Session");
        let session_props = self.props(&session, IFACE_SESSION).await;
        let address = values::text_or_empty(&session_props, "Destination");
        let device = self.device_props(&address).await;
        let trusted = values::flag(&device, "Trusted").unwrap_or(false);
        let device_name = values::text(&device, "Alias").unwrap_or_else(|| address.clone());
        let settings = self.shared.settings.lock().expect("no panics while holding this lock").clone();
        let recently = self.shared.accepted_at.lock().expect("no panics while holding this lock").get(&address).is_some_and(|at| at.elapsed() < BATCH_WINDOW);
        if !auto_accept(settings.policy, trusted, recently) {
            let answer = self.prompts.ask("bluetooth-file", json!({ "deviceName": device_name, "deviceAddress": address, "fileName": name, "fileSize": size, "folder": settings.folder })).await;
            match answer {
                Answer::Accepted(_) => {}
                Answer::Declined => return Err(ObexError::Rejected("Declined".to_string())),
                Answer::Gone => return Err(ObexError::Canceled("Went away".to_string())),
            }
        }
        let cache = cache_directory();
        let _ = std::fs::create_dir_all(&cache);
        let temporary = unique_path(&cache, &name);
        self.shared.incoming.lock().expect("no panics while holding this lock").insert(transfer.to_string(), Incoming { temporary: temporary.clone(), name, device: address });
        Ok(temporary.display().to_string())
    }

    #[zbus(name = "Cancel")]
    fn cancel(&self) {}
}

/// Handles the end of incoming transfers, moving what arrived to the folder and saying so.
pub async fn follow_incoming(session: Connection, shared: Arc<ObexShared>, out: mpsc::UnboundedSender<String>) -> zbus::Result<()> {
    let rule = MatchRule::builder().msg_type(MessageType::Signal).interface("org.freedesktop.DBus.Properties").member("PropertiesChanged").path_namespace("/org/bluez/obex").build()?;
    let mut changes = MessageStream::for_match_rule(rule, &session, NonZeroUsize::new(64)).await?;
    while let Some(Ok(message)) = changes.next().await {
        let Some(path) = message.header().path().map(ToString::to_string) else { continue };
        let body = message.body();
        let Ok((interface, changed, _)): zbus::Result<(String, Props, Vec<String>)> = body.deserialize() else { continue };
        if interface != IFACE_TRANSFER {
            continue;
        }
        if let Some(transferred) = values::number(&changed, "Transferred") {
            let _ = out.send(Outgoing::Event { name: "transferProgress", data: &json!({ "transfer": path, "transferred": transferred }) }.to_line());
        }
        let status = values::text_or_empty(&changed, "Status");
        if status != "complete" && status != "error" {
            continue;
        }
        let incoming = shared.incoming.lock().expect("no panics while holding this lock").remove(&path);
        let Some(incoming) = incoming else {
            continue;
        };
        if status == "error" {
            let _ = std::fs::remove_file(&incoming.temporary);
            let _ = out.send(Outgoing::Event { name: "fileReceived", data: &json!({ "ok": false, "name": incoming.name }) }.to_line());
            continue;
        }
        let folder = shared.settings.lock().expect("no panics while holding this lock").folder.clone();
        let _ = std::fs::create_dir_all(&folder);
        let target = unique_path(&folder, &incoming.name);
        let moved = std::fs::rename(&incoming.temporary, &target).or_else(|_| std::fs::copy(&incoming.temporary, &target).and_then(|_| std::fs::remove_file(&incoming.temporary)));
        shared.accepted_at.lock().expect("no panics while holding this lock").insert(incoming.device, Instant::now());
        let _ = out.send(Outgoing::Event { name: "fileReceived", data: &json!({ "ok": moved.is_ok(), "name": incoming.name, "path": target }) }.to_line());
    }
    Ok(())
}

/// Registers to be asked about incoming files, starting obexd if need be.
pub async fn register_agent(session: &Connection) -> zbus::Result<()> {
    let path = ObjectPath::try_from(AGENT_PATH).expect("a valid path");
    session.call_method(Some(BUS_NAME), ROOT_PATH, Some("org.bluez.obex.AgentManager1"), "RegisterAgent", &(&path,)).await?;
    Ok(())
}

/// Sends files to a device, one after another, reporting along the way. Waits for each to finish.
pub async fn send_files(session: &Connection, device_address: &str, files: &[String], out: &mpsc::UnboundedSender<String>) -> Result<(), ApiError> {
    let mut options: HashMap<&str, Variant> = HashMap::new();
    options.insert("Target", Variant::from("opp"));
    let reply = session.call_method(Some(BUS_NAME), ROOT_PATH, Some(IFACE_CLIENT), "CreateSession", &(device_address, options)).await.map_err(|failure| obex_error(&failure))?;
    let session_path: OwnedObjectPath = reply.body().deserialize().map_err(|failure| obex_error(&failure))?;
    let result = send_in_session(session, &session_path, files, out).await;
    let _ = session.call_method(Some(BUS_NAME), ROOT_PATH, Some(IFACE_CLIENT), "RemoveSession", &(&session_path,)).await;
    result
}

async fn send_in_session(session: &Connection, session_path: &OwnedObjectPath, files: &[String], out: &mpsc::UnboundedSender<String>) -> Result<(), ApiError> {
    for file in files {
        let rule = MatchRule::builder().msg_type(MessageType::Signal).interface("org.freedesktop.DBus.Properties").member("PropertiesChanged").path_namespace(session_path.as_str()).build().map_err(|failure| obex_error(&failure))?;
        let mut changes = MessageStream::for_match_rule(rule, session, NonZeroUsize::new(64)).await.map_err(|failure| obex_error(&failure))?;
        let reply = session.call_method(Some(BUS_NAME), session_path.as_str(), Some(IFACE_PUSH), "SendFile", &(file.as_str(),)).await.map_err(|failure| obex_error(&failure))?;
        let (transfer, properties): (OwnedObjectPath, HashMap<String, OwnedVariant>) = reply.body().deserialize().map_err(|failure| obex_error(&failure))?;
        let size = values::number(&properties, "Size").unwrap_or(0);
        let _ = out.send(Outgoing::Event { name: "transferStarted", data: &json!({ "transfer": transfer.as_str(), "name": file, "size": size }) }.to_line());
        loop {
            let Some(Ok(message)) = changes.next().await else { return Err(ApiError::new(ErrorCode::Unavailable, "The file transfer service stopped")) };
            if message.header().path().map(ObjectPath::as_str) != Some(transfer.as_str()) {
                continue;
            }
            let body = message.body();
            let Ok((_, changed, _)): zbus::Result<(String, Props, Vec<String>)> = body.deserialize() else { continue };
            if let Some(transferred) = values::number(&changed, "Transferred") {
                let _ = out.send(Outgoing::Event { name: "transferProgress", data: &json!({ "transfer": transfer.as_str(), "transferred": transferred }) }.to_line());
            }
            match values::text_or_empty(&changed, "Status").as_str() {
                "complete" => break,
                "error" => return Err(ApiError::new(ErrorCode::Failed, "The device didn't take the file")),
                _ => {}
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_file_comes_in_unasked_only_by_policy_or_as_part_of_a_batch() {
        assert!(!auto_accept(ReceivePolicy::Ask, true, false));
        assert!(auto_accept(ReceivePolicy::Ask, false, true));
        assert!(auto_accept(ReceivePolicy::Trusted, true, false));
        assert!(!auto_accept(ReceivePolicy::Trusted, false, false));
        assert!(auto_accept(ReceivePolicy::Always, false, false));
    }

    #[test]
    fn a_name_stays_inside_the_folder_whatever_it_claims() {
        assert_eq!(safe_file_name("photo.jpg"), "photo.jpg");
        assert_eq!(safe_file_name("../../.ssh/authorized_keys"), "authorized_keys");
        assert_eq!(safe_file_name("/etc/passwd"), "passwd");
        assert_eq!(safe_file_name("..\\..\\windows\\evil.exe"), "evil.exe");
        assert_eq!(safe_file_name(".."), "received-file");
        assert_eq!(safe_file_name("."), "received-file");
        assert_eq!(safe_file_name(""), "received-file");
        assert_eq!(safe_file_name("../"), "received-file");
        assert_eq!(safe_file_name("na\u{0}me\n.txt"), "name.txt");
        assert_eq!(safe_file_name("фото 1.jpg"), "фото 1.jpg");
    }

    #[test]
    fn taken_names_get_a_number() {
        let folder = std::env::temp_dir().join(format!("velora-obex-test-{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        assert_eq!(unique_path(&folder, "a.txt"), folder.join("a.txt"));
        std::fs::write(folder.join("a.txt"), "").unwrap();
        assert_eq!(unique_path(&folder, "a.txt"), folder.join("a (1).txt"));
        std::fs::write(folder.join("a (1).txt"), "").unwrap();
        assert_eq!(unique_path(&folder, "a.txt"), folder.join("a (2).txt"));
        std::fs::write(folder.join("noext"), "").unwrap();
        assert_eq!(unique_path(&folder, "noext"), folder.join("noext (1)"));
        std::fs::remove_dir_all(&folder).unwrap();
    }

    #[test]
    fn policies_read_from_settings_words() {
        assert_eq!(serde_json::from_str::<ReceivePolicy>("\"ask\"").unwrap(), ReceivePolicy::Ask);
        assert_eq!(serde_json::from_str::<ReceivePolicy>("\"trusted\"").unwrap(), ReceivePolicy::Trusted);
        assert_eq!(serde_json::from_str::<ReceivePolicy>("\"always\"").unwrap(), ReceivePolicy::Always);
    }
}
