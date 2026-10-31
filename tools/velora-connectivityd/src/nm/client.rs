//! Talking to NetworkManager: reading its state, watching for changes and acting on connections.

use super::model::{self, NetworkSnapshot, Security, IFACE_ACTIVE, IFACE_DEVICE, IFACE_MANAGER, IFACE_SETTINGS_CONNECTION, IFACE_WIRELESS};
use super::{form, reasons, share};
use crate::protocol::{ApiError, ErrorCode};
use crate::secret::Secret;
use crate::values::{self, Interfaces, Objects, Props, Settings};
use futures_util::StreamExt;
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};
use std::num::NonZeroUsize;
use std::path::Path;
use std::process::Stdio;
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use tokio::sync::Notify;
use zbus::message::Type as MessageType;
use zbus::{Connection, MatchRule, MessageStream, ObjectPath, OwnedObjectPath, OwnedVariant, Proxy, Variant};
use zeroize::Zeroizing;

pub const BUS_NAME: &str = "org.freedesktop.NetworkManager";
const ROOT_PATH: &str = "/org/freedesktop";
const MANAGER_PATH: &str = "/org/freedesktop/NetworkManager";
const SETTINGS_PATH: &str = "/org/freedesktop/NetworkManager/Settings";
const IFACE_SETTINGS: &str = "org.freedesktop.NetworkManager.Settings";
const IFACE_PROPERTIES: &str = "org.freedesktop.DBus.Properties";

const UPDATE_TO_DISK: u32 = 0x1;
const SCAN_MIN_INTERVAL: Duration = Duration::from_secs(10);
const SCAN_GIVE_UP: Duration = Duration::from_secs(15);
const ACTIVATION_TIMEOUT: Duration = Duration::from_secs(180);

fn error(error: zbus::Error) -> ApiError {
    reasons::dbus_error(&error)
}

fn object_path(path: &str) -> Result<ObjectPath<'_>, ApiError> {
    ObjectPath::try_from(path).map_err(|_| ApiError::invalid(format!("not an object path: {path}")))
}

fn owned<'a>(value: impl Into<Variant<'a>>) -> OwnedVariant {
    value.into().try_into_owned().expect("settings hold no file descriptors")
}

/// Profiles' settings are only read when they change, since it takes one call per profile.
#[derive(Default)]
struct ProfileCache {
    profiles: BTreeMap<String, Settings>,
}

#[derive(Default)]
struct ScanState {
    /// Device path → when a scan was last asked for
    requested: HashMap<String, Instant>,
    /// Device path → the device's `LastScan` when the scan in progress was asked for
    in_progress: HashMap<String, (i64, Instant)>,
}

pub struct NmClient {
    connection: Connection,
    cache: Mutex<ProfileCache>,
    scans: Mutex<ScanState>,
    /// Woken whenever a snapshot may have changed.
    pub changed: Notify,
    /// Woken when the service comes or goes.
    pub availability_changed: Notify,
}

impl NmClient {
    pub fn new(connection: Connection) -> Self {
        Self { connection, cache: Mutex::default(), scans: Mutex::default(), changed: Notify::new(), availability_changed: Notify::new() }
    }

