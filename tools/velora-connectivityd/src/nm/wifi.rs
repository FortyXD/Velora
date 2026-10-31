//! Owned Wi-Fi activations. Stopping the wait never deactivates a connection, and a password is only
//! persisted after activation succeeds. A short-lived secret agent answers only this operation's UUID.

use super::agent::{secrets_reply, AgentError, AGENT_PATH};
use super::client::{wifi_settings, NmClient, BUS_NAME};
use super::model::{self, Security, IFACE_MANAGER, IFACE_SETTINGS_CONNECTION};
use super::{form, reasons, validate};
use crate::protocol::{ApiError, ErrorCode, Outgoing};
use crate::secret::Secret;
use crate::values::{self, Settings};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::os::unix::fs::OpenOptionsExt;
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, oneshot, watch};
use zbus::{interface, Connection, ObjectPath, OwnedObjectPath, OwnedVariant, Proxy, Variant};

const MANAGER: &str = "/org/freedesktop/NetworkManager";
const SECURITY: &str = "802-11-wireless-security";
fn dbus_error(error: zbus::Error) -> ApiError { reasons::dbus_error(&error) }

const NOT_SAVED: &str = "Connected, but the password could not be saved";

#[derive(Deserialize)]
pub struct Connect {
    pub operation: String,
    pub ssid: String,
    #[serde(default)]
    pub uuid: String,
    #[serde(default)]
    pub bssid: String,
    #[serde(default)]
    pub hidden: bool,
    #[serde(default)]
    pub security: String,
    #[serde(default)]
    pub password: Option<Secret>,
}

struct Waiting {
    path: Option<String>,
    secret: Option<Secret>,
    served: bool,
    request: u64,
    answer: Option<oneshot::Sender<Secret>>,
    connected: bool,
}

struct Operation {
    id: String,
    uuid: String,
    ssid: String,
    security: Security,
    waiting: Mutex<Waiting>,
    canceled: watch::Sender<bool>,
    out: mpsc::UnboundedSender<String>,
}

impl Operation {
    fn event(&self, name: &str, data: Value) {
        let _ = self.out.send(Outgoing::Event { name, data: &data }.to_line());
    }

    async fn canceled(&self) {
        let mut state = self.canceled.subscribe();
        while !*state.borrow_and_update() {
            if state.changed().await.is_err() { return; }
        }
    }

    async fn password(&self, path: &str, retry: bool) -> Result<Secret, AgentError> {
        let receiver = {
            let mut waiting = self.waiting.lock().expect("operation lock");
            if *self.canceled.borrow() || waiting.path.as_deref().is_some_and(|owned| owned != path) {
                return Err(AgentError::AgentCanceled("The password request went away".into()));
            }
            waiting.path = Some(path.to_string());
            if retry && waiting.served { waiting.secret = None; }
            if let Some(secret) = waiting.secret.clone() {
                waiting.served = true;
                return Ok(secret);
            }
            let (answer, receiver) = oneshot::channel();
            waiting.answer = Some(answer);
            waiting.request += 1;
            self.event("wifiPassword", json!({ "operation": self.id, "ssid": self.ssid, "request": waiting.request.to_string(), "retry": retry }));
            receiver
        };
        tokio::select! {
            answer = receiver => answer.map_err(|_| AgentError::AgentCanceled("The password request went away".into())),
            () = self.canceled() => Err(AgentError::UserCanceled("The password request was canceled".into())),
        }
    }
}

#[derive(Default)]
pub struct Operations {
    preparing: Mutex<Option<(String, watch::Sender<bool>)>>,
    active: Mutex<Option<Arc<Operation>>>,
}

