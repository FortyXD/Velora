//! Owned Wi-Fi activations. Stopping the wait never deactivates a connection, and a password is only
//! persisted after activation succeeds. A short-lived secret agent answers only this operation's UUID.

use super::agent::{secrets_reply, AgentError, AGENT_PATH};
use super::client::{wifi_settings, NmClient, BUS_NAME};
use super::model::{self, Security, IFACE_MANAGER, IFACE_SETTINGS_CONNECTION};
use super::{form, reasons, validate};
use super::wifi_budget::{WorkBudget, WORK_TIMEOUT};
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
    prompting: watch::Sender<bool>,
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
            self.prompting.send_replace(true);
            waiting.request += 1;
            // The backend resolved this network's identity: a prompt that arrives for an
            // operation started without a row (a QR code, say) can be bound to the right one.
            self.event("wifiPassword", json!({ "operation": self.id, "ssid": self.ssid, "uuid": self.uuid,
                "security": serde_json::to_value(self.security).ok().and_then(|value| value.as_str().map(str::to_string)).unwrap_or_default(),
                "request": waiting.request.to_string(), "retry": retry }));
            receiver
        };
        let result = tokio::select! {
            answer = receiver => answer.map_err(|_| AgentError::AgentCanceled("The password request went away".into())),
            () = self.canceled() => Err(AgentError::UserCanceled("The password request was canceled".into())),
        };
        self.prompting.send_replace(self.waiting.lock().expect("operation lock").answer.is_some());
        result
    }
}

#[derive(Default)]
struct Lifecycle {
    stopping: bool,
    current: Option<(watch::Sender<bool>, watch::Receiver<bool>)>,
}

struct Completion(watch::Sender<bool>);
impl Drop for Completion {
    fn drop(&mut self) { self.0.send_replace(true); }
}

#[derive(Default)]
pub struct Operations {
    preparing: Mutex<Option<(String, watch::Sender<bool>)>>,
    active: Mutex<Option<Arc<Operation>>>,
    lifecycle: Mutex<Lifecycle>,
}

impl Operations {
    /// EOF cancels only Wi-Fi work and gives version-checked rollback/save a bounded chance to finish.
    pub async fn shutdown(&self) {
        let current = {
            let mut lifecycle = self.lifecycle.lock().expect("operation lock");
            lifecycle.stopping = true;
            lifecycle.current.clone()
        };
        if let Some((canceled, mut completed)) = current {
            canceled.send_replace(true);
            let wait = async {
                while !*completed.borrow_and_update() {
                    if completed.changed().await.is_err() { break; }
                }
            };
            let _ = tokio::time::timeout(std::time::Duration::from_secs(65), wait).await;
        }
    }

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