    pub(super) async fn proxy<'a>(&'a self, path: &'a str, interface: &'a str) -> Result<Proxy<'a>, ApiError> {
        // Cached properties would go stale between snapshots, and nothing here reads them
        zbus::proxy::Builder::<Proxy<'a>>::new(&self.connection)
            .destination(BUS_NAME)
            .path(path)
            .interface(interface)
            .cache_properties(zbus::proxy::CacheProperties::No)
            .build()
            .await
            .map_err(error)
    }

    async fn objects(&self) -> Result<Objects, ApiError> {
        let proxy = self.proxy(ROOT_PATH, "org.freedesktop.DBus.ObjectManager").await?;
        let objects: HashMap<OwnedObjectPath, Interfaces> = proxy.call("GetManagedObjects", &()).await.map_err(error)?;
        Ok(objects.into_iter().map(|(path, interfaces)| (path.to_string(), interfaces)).collect())
    }

    pub(super) async fn settings(&self, path: &str) -> Result<Settings, ApiError> {
        self.proxy(path, IFACE_SETTINGS_CONNECTION).await?.call("GetSettings", &()).await.map_err(error)
    }

    /// Brings the profile cache in line with the objects: new ones are read, removed ones dropped.
    async fn reconcile_profiles(&self, objects: &Objects) -> BTreeMap<String, Settings> {
        let missing: Vec<&String> = {
            let cache = self.cache.lock().expect("no panics while holding this lock");
            objects
                .iter()
                .filter(|(path, interfaces)| interfaces.contains_key(IFACE_SETTINGS_CONNECTION) && !cache.profiles.contains_key(*path))
                .map(|(path, _)| path)
                .collect()
        };
        let read = futures_util::future::join_all(missing.iter().map(|path| self.settings(path))).await;
        let mut cache = self.cache.lock().expect("no panics while holding this lock");
        for (path, settings) in missing.into_iter().zip(read) {
            // A profile that vanished mid-read shows up as gone in the next refresh
            if let Ok(settings) = settings {
                cache.profiles.insert(path.clone(), settings);
            }
        }
        cache.profiles.retain(|path, _| objects.get(path).is_some_and(|interfaces| interfaces.contains_key(IFACE_SETTINGS_CONNECTION)));
        cache.profiles.clone()
    }

    fn forget_profile(&self, path: &str) {
        self.cache.lock().expect("no panics while holding this lock").profiles.remove(path);
    }

    pub async fn is_running(&self) -> bool {
        self.objects().await.is_ok()
    }

    /// The whole current state. Anything short of an answer from the service reads as "unavailable".
    pub async fn snapshot(&self) -> NetworkSnapshot {
        let Ok(objects) = self.objects().await else {
            self.cache.lock().expect("no panics while holding this lock").profiles.clear();
            return NetworkSnapshot::unavailable();
        };
        let profiles = self.reconcile_profiles(&objects).await;
        model::snapshot(&objects, &profiles, &vpn_plugins())
    }

    /// Whether a Wi-Fi scan is under way, ending it once its device reports a newer one.
    pub fn scanning(&self, snapshot: &NetworkSnapshot) -> bool {
        let mut scans = self.scans.lock().expect("no panics while holding this lock");
        scans.in_progress.retain(|path, (last_scan, since)| {
            let current = snapshot.devices.iter().find(|device| &device.path == path).map(|device| device.last_scan);
            since.elapsed() < SCAN_GIVE_UP && current == Some(*last_scan)
        });
        !scans.in_progress.is_empty()
    }

    /// Follows the service until the stream ends or the bus connection drops, poking `changed` on
    /// anything that could alter a snapshot.
    pub async fn watch(&self) -> Result<(), ApiError> {
        let rule = MatchRule::builder().msg_type(MessageType::Signal).sender(BUS_NAME).build().map_err(error)?;
        let mut signals = MessageStream::for_match_rule(rule, &self.connection, NonZeroUsize::new(256)).await.map_err(error)?;
        let owner_rule = MatchRule::builder()
            .msg_type(MessageType::Signal)
            .sender("org.freedesktop.DBus")
            .member("NameOwnerChanged")
            .arg(0, BUS_NAME)
            .build()
            .map_err(error)?;
        let mut owners = MessageStream::for_match_rule(owner_rule, &self.connection, NonZeroUsize::new(16)).await.map_err(error)?;
        self.changed.notify_one();
        loop {
            tokio::select! {
                Some(Ok(message)) = signals.next() => {
                    let header = message.header();
                    if header.member().is_some_and(|member| member.as_str() == "Updated") {
                        if let Some(path) = header.path() {
                            self.forget_profile(path.as_str());
                        }
                    }
                    self.changed.notify_one();
                }
                Some(Ok(_)) = owners.next() => {
                    self.cache.lock().expect("no panics while holding this lock").profiles.clear();
                    self.changed.notify_one();
                    self.availability_changed.notify_one();
                }
                else => return Ok(()),
            }
        }
    }

    pub(super) async fn find_profile(&self, uuid: &str) -> Result<String, ApiError> {
        let settings = self.proxy(SETTINGS_PATH, IFACE_SETTINGS).await?;
        let path: OwnedObjectPath = settings.call("GetConnectionByUuid", &(uuid,)).await.map_err(error)?;
        Ok(path.to_string())
    }

    async fn set_manager_flag(&self, name: &str, value: bool) -> Result<(), ApiError> {
        let properties = self.proxy(MANAGER_PATH, IFACE_PROPERTIES).await?;
        properties.call::<_, _, ()>("Set", &(IFACE_MANAGER, name, Variant::from(value))).await.map_err(error)
    }

    pub async fn set_wifi_enabled(&self, enabled: bool) -> Result<(), ApiError> {
        self.set_manager_flag("WirelessEnabled", enabled).await
    }

    /// Asks each Wi-Fi device to look for networks, no more than once in ten seconds unless forced;
    /// the service itself refuses scans in quick succession.
    pub async fn scan(&self, force: bool) -> Result<bool, ApiError> {
        let snapshot = self.snapshot().await;
        let mut requested = false;
        for device in snapshot.devices.iter().filter(|device| device.device_type == model::DEVICE_TYPE_WIFI && device.state > 20) {
            let due = {
                let scans = self.scans.lock().expect("no panics while holding this lock");
                force || scans.requested.get(&device.path).is_none_or(|at| at.elapsed() >= SCAN_MIN_INTERVAL)
            };
            if !due {
                continue;
            }
            let proxy = self.proxy(&device.path, IFACE_WIRELESS).await?;
            let options: HashMap<String, Variant> = HashMap::new();
            match proxy.call::<_, _, ()>("RequestScan", &(options,)).await {
                Ok(()) => {
                    let mut scans = self.scans.lock().expect("no panics while holding this lock");
                    scans.requested.insert(device.path.clone(), Instant::now());
                    scans.in_progress.insert(device.path.clone(), (device.last_scan, Instant::now()));
                    requested = true;
                }
                // "Scanning not allowed immediately following previous scan": results are on their way anyway
                Err(failure) if reasons::dbus_error(&failure).code == ErrorCode::Failed => {}
                Err(failure) => return Err(error(failure)),
            }
        }
        self.changed.notify_one();
        Ok(requested)
    }

    /// Runs an activation and waits for how it ends. The failure reasons come from signals, so they are
    /// watched from before the request goes out.
    pub(super) async fn activated<F, Fut>(&self, start: F) -> Result<String, ApiError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<String, ApiError>>,
    {
        let device_rule =
            MatchRule::builder().msg_type(MessageType::Signal).sender(BUS_NAME).interface(IFACE_DEVICE).member("StateChanged").build().map_err(error)?;
        let mut device_signals = MessageStream::for_match_rule(device_rule, &self.connection, NonZeroUsize::new(64)).await.map_err(error)?;
        let active_rule =
            MatchRule::builder().msg_type(MessageType::Signal).sender(BUS_NAME).interface(IFACE_ACTIVE).member("StateChanged").build().map_err(error)?;
        let mut active_signals = MessageStream::for_match_rule(active_rule, &self.connection, NonZeroUsize::new(64)).await.map_err(error)?;

        let active_path = start().await?;
        let active_proxy = self.proxy(&active_path, IFACE_ACTIVE).await?;
        let mut device_reason = None;
        let outcome = async {
            // It may have settled before the subscription saw anything
            match active_proxy.get_property::<u32>("State").await {
                Ok(2) => return Ok(active_path.clone()),
                Ok(4) => return Err(reasons::activation_error(None, 0)),
                Ok(_) => {}
                // Already gone: a failure that happened between the request and this read
                Err(_) => return Err(reasons::activation_error(None, 0)),
            }
            loop {
                tokio::select! {
                    Some(Ok(message)) = device_signals.next() => {
                        let body = message.body();
                        if let Ok((new_state, _old, reason)) = body.deserialize::<(u32, u32, u32)>() {
                            if new_state == 120 {
                                device_reason = Some(i64::from(reason));
                            }
                        }
                    }
                    Some(Ok(message)) = active_signals.next() => {
                        if message.header().path().map(ObjectPath::as_str) != Some(active_path.as_str()) {
                            continue;
                        }
                        let body = message.body();
                        let Ok((state, reason)) = body.deserialize::<(u32, u32)>() else { continue };
                        match state {
                            2 => return Ok(active_path.clone()),
                            4 => {
                                // The device's reason can arrive just after
                                let wait = tokio::time::sleep(Duration::from_millis(200));
                                tokio::pin!(wait);
                                loop {
                                    tokio::select! {
                                        Some(Ok(message)) = device_signals.next() => {
                                            let body = message.body();
                                            if let Ok((120, _old, device)) = body.deserialize::<(u32, u32, u32)>() {
                                                device_reason = Some(i64::from(device));
                                                break;
                                            }
                                        }
                                        () = &mut wait => break,
                                    }
                                }
                                return Err(reasons::activation_error(device_reason, i64::from(reason)));
                            }
                            _ => {}
                        }
                    }
                    else => return Err(reasons::activation_error(device_reason, 0)),
                }
            }
        };
        match tokio::time::timeout(ACTIVATION_TIMEOUT, outcome).await {
            Ok(result) => result,
            Err(_) => Err(ApiError::new(ErrorCode::Timeout, "The connection attempt timed out")),
        }
    }

    pub async fn activate(&self, uuid: &str) -> Result<String, ApiError> {
        let profile = self.find_profile(uuid).await?;
        let root = object_path("/")?;
        let manager = self.proxy(MANAGER_PATH, IFACE_MANAGER).await?;
        self.activated(|| async {
            let active: OwnedObjectPath = manager
                .call("ActivateConnection", &(object_path(&profile)?, &root, &root))
                .await
                .map_err(error)?;
            Ok(active.to_string())
        })
        .await
    }

    /// Stops a connection by its profile; asking for one that isn't up isn't an error.
    pub async fn deactivate(&self, uuid: &str) -> Result<(), ApiError> {
        let snapshot = self.snapshot().await;
        let Some(active) = snapshot.active_connections.iter().find(|active| active.uuid == uuid) else { return Ok(()) };
        let manager = self.proxy(MANAGER_PATH, IFACE_MANAGER).await?;
        manager.call::<_, _, ()>("DeactivateConnection", &(object_path(&active.path)?,)).await.map_err(error)
    }

    /// Deletes a profile along with the ports that belong to it, as plasma-nm does.
    pub async fn forget(&self, uuid: &str) -> Result<(), ApiError> {
        let path = self.find_profile(uuid).await?;
        let objects = self.objects().await?;
        let profiles = self.reconcile_profiles(&objects).await;
        let name = profiles.get(&path).and_then(|settings| settings.get("connection")).map(|section| values::text_or_empty(section, "interface-name"));
        for (port_path, settings) in &profiles {
            let Some(section) = settings.get("connection") else { continue };
            let controller = ["controller", "master"].iter().map(|key| values::text_or_empty(section, key)).find(|value| !value.is_empty());
            if controller.as_deref() == Some(uuid) || (controller.is_some() && controller == name) {
                let port = self.proxy(port_path, IFACE_SETTINGS_CONNECTION).await?;
                port.call::<_, _, ()>("Delete", &()).await.map_err(error)?;
            }
        }
        let profile = self.proxy(&path, IFACE_SETTINGS_CONNECTION).await?;
        profile.call::<_, _, ()>("Delete", &()).await.map_err(error)?;
        self.forget_profile(&path);
        self.changed.notify_one();
        Ok(())
    }

    /// Joins a network that has no profile yet, saving one when it succeeds.
    pub async fn join(&self, request: JoinRequest) -> Result<String, ApiError> {
        let snapshot = self.snapshot().await;
        let target = request
            .bssid
            .as_deref()
            .and_then(|bssid| snapshot.networks.iter().find(|network| network.bssid.eq_ignore_ascii_case(bssid)))
            .or_else(|| snapshot.networks.iter().find(|network| network.ssid == request.ssid));
        let security = match (target, request.hidden) {
            (_, true) if request.password.as_ref().is_some_and(|password| !password.is_empty()) => Security::WpaPsk,
            (_, true) => Security::None,
            (Some(network), false) => network.security_type,
            (None, false) => return Err(ApiError::new(ErrorCode::NotFound, "The network is out of range")),
        };
        if security.is_enterprise() {
            return Err(ApiError::new(ErrorCode::SecretsRequired, "This network needs an enterprise login"));
        }
        let settings = new_wifi_settings(&request.ssid, request.hidden, security, request.password.as_ref())?;
        let device = target
            .map(|network| network.device.clone())
            .or_else(|| snapshot.devices.iter().find(|device| device.device_type == model::DEVICE_TYPE_WIFI).map(|device| device.path.clone()))
            .ok_or_else(|| ApiError::new(ErrorCode::Unavailable, "No Wi-Fi device was found"))?;
        let specific = target.filter(|_| !request.hidden).map_or_else(|| "/".to_string(), |network| network.access_point.clone());
        let manager = self.proxy(MANAGER_PATH, IFACE_MANAGER).await?;
        let mut options: HashMap<&str, Variant> = HashMap::new();
        options.insert("persist", Variant::from("disk"));
        let device_path = object_path(&device)?;
        let specific_path = object_path(&specific)?;
        self.activated(|| async {
            let (_profile, active, _extra): (OwnedObjectPath, OwnedObjectPath, HashMap<String, OwnedVariant>) = manager
                .call("AddAndActivateConnection2", &(&settings, &device_path, &specific_path, &options))
                .await
                .map_err(error)?;
            Ok(active.to_string())
        })
        .await
    }

    /// Replaces a saved password and connects with it. Secrets the service holds elsewhere in the profile
    /// are read and sent back, since an update without them would clear them.
    pub async fn change_password(&self, uuid: &str, password: &Secret) -> Result<String, ApiError> {
        let path = self.find_profile(uuid).await?;
        let mut settings = self.settings_with_secrets(&path).await?;
        let security = profile_password_key(&settings)?;
        settings.entry("802-11-wireless-security".to_string()).or_default().insert(security.to_string(), owned(password.expose()));
        self.update(&path, &settings).await?;
        self.activate(uuid).await
    }

    /// The profile with every secret the service can give, for writing it back whole.
    pub async fn settings_with_secrets(&self, path: &str) -> Result<Settings, ApiError> {
        let mut settings = self.settings(path).await?;
        let proxy = self.proxy(path, IFACE_SETTINGS_CONNECTION).await?;
        for section in secret_sections(&settings) {
            let secrets: Result<Settings, _> = proxy.call("GetSecrets", &(section.as_str(),)).await;
            match secrets {
                Ok(secrets) => {
                    for (name, values) in secrets {
                        settings.entry(name).or_default().extend(values);
                    }
                }
                // A section with nothing stored answers with an error, not an empty result
                Err(failure) if reasons::dbus_error(&failure).code != ErrorCode::PermissionDenied => {}
                Err(failure) => return Err(error(failure)),
            }
        }
        Ok(settings)
    }

    async fn update(&self, path: &str, settings: &Settings) -> Result<(), ApiError> {
        let proxy = self.proxy(path, IFACE_SETTINGS_CONNECTION).await?;
        let args: HashMap<&str, Variant> = HashMap::new();
        let _: HashMap<String, OwnedVariant> = proxy.call("Update2", &(settings, UPDATE_TO_DISK, &args)).await.map_err(error)?;
        self.forget_profile(path);
        self.changed.notify_one();
        Ok(())
    }
}