impl Operations {
    pub fn cancel(&self, id: &str) -> bool {
        let mut active = self.active.lock().expect("operation lock");
        let Some(operation) = active.as_ref().filter(|operation| operation.id == id) else {
            if let Some((_, canceled)) = self.preparing.lock().expect("operation lock").as_ref().filter(|(operation, _)| operation == id) {
                canceled.send_replace(true);
                return true;
            }
            return false;
        };
        let mut waiting = operation.waiting.lock().expect("operation lock");
        if waiting.connected { return false; }
        operation.canceled.send_replace(true);
        waiting.answer = None;
        waiting.secret = None;
        drop(waiting);
        *active = None;
        true
    }

    pub fn submit(&self, id: &str, request: &str, password: Secret) -> Result<bool, ApiError> {
        let active = self.active.lock().expect("operation lock");
        let Some(operation) = active.as_ref().filter(|operation| operation.id == id) else { return Ok(false) };
        let mut waiting = operation.waiting.lock().expect("operation lock");
        if waiting.request.to_string() != request || waiting.answer.is_none() { return Ok(false); }
        validate_password(operation.security, &password)?;
        waiting.secret = Some(password.clone());
        waiting.served = true;
        Ok(waiting.answer.take().is_some_and(|answer| answer.send(password).is_ok()))
    }

    pub async fn connect(&self, request: Connect, out: mpsc::UnboundedSender<String>) -> Result<Value, ApiError> {
        if request.operation.is_empty() || request.operation.len() > 128 || !request.operation.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-') {
            return Err(ApiError::invalid("Invalid connection operation"));
        }
        let _lock = operation_lock()?;
        let (canceled, mut cancellation) = watch::channel(false);
        {
            let mut preparing = self.preparing.lock().expect("operation lock");
            if preparing.is_some() { return Err(ApiError::new(ErrorCode::Conflict, "Another Wi-Fi connection is still in progress")); }
            *preparing = Some((request.operation.clone(), canceled.clone()));
        }
        let initialize = async {
            let connection = Connection::system().await.map_err(dbus_error)?;
            let client = NmClient::new(connection.clone());
            let prepared = prepare(&client, &request).await?;
            Ok((connection, client, prepared))
        };
        let initialized = tokio::select! {
            biased;
            _ = cancellation.changed() => Err(ApiError::new(ErrorCode::Canceled, "The connection was canceled")),
            result = initialize => result,
        };
        *self.preparing.lock().expect("operation lock") = None;
        let (connection, client, prepared) = initialized?;
        let operation = Arc::new(Operation {
            id: request.operation.clone(), uuid: prepared.uuid.clone(), ssid: request.ssid.clone(), security: prepared.security,
            waiting: Mutex::new(Waiting { path: prepared.path.clone(), secret: request.password.clone(), served: prepared.path.is_none() && request.password.is_some(), request: 0, answer: None, connected: false }),
            canceled, out,
        });
        {
            let mut active = self.active.lock().expect("operation lock");
            if active.is_some() { return Err(ApiError::new(ErrorCode::Conflict, "Another Wi-Fi connection is still in progress")); }
            *active = Some(Arc::clone(&operation));
        }
        let result = run(&connection, &client, &operation, prepared, &request).await;
        operation.canceled.send_replace(true);
        operation.waiting.lock().expect("operation lock").answer = None;
        let _ = connection.close().await;
        let mut active = self.active.lock().expect("operation lock");
        if active.as_ref().is_some_and(|current| Arc::ptr_eq(current, &operation)) { *active = None; }
        result
    }
}

fn operation_lock() -> Result<File, ApiError> {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir().join(format!("velora-wifi-{}", std::process::id())));
    std::fs::create_dir_all(&runtime).map_err(|_| ApiError::new(ErrorCode::Failed, "Could not prepare the Wi-Fi connection"))?;
    let file = OpenOptions::new().create(true).write(true).truncate(false).mode(0o600).open(runtime.join("velora-wifi-operation.lock"))
        .map_err(|_| ApiError::new(ErrorCode::Failed, "Could not prepare the Wi-Fi connection"))?;
    file.try_lock().map_err(|_| ApiError::new(ErrorCode::Conflict, "Another Wi-Fi connection is still in progress"))?;
    Ok(file)
}