    pub async fn connect(&self, request: Connect, out: mpsc::UnboundedSender<String>, snapshots: &NmClient) -> Result<Value, ApiError> {
        if request.operation.is_empty() || request.operation.len() > 128 || !request.operation.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-') {
            return Err(ApiError::invalid("Invalid connection operation"));
        }
        let _lock = operation_lock()?;
        let (canceled, mut cancellation) = watch::channel(false);
        let (finished, completed) = watch::channel(false);
        let _completion = Completion(finished);
        {
            let mut lifecycle = self.lifecycle.lock().expect("operation lock");
            if lifecycle.stopping { return Err(ApiError::new(ErrorCode::Canceled, "The connection was canceled")); }
            lifecycle.current = Some((canceled.clone(), completed));
        }
        {
            let mut preparing = self.preparing.lock().expect("operation lock");
            if preparing.is_some() { return Err(ApiError::new(ErrorCode::Conflict, "Another Wi-Fi connection is still in progress")); }
            *preparing = Some((request.operation.clone(), canceled.clone()));
        }
        let (prompting, prompt_state) = watch::channel(false);
        let mut budget = WorkBudget::new();
        let initialize = async {
            let connection = Connection::system().await.map_err(dbus_error)?;
            let client = NmClient::new(connection.clone());
            let prepared = prepare(&client, &request).await?;
            Ok((connection, client, prepared))
        };
        let initialized = tokio::select! {
            biased;
            _ = cancellation.changed() => Err(ApiError::new(ErrorCode::Canceled, "The connection was canceled")),
            result = budget.run(initialize, prompt_state) => result,
        };
        *self.preparing.lock().expect("operation lock") = None;
        let (connection, client, prepared) = initialized?;
        let operation = Arc::new(Operation {
            id: request.operation.clone(), uuid: prepared.uuid.clone(), ssid: request.ssid.clone(), security: prepared.security,
            waiting: Mutex::new(Waiting { path: prepared.path.clone(), secret: request.password.clone(), served: prepared.path.is_none() && request.password.is_some(), request: 0, answer: None, connected: false }),
            canceled, prompting, out,
        });
        {
            let mut active = self.active.lock().expect("operation lock");
            if active.is_some() { return Err(ApiError::new(ErrorCode::Conflict, "Another Wi-Fi connection is still in progress")); }
            *active = Some(Arc::clone(&operation));
        }
        let result = run(&connection, &client, snapshots, &operation, prepared, &request, &mut budget).await;
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
        Security::Sae => (1..=63).contains(&password.expose().len()) && validate::sae_password(password.expose()),
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
    let profile_security = snapshot.profiles.iter().find(|profile| profile.uuid == request.uuid).map(|profile| profile.security_type);
    let matches = |network: &&model::WifiNetwork| {
        network.ssid == request.ssid && profile_security.is_none_or(|security| {
            security == network.security_type
                || (security == Security::WpaPsk && network.security_type == Security::Sae && (network.security.contains("WPA2") || network.security.contains("WPA1")))
                || (matches!(security, Security::DynamicWep | Security::Leap) && network.security_type == Security::Wep)
                // Explicit UUIDs may repair an incomplete saved profile, but are never auto-associated.
                || (security == Security::None && !request.bssid.is_empty() && network.security_type.is_personal())
        }) && (request.security.is_empty() || serde_json::to_value(network.security_type).ok().as_ref().and_then(Value::as_str) == Some(request.security.as_str()))
    };
    let target = if request.bssid.is_empty() {
        snapshot.networks.iter().find(matches)
    } else {
        snapshot.networks.iter().filter(matches).find(|network| network.bssid.eq_ignore_ascii_case(&request.bssid))
    };
    if !request.hidden && !request.bssid.is_empty() && target.is_none() {
        return Err(ApiError::new(ErrorCode::NotFound, "The network is out of range"));
    }
    // A saved profile for this name is reactivated, never duplicated: adding a fresh one with the same
    // id only makes the service store a second as "name 2". Reuse it when the caller gave no UUID, but
    // only where a network actually grounds the name — an out-of-range lookalike must not grab one.
    let desired = match target {
        Some(network) => Some(network.security_type),
        None => match request.security.as_str() {
            "none" | "open" => Some(Security::None),
            "sae" => Some(Security::Sae),
            "wpa-psk" => Some(Security::WpaPsk),
            _ => None,
        },
    };
    let resolved_uuid = if request.uuid.is_empty() && (target.is_some() || request.hidden) {
        model::profile_for_ssid(&snapshot.profiles, &request.ssid, desired).map(|profile| profile.uuid.clone()).unwrap_or_default()
    } else {
        request.uuid.clone()
    };
    let (path, settings, security, repair_security) = if resolved_uuid.is_empty() {
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
        let path = client.find_profile(&resolved_uuid).await?;
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

// A partial secret read must never be written back as though it were complete.
// Keep this stricter rule local to credential replacement, not the general connection editor.
async fn settings_with_secrets(client: &NmClient, path: &str, mut settings: Settings) -> Result<Settings, ApiError> {
    for section in super::client::secret_sections(&settings) {
        let secrets: Settings = client.proxy(path, IFACE_SETTINGS_CONNECTION).await?.call("GetSecrets", &(section.as_str(),)).await.map_err(dbus_error)?;
        for (name, values) in secrets { settings.entry(name).or_default().extend(values); }
    }
    Ok(settings)
}

async fn version(client: &NmClient, path: &str) -> Result<u64, ApiError> {
    let version = client.proxy(path, IFACE_SETTINGS_CONNECTION).await?.get_property::<u64>("VersionId").await.map_err(dbus_error)?;
    if version == 0 || version == u64::MAX { return Err(ApiError::new(ErrorCode::Conflict, "This profile does not support safe password updates")); }
    Ok(version)
}

async fn run(connection: &Connection, client: &NmClient, snapshots: &NmClient, operation: &Arc<Operation>, prepared: Prepared, request: &Connect, budget: &mut WorkBudget) -> Result<Value, ApiError> {
    let mut restore = None;
    // The profile revision this operation owns. Saving later must write against it, not against
    // whatever a concurrent editor left behind while the connection was activating.
    let mut owned_version: Option<u64> = None;
    let setup = async {
        let owner: String = Proxy::new(connection, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus").await.map_err(dbus_error)?
            .call("GetNameOwner", &(BUS_NAME,)).await.map_err(dbus_error)?;
        connection.object_server().at(AGENT_PATH, ScopedAgent { operation: Arc::clone(operation), owner }).await.map_err(dbus_error)?;
        let identifier = format!("org.velora.wifi.p{}.op{}", std::process::id(), request.operation);
        connection.call_method(Some(BUS_NAME), "/org/freedesktop/NetworkManager/AgentManager", Some("org.freedesktop.NetworkManager.AgentManager"), "RegisterWithCapabilities", &(identifier.as_str(), 0u32)).await.map_err(dbus_error)?;

        // An explicit replacement is tried in memory; the profile's on-disk password survives a failure.
        if let Some(path) = prepared.path.as_ref() {
            owned_version = version(client, path).await.ok();
            if request.password.is_some() || prepared.repair_security {
                let old_version = owned_version.ok_or_else(|| ApiError::new(ErrorCode::Conflict, "This profile does not support safe password updates"))?;
                let plain = client.settings(path).await?;
                let (key, flags_key) = secret_key(prepared.security);
                // Do not even retrieve an external keyring's password to try a replacement.
                if plain.get(SECURITY).and_then(|section| values::number(section, flags_key)).unwrap_or(0) == 0 {
                    let original = settings_with_secrets(client, path, plain).await?;
                    let mut candidate = original.clone();
                    if prepared.repair_security { candidate.insert(SECURITY.into(), prepared.settings[SECURITY].clone()); }
                    let section = candidate.entry(SECURITY.into()).or_default();
                    if let Some(password) = &request.password { section.insert(key.into(), owned(password.expose())); }
                    update(client, path, &candidate, 0x2, old_version).await?;
                    if request.password.is_some() { operation.waiting.lock().expect("operation lock").served = true; }
                    // NM increments VersionId for the update. Reading it again could adopt an intervening
                    // writer's version and then incorrectly roll that writer back on cancellation.
                    owned_version = Some(old_version + 1);
                    restore = Some((path.clone(), original, old_version + 1));
                }
            }
        }

        Ok(())
    };
    let setup_result = tokio::select! {
        biased;
        result = budget.run(setup, operation.prompting.subscribe()) => result,
        () = operation.canceled() => Err(ApiError::new(ErrorCode::Canceled, "The connection was canceled")),
    };
    let activation = async {
        setup_result?;
        if let Some(path) = &prepared.path {
            client.activation(|| async {
                let active: OwnedObjectPath = client.proxy(MANAGER, IFACE_MANAGER).await?.call("ActivateConnection", &(ObjectPath::try_from(path.as_str()).expect("profile path"), ObjectPath::try_from(prepared.device.as_str()).expect("device path"), ObjectPath::try_from(prepared.access_point.as_str()).expect("access point path"))).await.map_err(dbus_error)?;
                Ok(active.to_string())
            }).await
        } else {
            client.activation(|| async {
                let options = HashMap::from([("persist", Variant::from("memory"))]);
                let (path, active, _): (OwnedObjectPath, OwnedObjectPath, HashMap<String, OwnedVariant>) = client.proxy(MANAGER, IFACE_MANAGER).await?.call("AddAndActivateConnection2", &(&prepared.settings, ObjectPath::try_from(prepared.device.as_str()).expect("device path"), ObjectPath::try_from(prepared.access_point.as_str()).expect("access point path"), options)).await.map_err(dbus_error)?;
                operation.waiting.lock().expect("operation lock").path = Some(path.to_string());
                Ok(active.to_string())
            }).await
        }
    };
    let result = tokio::select! {
        biased;
        result = budget.run(activation, operation.prompting.subscribe()) => result,
        () = operation.canceled() => Err(ApiError::new(ErrorCode::Canceled, "The connection was canceled")),
    };
    // A reply racing a cancel may report NM success. Do not persist a canceled attempt.
    let result = {
        let mut waiting = operation.waiting.lock().expect("operation lock");
        if *operation.canceled.borrow() {
            Err(ApiError::new(ErrorCode::Canceled, "The connection was canceled"))
        } else {
            waiting.connected = result.is_ok();
            result
        }
    };
    let active = match result {
        Ok(active) => active,
        Err(error) => {
            if let Some((path, original, expected)) = restore { let _ = tokio::time::timeout(WORK_TIMEOUT, update(client, &path, &original, 0x2, expected)).await; }
            return Err(error);
        }
    };
    let secret = operation.waiting.lock().expect("operation lock").secret.clone();
    let save = tokio::time::timeout(WORK_TIMEOUT, async {
        if prepared.path.is_some() && secret.is_none() {
            // Activation nudges a profile's timestamp without sending "Updated", so the cache the UI
            // reads keeps the stale one; dropping it here lets the next snapshot see the network as used.
            if let Some(path) = &prepared.path { snapshots.invalidate_profile(path); }
            return Ok(());
        }
        let path = operation.waiting.lock().expect("operation lock").path.clone().ok_or_else(|| ApiError::new(ErrorCode::NotFound, NOT_SAVED))?;
        // An existing profile is saved against the revision this operation owned before activating,
        // so a write that landed in between is refused by NetworkManager rather than overwritten.
        // A profile this operation only just created has no earlier revision to check against.
        let expected = match owned_version.filter(|_| prepared.path.as_deref() == Some(path.as_str())) {
            Some(expected) => expected,
            None => version(client, &path).await?,
        };
        let plain = client.settings(&path).await?;
        let (_, flags_key) = secret_key(prepared.security);
        if secret.is_some() && plain.get(SECURITY).and_then(|section| values::number(section, flags_key)).unwrap_or(0) != 0 {
            return Err(ApiError::new(ErrorCode::SecretsRequired, NOT_SAVED));
        }
        let mut settings = settings_with_secrets(client, &path, plain).await?;
        let typed = secret.is_some();
        if let Some(secret) = secret {
            let (key, flags_key) = secret_key(prepared.security);
            let section = settings.entry(SECURITY.into()).or_default();
            let flags = values::number(section, flags_key).unwrap_or(0);
            if flags != 0 { return Err(ApiError::new(ErrorCode::SecretsRequired, NOT_SAVED)); }
            section.insert(key.into(), owned(secret.expose()));
        }
        // A profile created here or a saved password written into an existing one should join on its own.
        // An existing profile touched without a password keeps whatever autoconnect the person set.
        if prepared.path.is_none() || typed { settings.get_mut("connection").expect("connection section").insert("autoconnect".into(), owned(true)); }
        update(client, &path, &settings, 0x1, expected).await
    }).await.unwrap_or_else(|_| Err(ApiError::new(ErrorCode::Timeout, NOT_SAVED)));
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inline_passwords_keep_whitespace_and_utf8_byte_limits() {
        for (security, password, valid) in [
            (Security::WpaPsk, "        ".to_string(), true),
            (Security::WpaPsk, "я".repeat(31) + " ", true),
            (Security::WpaPsk, "я".repeat(32), false),
            (Security::WpaPsk, "ab".repeat(32), true),
            (Security::Sae, " ".to_string(), true),
            (Security::Sae, "x".repeat(63), true),
            (Security::Sae, "x".repeat(64), false),
            (Security::Sae, "я".repeat(32), false),
            (Security::Sae, String::new(), false),
            (Security::Sae, "x\0".to_string(), false),
        ] {
            assert_eq!(validate_password(security, &Secret::new(password)).is_ok(), valid);
        }
    }
}