/// A saved secret, found under one key of one section.
#[derive(Debug, Serialize)]
pub struct SavedSecret {
    pub section: String,
    pub key: String,
    pub value: String,
}

impl NmClient {
    /// A profile's saved secrets, by section, including the ones a VPN keeps in a dictionary of its own.
    /// Sections that have nothing stored are left out rather than treated as errors.
    pub async fn saved_secrets(&self, uuid: &str) -> Result<Vec<SavedSecret>, ApiError> {
        let path = self.find_profile(uuid).await?;
        let settings = self.settings(&path).await?;
        let proxy = self.proxy(&path, IFACE_SETTINGS_CONNECTION).await?;
        let mut found = Vec::new();
        for section in secret_sections(&settings) {
            let secrets: Result<Settings, _> = proxy.call("GetSecrets", &(section.as_str(),)).await;
            match secrets {
                Ok(secrets) => found.extend(secrets.iter().flat_map(|(name, values)| flatten_secrets(name, values))),
                Err(failure) if reasons::dbus_error(&failure).code == ErrorCode::PermissionDenied => return Err(error(failure)),
                Err(_) => {}
            }
        }
        Ok(found)
    }

    /// The one password a person would call "the Wi-Fi password", if the profile has one.
    pub async fn wifi_password(&self, uuid: &str) -> Result<Option<Secret>, ApiError> {
        let secrets = self.saved_secrets(uuid).await?;
        Ok(secrets
            .into_iter()
            .find(|secret| secret.section == "802-11-wireless-security" && matches!(secret.key.as_str(), "psk" | "wep-key0"))
            .map(|secret| Secret::new(secret.value)))
    }