fn validate_password(security: Security, password: &Secret) -> Result<(), ApiError> {
    let valid = !password.expose().contains('\0') && match security {
        Security::WpaPsk => validate::wpa_psk(password.expose()),
        Security::Sae => validate::sae_password(password.expose()),
        Security::Wep => validate::wep_key(password.expose()),
        _ => false,
    };
    if valid { Ok(()) } else { Err(ApiError::new(ErrorCode::WrongSecret, "The password is not valid for this network's security")) }
}

struct Prepared {
    uuid: String,
    path: Option<String>,
    settings: Settings,
    security: Security,
    device: String,
    access_point: String,
    repair_security: bool,
}

async fn prepare(client: &NmClient, request: &Connect) -> Result<Prepared, ApiError> {
    let snapshot = client.snapshot().await;
    let target = snapshot.networks.iter().find(|network| !request.bssid.is_empty() && network.bssid.eq_ignore_ascii_case(&request.bssid))
        .or_else(|| snapshot.networks.iter().find(|network| network.ssid == request.ssid));
    let (path, settings, security, repair_security) = if request.uuid.is_empty() {
        if target.is_none() && !request.hidden { return Err(ApiError::new(ErrorCode::NotFound, "The network is out of range")); }
        let security = if request.hidden {
            match request.security.as_str() {
                "none" | "open" => Security::None,
                "sae" => Security::Sae,
                "wpa-psk" | "" => Security::WpaPsk,
                _ => return Err(ApiError::invalid("Unsupported hidden network security")),
            }
        } else { target.map_or(Security::None, |network| network.security_type) };
        let mut settings = wifi_settings(&request.ssid, request.hidden, security, request.password.as_ref())?;
        let uuid = values::text_or_empty(&form::new_profile("802-11-wireless", None)?["connection"], "uuid");
        let section = settings.get_mut("connection").expect("Wi-Fi connection section");
        section.insert("uuid".into(), owned(uuid));
        section.insert("autoconnect".into(), owned(false));
        (None, settings, security, false)
    } else {
        let path = client.find_profile(&request.uuid).await?;
        let mut settings = client.settings(&path).await?;
        if settings.get("connection").is_none_or(|section| values::text_or_empty(section, "type") != "802-11-wireless") {
            return Err(ApiError::invalid("This connection is not a Wi-Fi network"));
        }
        let mut security = model::profile_security(&settings);
        let repair = security == Security::None && target.is_some_and(|network| network.security_type.is_personal());
        if repair {
            security = target.expect("the secured access point").security_type;
            let security_settings = wifi_settings(&request.ssid, request.hidden, security, None)?;
            settings.insert(SECURITY.into(), security_settings[SECURITY].clone());
        }
        (Some(path), settings, security, repair)
    };
    if path.is_none() && security.is_enterprise() { return Err(ApiError::new(ErrorCode::SecretsRequired, "This network needs an enterprise login")); }
    if let Some(password) = &request.password { validate_password(security, password)?; }
    let uuid = values::text_or_empty(&settings["connection"], "uuid");
    let device = target.map(|network| network.device.clone()).or_else(|| snapshot.devices.iter().find(|device| device.device_type == model::DEVICE_TYPE_WIFI).map(|device| device.path.clone()))
        .ok_or_else(|| ApiError::new(ErrorCode::Unavailable, "No Wi-Fi device was found"))?;
    Ok(Prepared { uuid, path, settings, security, device, access_point: target.filter(|_| !request.hidden).map_or_else(|| "/".into(), |network| network.access_point.clone()), repair_security })
}

fn secret_key(security: Security) -> (&'static str, &'static str) {
    if security == Security::Wep { ("wep-key0", "wep-key-flags") } else { ("psk", "psk-flags") }
}

fn owned<'a>(value: impl Into<Variant<'a>>) -> OwnedVariant {
    value.into().try_into_owned().expect("plain settings")
}