    /// The Wi-Fi QR code of a saved network, ready to show.
    pub async fn wifi_qr_code(&self, uuid: &str) -> Result<String, ApiError> {
        let path = self.find_profile(uuid).await?;
        let settings = self.settings(&path).await?;
        let wireless = settings.get("802-11-wireless").ok_or_else(|| ApiError::invalid("This isn't a Wi-Fi network"))?;
        let ssid = String::from_utf8_lossy(&values::bytes(wireless, "ssid").unwrap_or_default()).into_owned();
        let hidden = values::flag(wireless, "hidden").unwrap_or(false);
        let password = self.wifi_password(uuid).await?;
        let security = model::profile_security(&settings);
        if security.is_personal() && password.is_none() {
            return Err(ApiError::new(ErrorCode::SecretsRequired, "No saved password was found for this network"));
        }
        share::qr_image(&share::wifi_qr_payload(&ssid, security, password.as_ref(), hidden)).await
    }

    pub async fn copy_wifi_password(&self, uuid: &str) -> Result<(), ApiError> {
        let password = self
            .wifi_password(uuid)
            .await?
            .ok_or_else(|| ApiError::new(ErrorCode::SecretsRequired, "No saved password was found for this network"))?;
        share::copy_to_clipboard(&password).await
    }

    /// Shares this computer's connection over Wi-Fi: a profile that lasts until it stops, on a device that
    /// can do it, preferring one that isn't busy.
    pub async fn start_hotspot(&self, ssid: &str, password: Option<&Secret>) -> Result<String, ApiError> {
        let settings = hotspot_settings(ssid, password)?;
        let snapshot = self.snapshot().await;
        let device = snapshot
            .devices
            .iter()
            .filter(|device| device.device_type == model::DEVICE_TYPE_WIFI && device.supports_ap)
            .min_by_key(|device| device.state == 100)
            .ok_or_else(|| ApiError::new(ErrorCode::Unavailable, "No Wi-Fi device here can share a connection"))?;
        let manager = self.proxy(MANAGER_PATH, IFACE_MANAGER).await?;
        let mut options: HashMap<&str, Variant> = HashMap::new();
        options.insert("persist", Variant::from("volatile"));
        let device_path = object_path(&device.path)?;
        let root = object_path("/")?;
        self.activated(|| async {
            let (_profile, active, _extra): (OwnedObjectPath, OwnedObjectPath, HashMap<String, OwnedVariant>) = manager
                .call("AddAndActivateConnection2", &(&settings, &device_path, &root, &options))
                .await
                .map_err(error)?;
            Ok(active.to_string())
        })
        .await
    }

    pub async fn stop_hotspot(&self) -> Result<(), ApiError> {
        let snapshot = self.snapshot().await;
        let manager = self.proxy(MANAGER_PATH, IFACE_MANAGER).await?;
        for active in snapshot.active_connections.iter().filter(|active| active.hotspot) {
            manager.call::<_, _, ()>("DeactivateConnection", &(object_path(&active.path)?,)).await.map_err(error)?;
        }
        Ok(())
    }

    pub async fn wifi_enabled(&self) -> Result<bool, ApiError> {
        self.proxy(MANAGER_PATH, IFACE_MANAGER).await?.get_property("WirelessEnabled").await.map_err(error)
    }

    pub async fn wwan_enabled(&self) -> Result<bool, ApiError> {
        self.proxy(MANAGER_PATH, IFACE_MANAGER).await?.get_property("WwanEnabled").await.map_err(error)
    }

    pub async fn set_wwan_enabled(&self, enabled: bool) -> Result<(), ApiError> {
        self.set_manager_flag("WwanEnabled", enabled).await
    }
}

/// What an editor needs to show a profile. Secrets stay out; the form asks for them when they're to be shown.
#[derive(Debug, Serialize)]
pub struct ProfileForm {
    pub uuid: String,
    pub revision: String,
    pub fields: serde_json::Map<String, serde_json::Value>,
}

impl NmClient {
    pub async fn profile_form(&self, uuid: &str) -> Result<ProfileForm, ApiError> {
        let path = self.find_profile(uuid).await?;
        let settings = self.settings(&path).await?;
        Ok(ProfileForm { uuid: uuid.to_string(), revision: form::revision(&settings), fields: form::to_form(&settings) })
    }

    /// Applies a form's edits to the profile as it is now, secrets included, as the service wants it whole.
    /// `revision` is what the editor read; if the profile has changed since, nothing is written.
    pub async fn save_profile(&self, uuid: &str, revision: Option<&str>, changes: &serde_json::Map<String, serde_json::Value>) -> Result<(), ApiError> {
        let path = self.find_profile(uuid).await?;
        if let Some(expected) = revision {
            if form::revision(&self.settings(&path).await?) != expected {
                return Err(ApiError::new(ErrorCode::Conflict, "This connection was changed elsewhere while you were editing it"));
            }
        }
        let mut settings = self.settings_with_secrets(&path).await?;
        form::apply_changes(&mut settings, changes)?;
        self.update(&path, &settings).await
    }

    /// Creates a saved profile; returns its UUID.
    pub async fn add_profile(&self, connection_type: &str, vpn_service: Option<&str>, changes: &serde_json::Map<String, serde_json::Value>) -> Result<String, ApiError> {
        let mut settings = form::new_profile(connection_type, vpn_service)?;
        form::apply_changes(&mut settings, changes)?;
        let section = settings.get("connection").ok_or_else(|| ApiError::invalid("connection.id: a name is required"))?;
        if values::text_or_empty(section, "id").is_empty() {
            return Err(ApiError::invalid("connection.id: a name is required"));
        }
        let uuid = values::text_or_empty(section, "uuid");
        let manager = self.proxy(SETTINGS_PATH, IFACE_SETTINGS).await?;
        let args: HashMap<&str, Variant> = HashMap::new();
        let (_path, _result): (OwnedObjectPath, HashMap<String, OwnedVariant>) = manager.call("AddConnection2", &(&settings, UPDATE_TO_DISK, &args)).await.map_err(error)?;
        self.changed.notify_one();
        Ok(uuid)
    }

    /// Reads a VPN configuration file with the matching plugin (or NetworkManager's WireGuard reader);
    /// returns the UUID of the profile it became. Only the file's path goes on the command line.
    pub async fn import_vpn(&self, path: &str) -> Result<String, ApiError> {
        let text = tokio::fs::read_to_string(path).await.map_err(|_| ApiError::new(ErrorCode::NotFound, "The file couldn't be read"))?;
        let kind = vpn_file_kind(path, &text);
        let output = Command::new("nmcli")
            .args(["connection", "import", "type", kind, "file", path])
            .env("LC_ALL", "C")
            .env("LANG", "C")
            .stdin(Stdio::null())
            .output()
            .await
            .map_err(|_| ApiError::new(ErrorCode::Unavailable, "nmcli is not installed"))?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let message = stderr.lines().find(|line| !line.trim().is_empty()).unwrap_or("The file couldn't be imported").trim_start_matches("Error: ");
            return Err(ApiError::new(ErrorCode::Failed, message));
        }
        self.changed.notify_one();
        imported_uuid(&String::from_utf8_lossy(&output.stdout)).ok_or_else(|| ApiError::new(ErrorCode::Failed, "The file was imported, but the new connection couldn't be found"))
    }

    /// Writes a VPN profile out as a configuration file, for this person alone to read.
    pub async fn export_vpn(&self, uuid: &str, target: &str) -> Result<(), ApiError> {
        let path = self.find_profile(uuid).await?;
        let settings = self.settings(&path).await?;
        if settings.contains_key("wireguard") {
            let secrets = self.settings_with_secrets(&path).await?;
            let text = Zeroizing::new(form::wireguard_config(&settings, &secrets)?);
            let mut file = tokio::fs::OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .mode(0o600)
                .open(target)
                .await
                .map_err(|_| ApiError::new(ErrorCode::Failed, "The file couldn't be written"))?;
            file.write_all(text.as_bytes()).await.map_err(|_| ApiError::new(ErrorCode::Failed, "The file couldn't be written"))?;
            return Ok(());
        }
        let output = Command::new("nmcli")
            .args(["connection", "export", "uuid", uuid, target])
            .env("LC_ALL", "C")
            .env("LANG", "C")
            .stdin(Stdio::null())
            .output()
            .await
            .map_err(|_| ApiError::new(ErrorCode::Unavailable, "nmcli is not installed"))?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ApiError::new(ErrorCode::Failed, stderr.lines().next().unwrap_or("The connection couldn't be exported").trim_start_matches("Error: ")));
        }
        // Permissions are set after the fact only if the plugin wrote the file with its own
        let _ = tokio::fs::set_permissions(target, std::os::unix::fs::PermissionsExt::from_mode(0o600)).await;
        Ok(())
    }
}