async fn update(client: &NmClient, path: &str, settings: &Settings, flags: u32, version: u64) -> Result<(), ApiError> {
    let arguments = HashMap::from([("version-id", Variant::from(version))]);
    let _: HashMap<String, OwnedVariant> = client.proxy(path, IFACE_SETTINGS_CONNECTION).await?.call("Update2", &(settings, flags, arguments)).await.map_err(dbus_error)?;
    Ok(())
}

async fn version(client: &NmClient, path: &str) -> Result<u64, ApiError> {
    client.proxy(path, IFACE_SETTINGS_CONNECTION).await?.get_property("VersionId").await.map_err(dbus_error)
}

async fn run(connection: &Connection, client: &NmClient, operation: &Arc<Operation>, prepared: Prepared, request: &Connect) -> Result<Value, ApiError> {
    let owner: String = Proxy::new(connection, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus").await.map_err(dbus_error)?
        .call("GetNameOwner", &(BUS_NAME,)).await.map_err(dbus_error)?;
    connection.object_server().at(AGENT_PATH, ScopedAgent { operation: Arc::clone(operation), owner }).await.map_err(dbus_error)?;
    let identifier = format!("org.velora.wifi.p{}.op{}", std::process::id(), request.operation);
    connection.call_method(Some(BUS_NAME), "/org/freedesktop/NetworkManager/AgentManager", Some("org.freedesktop.NetworkManager.AgentManager"), "RegisterWithCapabilities", &(identifier.as_str(), 0u32)).await.map_err(dbus_error)?;

    // An explicit replacement is tried in memory; the profile's on-disk password survives a failure.
    let mut restore = None;
    if let Some(path) = prepared.path.as_ref().filter(|_| request.password.is_some() || prepared.repair_security) {
        let old_version = version(client, path).await?;
        let original = client.settings_with_secrets(path).await?;
        let mut candidate = original.clone();
        if prepared.repair_security { candidate.insert(SECURITY.into(), prepared.settings[SECURITY].clone()); }
        let (key, flags_key) = secret_key(prepared.security);
        let section = candidate.entry(SECURITY.into()).or_default();
        // External keyrings retain ownership. The scoped agent supplies their replacement in memory.
        if values::number(section, flags_key).unwrap_or(0) == 0 {
            if let Some(password) = &request.password { section.insert(key.into(), owned(password.expose())); }
            update(client, path, &candidate, 0x2, old_version).await?;
            if request.password.is_some() { operation.waiting.lock().expect("operation lock").served = true; }
            restore = Some((path.clone(), original, version(client, path).await?));
        }
    }

    let activation = async {
        if let Some(path) = &prepared.path {
            client.activated(|| async {
                let active: OwnedObjectPath = client.proxy(MANAGER, IFACE_MANAGER).await?.call("ActivateConnection", &(ObjectPath::try_from(path.as_str()).expect("profile path"), ObjectPath::try_from(prepared.device.as_str()).expect("device path"), ObjectPath::try_from(prepared.access_point.as_str()).expect("access point path"))).await.map_err(dbus_error)?;
                Ok(active.to_string())
            }).await
        } else {
            client.activated(|| async {
                let options = HashMap::from([("persist", Variant::from("memory"))]);
                let (path, active, _): (OwnedObjectPath, OwnedObjectPath, HashMap<String, OwnedVariant>) = client.proxy(MANAGER, IFACE_MANAGER).await?.call("AddAndActivateConnection2", &(&prepared.settings, ObjectPath::try_from(prepared.device.as_str()).expect("device path"), ObjectPath::try_from(prepared.access_point.as_str()).expect("access point path"), options)).await.map_err(dbus_error)?;
                operation.waiting.lock().expect("operation lock").path = Some(path.to_string());
                Ok(active.to_string())
            }).await
        }
    };
    let result = tokio::select! {
        biased;
        result = activation => result,
        () = operation.canceled() => Err(ApiError::new(ErrorCode::Canceled, "The connection was canceled")),
    };
    let active = match result {
        Ok(active) => active,
        Err(error) => {
            if let Some((path, original, expected)) = restore { let _ = update(client, &path, &original, 0x2, expected).await; }
            return Err(error);
        }
    };
    operation.waiting.lock().expect("operation lock").connected = true;
    let secret = operation.waiting.lock().expect("operation lock").secret.clone();
    let save = async {
        if prepared.path.is_some() && secret.is_none() { return Ok(()); }
        let path = operation.waiting.lock().expect("operation lock").path.clone().ok_or_else(|| ApiError::new(ErrorCode::NotFound, NOT_SAVED))?;
        let expected = version(client, &path).await?;
        let mut settings = client.settings_with_secrets(&path).await?;
        if let Some(secret) = secret {
            let (key, flags_key) = secret_key(prepared.security);
            let section = settings.entry(SECURITY.into()).or_default();
            let flags = values::number(section, flags_key).unwrap_or(0);
            if flags != 0 { return Err(ApiError::new(ErrorCode::SecretsRequired, NOT_SAVED)); }
            section.insert(key.into(), owned(secret.expose()));
        }
        if prepared.path.is_none() { settings.get_mut("connection").expect("connection section").insert("autoconnect".into(), owned(true)); }
        update(client, &path, &settings, 0x1, expected).await
    }.await;
    Ok(json!({ "active": active, "saved": save.is_ok(), "warning": if save.is_err() { NOT_SAVED } else { "" } }))
}

struct ScopedAgent {
    operation: Arc<Operation>,
    owner: String,
}

#[interface(name = "org.freedesktop.NetworkManager.SecretAgent")]
impl ScopedAgent {
    #[zbus(name = "GetSecrets")]
    async fn get_secrets(&self, connection: Settings, path: ObjectPath<'_>, setting: String, _hints: Vec<String>, flags: u32, #[zbus(header)] header: zbus::message::Header<'_>) -> Result<Settings, AgentError> {
        let uuid = connection.get("connection").map(|section| values::text_or_empty(section, "uuid")).unwrap_or_default();
        if header.sender().map(|sender| sender.as_str()) != Some(self.owner.as_str()) || uuid != self.operation.uuid || setting != SECURITY || !self.operation.security.is_personal() {
            return Err(AgentError::NoSecrets("This password request belongs to another connection".into()));
        }
        if flags & 0x1 == 0 { return Err(AgentError::NoSecrets("Asking for a password is not allowed".into())); }
        let secret = self.operation.password(path.as_str(), flags & 0x2 != 0).await?;
        let key = if self.operation.security == Security::Wep { "wep-key0" } else { "psk" };
        Ok(secrets_reply(&setting, &HashMap::from([(key.into(), secret.expose().to_string())])))
    }

    #[zbus(name = "CancelGetSecrets")]
    fn cancel_get_secrets(&self, path: ObjectPath<'_>, _setting: String, #[zbus(header)] header: zbus::message::Header<'_>) {
        if header.sender().map(|sender| sender.as_str()) != Some(self.owner.as_str()) { return; }
        let mut waiting = self.operation.waiting.lock().expect("operation lock");
        if waiting.path.as_deref() == Some(path.as_str()) { waiting.answer = None; }
    }

    #[zbus(name = "SaveSecrets")]
    fn save_secrets(&self, _connection: Settings, _path: ObjectPath<'_>) -> Result<(), AgentError> {
        Err(AgentError::NoSecrets("Passwords are saved only after a successful connection".into()))
    }

    #[zbus(name = "DeleteSecrets")]
    fn delete_secrets(&self, _connection: Settings, _path: ObjectPath<'_>) -> Result<(), AgentError> {
        Err(AgentError::NoSecrets("This agent does not delete saved passwords".into()))
    }
}