fn vpn_file_kind(path: &str, text: &str) -> &'static str {
    if path.ends_with(".conf") && text.contains("[Interface]") {
        "wireguard"
    } else {
        "openvpn"
    }
}

/// The UUID in `Connection 'x' (uuid) successfully added.`
fn imported_uuid(output: &str) -> Option<String> {
    let inside = output.rsplit_once('(')?.1;
    let uuid = inside.split_once(')')?.0;
    (uuid.len() == 36 && uuid.bytes().all(|byte| byte.is_ascii_hexdigit() || byte == b'-')).then(|| uuid.to_string())
}

/// One setting's secrets as a flat list. A VPN keeps its in a nested string dictionary.
fn flatten_secrets(section: &str, secrets: &Props) -> Vec<SavedSecret> {
    let mut found = Vec::new();
    for (key, value) in secrets {
        match values::to_json(value) {
            serde_json::Value::String(text) => found.push(SavedSecret { section: section.to_string(), key: key.clone(), value: text }),
            serde_json::Value::Object(nested) => {
                for (inner, value) in nested {
                    if let serde_json::Value::String(text) = value {
                        found.push(SavedSecret { section: section.to_string(), key: inner, value: text });
                    }
                }
            }
            _ => {}
        }
    }
    found.sort_by(|a, b| (&a.section, &a.key).cmp(&(&b.section, &b.key)));
    found
}

/// A shared-connection profile, in access point mode. Without a password the network is open, as in plasma-nm.
pub fn hotspot_settings(ssid: &str, password: Option<&Secret>) -> Result<Settings, ApiError> {
    if !super::validate::ssid(ssid) {
        return Err(ApiError::invalid("A network name is 1 to 32 bytes long"));
    }
    let password = password.filter(|password| !password.is_empty());
    let mut settings = Settings::new();
    let mut connection = Props::new();
    connection.insert("type".to_string(), owned("802-11-wireless"));
    connection.insert("id".to_string(), owned(ssid));
    connection.insert("autoconnect".to_string(), owned(false));
    settings.insert("connection".to_string(), connection);
    let mut wireless = Props::new();
    wireless.insert("ssid".to_string(), owned(ssid.as_bytes().to_vec()));
    wireless.insert("mode".to_string(), owned("ap"));
    settings.insert("802-11-wireless".to_string(), wireless);
    let mut ipv4 = Props::new();
    ipv4.insert("method".to_string(), owned("shared"));
    settings.insert("ipv4".to_string(), ipv4);
    if let Some(password) = password {
        if !super::validate::wpa_psk(password.expose()) {
            return Err(ApiError::new(ErrorCode::WrongSecret, "A password is 8 to 63 characters long"));
        }
        let mut security = Props::new();
        security.insert("key-mgmt".to_string(), owned("wpa-psk"));
        security.insert("psk".to_string(), owned(password.expose()));
        settings.insert("802-11-wireless-security".to_string(), security);
    }
    Ok(settings)
}

pub struct JoinRequest {
    pub ssid: String,
    pub bssid: Option<String>,
    pub password: Option<Secret>,
    pub hidden: bool,
}

/// A new profile for a Wi-Fi network; the service fills in the name and the rest.
pub fn new_wifi_settings(ssid: &str, hidden: bool, security: Security, password: Option<&Secret>) -> Result<Settings, ApiError> {
    if security.is_personal() && password.is_none_or(Secret::is_empty) {
        return Err(ApiError::new(ErrorCode::SecretsRequired, "This network needs a password"));
    }
    wifi_settings(ssid, hidden, security, password)
}

/// An owned activation can ask its secret agent for a missing password later.
pub(super) fn wifi_settings(ssid: &str, hidden: bool, security: Security, password: Option<&Secret>) -> Result<Settings, ApiError> {
    if !super::validate::ssid(ssid) {
        return Err(ApiError::invalid("A network name is 1 to 32 bytes long"));
    }
    let password = password.filter(|password| !password.is_empty());
    let mut settings = Settings::new();
    let mut connection = Props::new();
    connection.insert("type".to_string(), owned("802-11-wireless"));
    connection.insert("id".to_string(), owned(ssid));
    settings.insert("connection".to_string(), connection);
    let mut wireless = Props::new();
    wireless.insert("ssid".to_string(), owned(ssid.as_bytes().to_vec()));
    wireless.insert("mode".to_string(), owned("infrastructure"));
    if hidden {
        wireless.insert("hidden".to_string(), owned(true));
    }
    settings.insert("802-11-wireless".to_string(), wireless);
    if !matches!(security, Security::None) {
        let mut section = Props::new();
        section.insert("key-mgmt".to_string(), owned(security.key_mgmt()));
        if let Some(password) = password {
            match security {
                Security::Wep => {
                    if !super::validate::wep_key(password.expose()) {
                        return Err(ApiError::new(ErrorCode::WrongSecret, "A WEP key is 5 or 13 characters, or 10 or 26 hex digits"));
                    }
                    section.insert("wep-key0".to_string(), owned(password.expose()));
                }
                Security::WpaPsk => {
                    if !super::validate::wpa_psk(password.expose()) {
                        return Err(ApiError::new(ErrorCode::WrongSecret, "A password is 8 to 63 characters long"));
                    }
                    section.insert("psk".to_string(), owned(password.expose()));
                }
                Security::Sae => {
                    section.insert("psk".to_string(), owned(password.expose()));
                }
                _ => {}
            }
        }
        settings.insert("802-11-wireless-security".to_string(), section);
    }
    Ok(settings)
}

/// Which key of the security section holds this profile's typed password.
fn profile_password_key(settings: &Settings) -> Result<&'static str, ApiError> {
    match model::profile_security(settings) {
        Security::WpaPsk | Security::Sae => Ok("psk"),
        Security::Wep => Ok("wep-key0"),
        _ => Err(ApiError::invalid("This network has no single password to change")),
    }
}

/// The sections whose secrets the service keeps or an agent can supply. "Always ask" and "not required"
/// have nothing stored; plasma-nm skips them for the same reason.
pub fn secret_sections(settings: &Settings) -> Vec<String> {
    const CANDIDATES: [(&str, &[&str]); 9] = [
        ("802-11-wireless-security", &["psk-flags", "wep-key-flags", "leap-password-flags"]),
        ("802-1x", &["password-flags", "private-key-password-flags", "phase2-private-key-password-flags", "pin-flags"]),
        ("wireguard", &["private-key-flags"]),
        ("gsm", &["password-flags", "pin-flags"]),
        ("cdma", &["password-flags"]),
        ("pppoe", &["password-flags"]),
        ("adsl", &["password-flags"]),
        ("vpn", &[]),
        ("wifi-p2p", &[]),
    ];
    CANDIDATES
        .iter()
        .filter(|(name, flags)| {
            let Some(section) = settings.get(*name) else { return false };
            if *name == "vpn" {
                return true;
            }
            // No flag set at all means the default: stored by the service
            let mut present = flags.iter().filter_map(|flag| values::number(section, flag)).peekable();
            present.peek().is_none() || present.any(|flags| flags & 0b110 == 0)
        })
        .map(|(name, _)| (*name).to_string())
        .collect()
}

/// VPN kinds this system has a plugin for, from `/usr/lib/NetworkManager/VPN` and `/etc/NetworkManager/VPN`.
pub fn vpn_plugins() -> Vec<String> {
    let directories = std::env::var("VELORA_NM_VPN_DIRS").unwrap_or_else(|_| "/usr/lib/NetworkManager/VPN:/etc/NetworkManager/VPN".to_string());
    let mut services: Vec<String> = directories
        .split(':')
        .filter_map(|directory| std::fs::read_dir(directory).ok())
        .flatten()
        .filter_map(Result::ok)
        .filter(|entry| entry.path().extension().is_some_and(|extension| extension == "name"))
        .filter_map(|entry| vpn_service(&entry.path()))
        .collect();
    services.sort();
    services.dedup();
    services
}

fn vpn_service(path: &Path) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    text.lines().find_map(|line| line.strip_prefix("service=")).map(|service| service.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::values::build::{owned as value, props};

    #[test]
    fn a_new_network_gets_the_key_its_security_needs() {
        let password = Secret::new("correct horse");
        let settings = new_wifi_settings("Home", false, Security::WpaPsk, Some(&password)).unwrap();
        let section = &settings["802-11-wireless-security"];
        assert_eq!(values::text(section, "key-mgmt").as_deref(), Some("wpa-psk"));
        assert_eq!(values::text(section, "psk").as_deref(), Some("correct horse"));
        assert_eq!(values::bytes(&settings["802-11-wireless"], "ssid").unwrap(), b"Home");
        assert_eq!(values::flag(&settings["802-11-wireless"], "hidden"), None);

        let settings = new_wifi_settings("Home", false, Security::Sae, Some(&Secret::new("short"))).unwrap();
        assert_eq!(values::text(&settings["802-11-wireless-security"], "key-mgmt").as_deref(), Some("sae"));

        let settings = new_wifi_settings("Old", false, Security::Wep, Some(&Secret::new("12345"))).unwrap();
        assert_eq!(values::text(&settings["802-11-wireless-security"], "wep-key0").as_deref(), Some("12345"));
        assert_eq!(values::text(&settings["802-11-wireless-security"], "key-mgmt").as_deref(), Some("none"));
    }

    #[test]
    fn open_and_owe_networks_need_no_password() {
        let settings = new_wifi_settings("Cafe", false, Security::None, None).unwrap();
        assert!(!settings.contains_key("802-11-wireless-security"));
        let settings = new_wifi_settings("Cafe", false, Security::Owe, None).unwrap();
        assert_eq!(values::text(&settings["802-11-wireless-security"], "key-mgmt").as_deref(), Some("owe"));
        assert!(!settings["802-11-wireless-security"].contains_key("psk"));
    }

    #[test]
    fn hidden_networks_are_marked() {
        let settings = new_wifi_settings("Secret", true, Security::None, None).unwrap();
        assert_eq!(values::flag(&settings["802-11-wireless"], "hidden"), Some(true));
    }

    #[test]
    fn bad_input_is_refused_before_it_goes_out() {
        assert_eq!(new_wifi_settings("", false, Security::None, None).unwrap_err().code, ErrorCode::Invalid);
        assert_eq!(new_wifi_settings(&"x".repeat(33), false, Security::None, None).unwrap_err().code, ErrorCode::Invalid);
        assert_eq!(new_wifi_settings("Home", false, Security::WpaPsk, None).unwrap_err().code, ErrorCode::SecretsRequired);
        assert_eq!(new_wifi_settings("Home", false, Security::WpaPsk, Some(&Secret::default())).unwrap_err().code, ErrorCode::SecretsRequired);
        assert_eq!(new_wifi_settings("Home", false, Security::WpaPsk, Some(&Secret::new("short"))).unwrap_err().code, ErrorCode::WrongSecret);
        assert_eq!(new_wifi_settings("Home", false, Security::Wep, Some(&Secret::new("bad"))).unwrap_err().code, ErrorCode::WrongSecret);
    }

    #[test]
    fn secret_sections_skip_what_is_never_stored() {
        let mut settings = Settings::new();
        settings.insert("802-11-wireless-security".to_string(), props([("key-mgmt", value("wpa-psk"))]));
        settings.insert("connection".to_string(), Props::new());
        assert_eq!(secret_sections(&settings), ["802-11-wireless-security"]);

        settings.insert("802-11-wireless-security".to_string(), props([("psk-flags", value(2u32))]));
        assert!(secret_sections(&settings).is_empty());
        settings.insert("802-11-wireless-security".to_string(), props([("psk-flags", value(4u32))]));
        assert!(secret_sections(&settings).is_empty());
        settings.insert("802-11-wireless-security".to_string(), props([("psk-flags", value(1u32))]));
        assert_eq!(secret_sections(&settings), ["802-11-wireless-security"]);

        settings.insert("vpn".to_string(), Props::new());
        settings.insert("802-1x".to_string(), props([("password-flags", value(0u32))]));
        assert_eq!(secret_sections(&settings), ["802-11-wireless-security", "802-1x", "vpn"]);
    }

    #[test]
    fn vpn_files_are_told_apart_by_what_they_hold() {
        assert_eq!(vpn_file_kind("/x/home.ovpn", "client\nremote x"), "openvpn");
        assert_eq!(vpn_file_kind("/x/wg0.conf", "[Interface]\nPrivateKey = y"), "wireguard");
        assert_eq!(vpn_file_kind("/x/client.conf", "client\nremote x"), "openvpn");
    }

    #[test]
    fn the_new_profiles_id_comes_from_the_tools_message() {
        assert_eq!(imported_uuid("Connection 'home' (0a1b2c3d-1111-2222-3333-444455556666) successfully added.\n").as_deref(), Some("0a1b2c3d-1111-2222-3333-444455556666"));
        assert_eq!(imported_uuid("something else"), None);
        assert_eq!(imported_uuid("Connection 'x' (not-a-uuid) added"), None);
    }

    #[test]
    fn hotspots_share_the_connection_on_an_access_point() {
        let settings = hotspot_settings("Laptop", Some(&Secret::new("12345678"))).unwrap();
        assert_eq!(values::text(&settings["802-11-wireless"], "mode").as_deref(), Some("ap"));
        assert_eq!(values::text(&settings["ipv4"], "method").as_deref(), Some("shared"));
        assert_eq!(values::flag(&settings["connection"], "autoconnect"), Some(false));
        assert_eq!(values::text(&settings["802-11-wireless-security"], "psk").as_deref(), Some("12345678"));
        let open = hotspot_settings("Laptop", None).unwrap();
        assert!(!open.contains_key("802-11-wireless-security"));
        assert_eq!(hotspot_settings("Laptop", Some(&Secret::new("short"))).unwrap_err().code, ErrorCode::WrongSecret);
        assert_eq!(hotspot_settings("", None).unwrap_err().code, ErrorCode::Invalid);
    }

    #[test]
    fn saved_secrets_flatten_with_vpn_dictionaries_opened_up() {
        let mut vpn = HashMap::new();
        vpn.insert("password".to_string(), "abc".to_string());
        vpn.insert("cert-pass".to_string(), "def".to_string());
        let secrets = props([("secrets", value(vpn)), ("skipped", value(5u32))]);
        let found = flatten_secrets("vpn", &secrets);
        assert_eq!(found.iter().map(|secret| (secret.key.as_str(), secret.value.as_str())).collect::<Vec<_>>(), [("cert-pass", "def"), ("password", "abc")]);
        let wifi = props([("psk", value("hunter2"))]);
        assert_eq!(flatten_secrets("802-11-wireless-security", &wifi)[0].value, "hunter2");
    }

    #[test]
    fn the_password_key_depends_on_the_security() {
        let with = |key_mgmt: &str| {
            let mut settings = Settings::new();
            settings.insert("802-11-wireless-security".to_string(), props([("key-mgmt", value(key_mgmt))]));
            profile_password_key(&settings)
        };
        assert_eq!(with("wpa-psk"), Ok("psk"));
        assert_eq!(with("sae"), Ok("psk"));
        assert_eq!(with("none"), Ok("wep-key0"));
        assert_eq!(with("wpa-eap").unwrap_err().code, ErrorCode::Invalid);
    }

    #[test]
    fn vpn_plugins_are_read_from_their_name_files() {
        let directory = std::env::temp_dir().join(format!("velora-vpn-test-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let file = directory.join("nm-openvpn-service.name");
        std::fs::write(&file, "[VPN Connection]\nname=openvpn\nservice=org.freedesktop.NetworkManager.openvpn\n").unwrap();
        assert_eq!(vpn_service(&file).as_deref(), Some("org.freedesktop.NetworkManager.openvpn"));
        std::fs::write(&file, "[VPN Connection]\nname=broken\n").unwrap();
        assert_eq!(vpn_service(&file), None);
        std::fs::remove_dir_all(&directory).unwrap();
    }
}
