//! A stand-in for NetworkManager with the parts of its behaviour the daemon relies on. In particular an
//! `Update2` without secrets clears them, and failed activations report through the same signals.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use zbus::object_server::SignalEmitter;
use zbus::{fdo, interface, Connection, ObjectPath, OwnedObjectPath, OwnedVariant, Variant};

pub const BUS_NAME: &str = "org.freedesktop.NetworkManager";
const MANAGER_PATH: &str = "/org/freedesktop/NetworkManager";
const SETTINGS_PATH: &str = "/org/freedesktop/NetworkManager/Settings";
const WIFI_DEVICE_PATH: &str = "/org/freedesktop/NetworkManager/Devices/2";
const WIRED_DEVICE_PATH: &str = "/org/freedesktop/NetworkManager/Devices/1";

pub type Props = HashMap<String, OwnedVariant>;
pub type Settings = HashMap<String, Props>;

pub fn value<'a>(value: impl Into<Variant<'a>>) -> OwnedVariant {
    value.into().try_into_owned().expect("no file descriptors in test values")
}

fn path(text: &str) -> OwnedObjectPath {
    OwnedObjectPath::try_from(text.to_string()).expect("paths here are valid")
}

fn none() -> OwnedObjectPath {
    path("/")
}

/// What the next activation does.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Outcome {
    Succeed,
    /// Reaches a failed state, reporting these reasons.
    Fail { device_reason: u32, active_reason: u32 },
    /// Refused by the permission check.
    Deny,
}

#[derive(zbus::DBusError, Debug)]
#[zbus(prefix = "org.freedesktop.NetworkManager")]
pub enum NmError {
    #[zbus(error)]
    ZBus(zbus::Error),
    PermissionDenied(String),
    UnknownConnection(String),
    #[zbus(name = "Settings.InvalidConnection")]
    InvalidConnection(String),
    #[zbus(name = "AgentManager.NoSecrets")]
    NoSecrets(String),
}

const SECRET_KEYS: [&str; 13] = [
    "psk", "wep-key0", "wep-key1", "wep-key2", "wep-key3", "leap-password", "password", "private-key-password",
    "phase2-private-key-password", "pin", "private-key", "secrets", "preshared-key",
];

fn split_secrets(settings: &Settings) -> (Settings, Settings) {
    let mut plain = Settings::new();
    let mut secret = Settings::new();
    for (section, props) in settings {
        for (key, entry) in props {
            let target = if SECRET_KEYS.contains(&key.as_str()) { &mut secret } else { &mut plain };
            target.entry(section.clone()).or_default().insert(key.clone(), entry.clone());
        }
        plain.entry(section.clone()).or_default();
    }
    (plain, secret)
}

#[derive(Default)]
struct Shared {
    outcome: Option<Outcome>,
    next_profile: u32,
    next_active: u32,
    next_ap: u32,
    /// Path → (settings without secrets, secrets)
    profiles: HashMap<String, (Settings, Settings)>,
    /// Names of the methods called, without parameters, for tests of what was asked
    calls: Vec<String>,
    /// Secrets queries that should fail as if nothing were stored
    no_secrets: bool,
    deny_secrets: bool,
    scan_refused: bool,
    /// The bus name of the registered secret agent
    agent: Option<String>,
}

type SharedState = Arc<Mutex<Shared>>;

struct Manager {
    shared: SharedState,
    connection: Connection,
    wifi_enabled: bool,
    wifi_hardware: bool,
    wwan_enabled: bool,
    connectivity: u32,
    active: Vec<OwnedObjectPath>,
    devices: Vec<OwnedObjectPath>,
}

#[interface(name = "org.freedesktop.NetworkManager")]
impl Manager {
    #[zbus(property, name = "NetworkingEnabled")]
    fn networking_enabled(&self) -> bool {
        true
    }
    #[zbus(property, name = "WirelessEnabled")]
    fn wireless_enabled(&self) -> bool {
        self.wifi_enabled
    }
    #[zbus(property, name = "WirelessEnabled")]
    fn set_wireless_enabled(&mut self, enabled: bool) {
        self.shared.lock().expect("test state").calls.push(format!("SetWirelessEnabled {enabled}"));
        self.wifi_enabled = enabled;
    }
    #[zbus(property, name = "WirelessHardwareEnabled")]
    fn wireless_hardware_enabled(&self) -> bool {
        self.wifi_hardware
    }
    #[zbus(property, name = "WwanEnabled")]
    fn wwan_enabled(&self) -> bool {
        self.wwan_enabled
    }
    #[zbus(property, name = "WwanEnabled")]
    fn set_wwan_enabled(&mut self, enabled: bool) {
        self.shared.lock().expect("test state").calls.push(format!("SetWwanEnabled {enabled}"));
        self.wwan_enabled = enabled;
    }
    #[zbus(property, name = "WwanHardwareEnabled")]
    fn wwan_hardware_enabled(&self) -> bool {
        false
    }
    #[zbus(property, name = "Connectivity")]
    fn connectivity(&self) -> u32 {
        self.connectivity
    }
    #[zbus(property, name = "ActiveConnections")]
    fn active_connections(&self) -> Vec<OwnedObjectPath> {
        self.active.clone()
    }
    #[zbus(property, name = "Devices")]
    fn devices(&self) -> Vec<OwnedObjectPath> {
        self.devices.clone()
    }

    #[zbus(name = "ActivateConnection")]
    async fn activate_connection(
        &mut self,
        connection: ObjectPath<'_>,
        _device: ObjectPath<'_>,
        _specific: ObjectPath<'_>,
    ) -> Result<OwnedObjectPath, NmError> {
        let outcome = {
            let mut shared = self.shared.lock().expect("test state");
            shared.calls.push("ActivateConnection".to_string());
            if !shared.profiles.contains_key(connection.as_str()) {
                return Err(NmError::UnknownConnection(connection.to_string()));
            }
            shared.outcome.unwrap_or(Outcome::Succeed)
        };
        if outcome == Outcome::Deny {
            return Err(NmError::PermissionDenied("Not authorized to control networking.".to_string()));
        }
        start_activation(self.connection.clone(), Arc::clone(&self.shared), connection.to_string(), outcome).await
    }

    #[zbus(name = "AddAndActivateConnection2")]
    async fn add_and_activate_connection2(
        &mut self,
        settings: Settings,
        _device: ObjectPath<'_>,
        _specific: ObjectPath<'_>,
        options: HashMap<String, OwnedVariant>,
    ) -> Result<(OwnedObjectPath, OwnedObjectPath, HashMap<String, OwnedVariant>), NmError> {
        let outcome = {
            let mut shared = self.shared.lock().expect("test state");
            let persist = options.get("persist").and_then(|entry| entry.downcast_ref::<&str>().ok().map(str::to_string)).unwrap_or_default();
            shared.calls.push(format!("AddAndActivateConnection2 persist={persist}"));
            shared.outcome.unwrap_or(Outcome::Succeed)
        };
        if outcome == Outcome::Deny {
            return Err(NmError::PermissionDenied("Not authorized to control networking.".to_string()));
        }
        let mut settings = settings;
        let section = settings.entry("connection".to_string()).or_default();
        section.entry("uuid".to_string()).or_insert_with(|| value(format!("generated-{}", std::process::id())));
        let profile = add_profile(&self.connection, &self.shared, settings).await.map_err(NmError::ZBus)?;
        let active = start_activation(self.connection.clone(), Arc::clone(&self.shared), profile.to_string(), outcome).await?;
        Ok((profile, active, HashMap::new()))
    }

    #[zbus(name = "DeactivateConnection")]
    async fn deactivate_connection(&mut self, active: ObjectPath<'_>) -> Result<(), NmError> {
        self.shared.lock().expect("test state").calls.push("DeactivateConnection".to_string());
        let server = self.connection.object_server();
        let reference = server
            .interface::<_, ActiveConnection>(active.as_str())
            .await
            .map_err(|_| NmError::UnknownConnection(active.to_string()))?;
        ActiveConnection::state_signal(reference.signal_emitter(), 4, 2).await.map_err(NmError::ZBus)?;
        server.remove::<ActiveConnection, _>(active.as_str()).await.map_err(NmError::ZBus)?;
        Ok(())
    }
}

/// Runs the state changes of an activation shortly after the request returns, as the real one does.
async fn start_activation(connection: Connection, shared: SharedState, profile: String, outcome: Outcome) -> Result<OwnedObjectPath, NmError> {
    let (active_path, uuid, id, kind) = {
        let mut state = shared.lock().expect("test state");
        state.next_active += 1;
        let number = state.next_active;
        let settings = &state.profiles[&profile].0;
        let section = &settings["connection"];
        let read = |key: &str| section.get(key).and_then(|entry| entry.downcast_ref::<&str>().ok().map(str::to_string)).unwrap_or_default();
        (format!("/org/freedesktop/NetworkManager/ActiveConnection/{number}"), read("uuid"), read("id"), read("type"))
    };
    let device = if kind == "802-11-wireless" { WIFI_DEVICE_PATH } else { WIRED_DEVICE_PATH };
    let object = ActiveConnection { uuid, id, kind, state: 1, devices: vec![path(device)], profile: path(&profile) };
    connection.object_server().at(active_path.as_str(), object).await.map_err(NmError::ZBus)?;
    let reply = path(&active_path);
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(30)).await;
        let server = connection.object_server();
        let Ok(reference) = server.interface::<_, ActiveConnection>(active_path.as_str()).await else { return };
        let Ok(device_reference) = server.interface::<_, Device>(device).await else { return };
        match outcome {
            Outcome::Succeed | Outcome::Deny => {
                device_reference.get_mut().await.state = 100;
                let _ = Device::state_signal(device_reference.signal_emitter(), 100, 30, 0).await;
                reference.get_mut().await.state = 2;
                let _ = ActiveConnection::state_signal(reference.signal_emitter(), 2, 1).await;
            }
            Outcome::Fail { device_reason, active_reason } => {
                let _ = Device::state_signal(device_reference.signal_emitter(), 120, 50, device_reason).await;
                let _ = Device::state_signal(device_reference.signal_emitter(), 30, 120, 0).await;
                let _ = ActiveConnection::state_signal(reference.signal_emitter(), 4, active_reason).await;
                let _ = server.remove::<ActiveConnection, _>(active_path.as_str()).await;
            }
        }
    });
    Ok(reply)
}

struct ActiveConnection {
    uuid: String,
    id: String,
    kind: String,
    state: u32,
    devices: Vec<OwnedObjectPath>,
    profile: OwnedObjectPath,
}

#[interface(name = "org.freedesktop.NetworkManager.Connection.Active")]
impl ActiveConnection {
    #[zbus(property, name = "Uuid")]
    fn uuid(&self) -> String {
        self.uuid.clone()
    }
    #[zbus(property, name = "Id")]
    fn id(&self) -> String {
        self.id.clone()
    }
    #[zbus(property, name = "Type")]
    fn kind(&self) -> String {
        self.kind.clone()
    }
    #[zbus(property, name = "State")]
    fn state(&self) -> u32 {
        self.state
    }
    #[zbus(property, name = "Vpn")]
    fn vpn(&self) -> bool {
        self.kind == "vpn"
    }
    #[zbus(property, name = "Devices")]
    fn devices(&self) -> Vec<OwnedObjectPath> {
        self.devices.clone()
    }
    #[zbus(property, name = "Connection")]
    fn connection(&self) -> OwnedObjectPath {
        self.profile.clone()
    }
    #[zbus(signal, name = "StateChanged")]
    async fn state_signal(emitter: &SignalEmitter<'_>, state: u32, reason: u32) -> zbus::Result<()>;
}

struct SettingsService {
    shared: SharedState,
}

#[interface(name = "org.freedesktop.NetworkManager.Settings")]
impl SettingsService {
    #[zbus(name = "GetConnectionByUuid")]
    fn get_connection_by_uuid(&self, uuid: String) -> Result<OwnedObjectPath, NmError> {
        let shared = self.shared.lock().expect("test state");
        shared
            .profiles
            .iter()
            .find(|(_, (settings, _))| {
                settings.get("connection").and_then(|section| section.get("uuid")).and_then(|entry| entry.downcast_ref::<&str>().ok().map(|text| text == uuid)).unwrap_or(false)
            })
            .map(|(profile, _)| path(profile))
            .ok_or(NmError::InvalidConnection(format!("No connection with the UUID '{uuid}' could be found.")))
    }

    #[zbus(name = "AddConnection2")]
    async fn add_connection2(
        &self,
        settings: Settings,
        flags: u32,
        _args: HashMap<String, OwnedVariant>,
        #[zbus(connection)] connection: &Connection,
    ) -> Result<(OwnedObjectPath, HashMap<String, OwnedVariant>), NmError> {
        self.shared.lock().expect("test state").calls.push(format!("AddConnection2 flags={flags}"));
        let has_uuid = settings.get("connection").and_then(|section| section.get("uuid")).is_some();
        if !has_uuid {
            return Err(NmError::InvalidConnection("connection.uuid: property is missing".to_string()));
        }
        let profile = add_profile(connection, &self.shared, settings).await.map_err(NmError::ZBus)?;
        Ok((profile, HashMap::new()))
    }
}

struct Profile {
    shared: SharedState,
    connection: Connection,
    path: String,
}

#[interface(name = "org.freedesktop.NetworkManager.Settings.Connection")]
impl Profile {
    #[zbus(property, name = "Unsaved")]
    fn unsaved(&self) -> bool {
        false
    }
    #[zbus(property, name = "Flags")]
    fn flags(&self) -> u32 {
        0
    }
    #[zbus(property, name = "Filename")]
    fn filename(&self) -> String {
        String::new()
    }

    #[zbus(name = "GetSettings")]
    fn get_settings(&self) -> Result<Settings, NmError> {
        let shared = self.shared.lock().expect("test state");
        shared.profiles.get(&self.path).map(|(plain, _)| plain.clone()).ok_or(NmError::UnknownConnection(self.path.clone()))
    }

    #[zbus(name = "GetSecrets")]
    fn get_secrets(&self, section: String) -> Result<Settings, NmError> {
        let mut shared = self.shared.lock().expect("test state");
        shared.calls.push(format!("GetSecrets {section}"));
        if shared.deny_secrets {
            return Err(NmError::PermissionDenied("Not authorized to read secrets.".to_string()));
        }
        if shared.no_secrets {
            return Err(NmError::NoSecrets("No agents were available for this request.".to_string()));
        }
        let (_, secrets) = shared.profiles.get(&self.path).ok_or(NmError::UnknownConnection(self.path.clone()))?;
        Ok(secrets.iter().filter(|(name, _)| **name == section).map(|(name, props)| (name.clone(), props.clone())).collect())
    }

    #[zbus(name = "Update2")]
    async fn update2(
        &mut self,
        settings: Settings,
        flags: u32,
        _args: HashMap<String, OwnedVariant>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> Result<HashMap<String, OwnedVariant>, NmError> {
        {
            let mut shared = self.shared.lock().expect("test state");
            shared.calls.push(format!("Update2 flags={flags}"));
            let (plain, secrets) = split_secrets(&settings);
            // As the real service: what isn't in the update, secrets included, is gone
            shared.profiles.insert(self.path.clone(), (plain, secrets));
        }
        Self::updated(&emitter).await.map_err(NmError::ZBus)?;
        Ok(HashMap::new())
    }

    #[zbus(name = "Delete")]
    async fn delete(&mut self) -> Result<(), NmError> {
        self.shared.lock().expect("test state").profiles.remove(&self.path);
        self.shared.lock().expect("test state").calls.push(format!("Delete {}", self.path));
        let connection = self.connection.clone();
        let target = self.path.clone();
        // A method can't remove its own object while it is running
        tokio::spawn(async move {
            let _ = connection.object_server().remove::<Profile, _>(target.as_str()).await;
        });
        Ok(())
    }

    #[zbus(signal, name = "Updated")]
    async fn updated(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
}

async fn add_profile(connection: &Connection, shared: &SharedState, settings: Settings) -> zbus::Result<OwnedObjectPath> {
    let profile_path = {
        let mut state = shared.lock().expect("test state");
        state.next_profile += 1;
        let profile_path = format!("{SETTINGS_PATH}/{}", state.next_profile);
        state.profiles.insert(profile_path.clone(), split_secrets(&settings));
        profile_path
    };
    let object = Profile { shared: Arc::clone(shared), connection: connection.clone(), path: profile_path.clone() };
    connection.object_server().at(profile_path.as_str(), object).await?;
    Ok(path(&profile_path))
}

struct AgentManager {
    shared: SharedState,
}

#[interface(name = "org.freedesktop.NetworkManager.AgentManager")]
impl AgentManager {
    #[zbus(name = "RegisterWithCapabilities")]
    fn register_with_capabilities(&self, identifier: String, capabilities: u32, #[zbus(header)] header: zbus::message::Header<'_>) {
        let mut shared = self.shared.lock().expect("test state");
        shared.calls.push(format!("RegisterAgent {identifier} capabilities={capabilities}"));
        shared.agent = header.sender().map(ToString::to_string);
    }
}

struct Device {
    name: String,
    kind: u32,
    state: u32,
    available: Vec<OwnedObjectPath>,
}

#[interface(name = "org.freedesktop.NetworkManager.Device")]
impl Device {
    #[zbus(property, name = "Interface")]
    fn interface_name(&self) -> String {
        self.name.clone()
    }
    #[zbus(property, name = "DeviceType")]
    fn device_type(&self) -> u32 {
        self.kind
    }
    #[zbus(property, name = "State")]
    fn state(&self) -> u32 {
        self.state
    }
    #[zbus(property, name = "StateReason")]
    fn state_reason(&self) -> (u32, u32) {
        (self.state, 0)
    }
    #[zbus(property, name = "Managed")]
    fn managed(&self) -> bool {
        true
    }
    #[zbus(property, name = "Driver")]
    fn driver(&self) -> String {
        "fake".to_string()
    }
    #[zbus(property, name = "Mtu")]
    fn mtu(&self) -> u32 {
        1500
    }
    #[zbus(property, name = "AvailableConnections")]
    fn available_connections(&self) -> Vec<OwnedObjectPath> {
        self.available.clone()
    }
    #[zbus(signal, name = "StateChanged")]
    async fn state_signal(emitter: &SignalEmitter<'_>, new_state: u32, old_state: u32, reason: u32) -> zbus::Result<()>;
}

struct Wireless {
    shared: SharedState,
    access_points: Vec<OwnedObjectPath>,
    active: OwnedObjectPath,
    last_scan: i64,
}

#[interface(name = "org.freedesktop.NetworkManager.Device.Wireless")]
impl Wireless {
    #[zbus(property, name = "AccessPoints")]
    fn access_points(&self) -> Vec<OwnedObjectPath> {
        self.access_points.clone()
    }
    #[zbus(property, name = "ActiveAccessPoint")]
    fn active_access_point(&self) -> OwnedObjectPath {
        self.active.clone()
    }
    #[zbus(property, name = "Bitrate")]
    fn bitrate(&self) -> u32 {
        866_000
    }
    #[zbus(property, name = "WirelessCapabilities")]
    fn wireless_capabilities(&self) -> u32 {
        0x10 | 0x20 | 0x40
    }
    #[zbus(property, name = "HwAddress")]
    fn hw_address(&self) -> String {
        "AA:BB:CC:00:11:22".to_string()
    }
    #[zbus(property, name = "LastScan")]
    fn last_scan(&self) -> i64 {
        self.last_scan
    }

    #[zbus(name = "RequestScan")]
    async fn request_scan(
        &mut self,
        _options: HashMap<String, OwnedVariant>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        {
            let mut shared = self.shared.lock().expect("test state");
            shared.calls.push("RequestScan".to_string());
            if shared.scan_refused {
                return Err(fdo::Error::Failed("Scanning not allowed immediately following previous scan".to_string()));
            }
        }
        self.last_scan += 1;
        let _ = self.last_scan_changed(&emitter).await;
        Ok(())
    }
}

struct AccessPoint {
    ssid: Vec<u8>,
    bssid: String,
    strength: u8,
    frequency: u32,
    flags: u32,
    rsn: u32,
}

#[interface(name = "org.freedesktop.NetworkManager.AccessPoint")]
impl AccessPoint {
    #[zbus(property, name = "Ssid")]
    fn ssid(&self) -> Vec<u8> {
        self.ssid.clone()
    }
    #[zbus(property, name = "HwAddress")]
    fn hw_address(&self) -> String {
        self.bssid.clone()
    }
    #[zbus(property, name = "Strength")]
    fn strength(&self) -> u8 {
        self.strength
    }
    #[zbus(property, name = "Frequency")]
    fn frequency(&self) -> u32 {
        self.frequency
    }
    #[zbus(property, name = "Flags")]
    fn flags(&self) -> u32 {
        self.flags
    }
    #[zbus(property, name = "WpaFlags")]
    fn wpa_flags(&self) -> u32 {
        0
    }
    #[zbus(property, name = "RsnFlags")]
    fn rsn_flags(&self) -> u32 {
        self.rsn
    }
    #[zbus(property, name = "MaxBitrate")]
    fn max_bitrate(&self) -> u32 {
        1_200_000
    }
}

/// The running stand-in, and its controls for tests.
pub struct FakeNm {
    connection: Connection,
    shared: SharedState,
}

/// WPA2 Personal, as an access point reports it.
pub const RSN_PSK: u32 = 0x100;
/// WPA3 Personal.
pub const RSN_SAE: u32 = 0x400;

impl FakeNm {
    pub async fn start(bus: &crate::bus::TestBus) -> anyhow::Result<Self> {
        Self::start_on(bus.connect().await?).await
    }

    pub async fn start_on(connection: Connection) -> anyhow::Result<Self> {
        let shared = SharedState::default();
        let server = connection.object_server();
        server.at("/org/freedesktop", fdo::ObjectManager).await?;
        server
            .at(
                MANAGER_PATH,
                Manager {
                    shared: Arc::clone(&shared),
                    connection: connection.clone(),
                    wifi_enabled: true,
                    wifi_hardware: true,
                    wwan_enabled: false,
                    connectivity: 4,
                    active: Vec::new(),
                    devices: vec![path(WIRED_DEVICE_PATH), path(WIFI_DEVICE_PATH)],
                },
            )
            .await?;
        server.at(SETTINGS_PATH, SettingsService { shared: Arc::clone(&shared) }).await?;
        server.at("/org/freedesktop/NetworkManager/AgentManager", AgentManager { shared: Arc::clone(&shared) }).await?;
        server.at(WIRED_DEVICE_PATH, Device { name: "eth0".to_string(), kind: 1, state: 30, available: Vec::new() }).await?;
        server.at(WIFI_DEVICE_PATH, Device { name: "wlan0".to_string(), kind: 2, state: 30, available: Vec::new() }).await?;
        server
            .at(WIFI_DEVICE_PATH, Wireless { shared: Arc::clone(&shared), access_points: Vec::new(), active: none(), last_scan: 100 })
            .await?;
        connection.request_name(BUS_NAME).await?;
        Ok(Self { connection, shared })
    }

    pub async fn add_access_point(&self, ssid: &[u8], bssid: &str, strength: u8, rsn: u32) -> anyhow::Result<()> {
        let number = {
            let mut shared = self.shared.lock().expect("test state");
            shared.next_ap += 1;
            shared.next_ap
        };
        let ap_path = format!("/org/freedesktop/NetworkManager/AccessPoint/{number}");
        let object = AccessPoint {
            ssid: ssid.to_vec(),
            bssid: bssid.to_string(),
            strength,
            frequency: 5180,
            flags: u32::from(rsn != 0),
            rsn,
        };
        let server = self.connection.object_server();
        server.at(ap_path.as_str(), object).await?;
        let wireless = server.interface::<_, Wireless>(WIFI_DEVICE_PATH).await?;
        wireless.get_mut().await.access_points.push(path(&ap_path));
        wireless.get().await.access_points_changed(wireless.signal_emitter()).await?;
        Ok(())
    }

    /// Adds a saved profile; returns its path.
    pub async fn add_wifi_profile(&self, uuid: &str, ssid: &[u8], key_mgmt: &str, password: &str, timestamp: u64) -> anyhow::Result<String> {
        let mut settings = Settings::new();
        let mut connection = Props::new();
        connection.insert("id".to_string(), value(uuid));
        connection.insert("uuid".to_string(), value(uuid));
        connection.insert("type".to_string(), value("802-11-wireless"));
        connection.insert("timestamp".to_string(), value(timestamp));
        settings.insert("connection".to_string(), connection);
        let mut wireless = Props::new();
        wireless.insert("ssid".to_string(), value(ssid.to_vec()));
        settings.insert("802-11-wireless".to_string(), wireless);
        if !key_mgmt.is_empty() {
            let mut security = Props::new();
            security.insert("key-mgmt".to_string(), value(key_mgmt));
            security.insert("psk".to_string(), value(password));
            settings.insert("802-11-wireless-security".to_string(), security);
        }
        self.add_profile(settings).await
    }

    pub async fn add_profile(&self, settings: Settings) -> anyhow::Result<String> {
        Ok(add_profile(&self.connection, &self.shared, settings).await?.to_string())
    }

    pub fn set_outcome(&self, outcome: Outcome) {
        self.shared.lock().expect("test state").outcome = Some(outcome);
    }

    pub fn set_secrets_unavailable(&self, unavailable: bool) {
        self.shared.lock().expect("test state").no_secrets = unavailable;
    }

    pub fn set_secrets_denied(&self, denied: bool) {
        self.shared.lock().expect("test state").deny_secrets = denied;
    }

    pub fn set_scan_refused(&self, refused: bool) {
        self.shared.lock().expect("test state").scan_refused = refused;
    }

    /// Adds a profile with a `802-11-wireless-security` section of these exact keys.
    pub async fn add_secret_profile(&self, uuid: &str, ssid: &[u8], security: Props) -> anyhow::Result<String> {
        let mut settings = Settings::new();
        let mut connection = Props::new();
        connection.insert("id".to_string(), value(uuid));
        connection.insert("uuid".to_string(), value(uuid));
        connection.insert("type".to_string(), value("802-11-wireless"));
        settings.insert("connection".to_string(), connection);
        let mut wireless = Props::new();
        wireless.insert("ssid".to_string(), value(ssid.to_vec()));
        settings.insert("802-11-wireless".to_string(), wireless);
        settings.insert("802-11-wireless-security".to_string(), security);
        self.add_profile(settings).await
    }

    pub async fn set_connectivity(&self, connectivity: u32) -> anyhow::Result<()> {
        let manager = self.connection.object_server().interface::<_, Manager>(MANAGER_PATH).await?;
        manager.get_mut().await.connectivity = connectivity;
        manager.get().await.connectivity_changed(manager.signal_emitter()).await?;
        Ok(())
    }

    pub fn agent_registered(&self) -> bool {
        self.shared.lock().expect("test state").agent.is_some()
    }

    /// Asks the registered agent for secrets, as the service does when connecting.
    pub async fn ask_agent(&self, connection: &Settings, setting: &str, hints: Vec<String>, flags: u32) -> zbus::Result<Settings> {
        let agent = self.shared.lock().expect("test state").agent.clone().expect("an agent registered first");
        let path = ObjectPath::try_from("/org/freedesktop/NetworkManager/Settings/1").expect("a valid path");
        let reply = self
            .connection
            .call_method(Some(agent.as_str()), "/org/freedesktop/NetworkManager/SecretAgent", Some("org.freedesktop.NetworkManager.SecretAgent"), "GetSecrets", &(connection, &path, setting, hints, flags))
            .await?;
        reply.body().deserialize()
    }

    pub async fn cancel_agent_request(&self, setting: &str) -> zbus::Result<()> {
        let agent = self.shared.lock().expect("test state").agent.clone().expect("an agent registered first");
        let path = ObjectPath::try_from("/org/freedesktop/NetworkManager/Settings/1").expect("a valid path");
        self.connection
            .call_method(Some(agent.as_str()), "/org/freedesktop/NetworkManager/SecretAgent", Some("org.freedesktop.NetworkManager.SecretAgent"), "CancelGetSecrets", &(&path, setting))
            .await?;
        Ok(())
    }

    /// Hands secrets to the registered agent to keep, as the service does for "only for me".
    pub async fn agent_save(&self, connection: &Settings) -> zbus::Result<()> {
        let agent = self.shared.lock().expect("test state").agent.clone().expect("an agent registered first");
        let path = ObjectPath::try_from("/org/freedesktop/NetworkManager/Settings/1").expect("a valid path");
        self.connection
            .call_method(Some(agent.as_str()), "/org/freedesktop/NetworkManager/SecretAgent", Some("org.freedesktop.NetworkManager.SecretAgent"), "SaveSecrets", &(connection, &path))
            .await?;
        Ok(())
    }

    pub async fn agent_delete(&self, connection: &Settings) -> zbus::Result<()> {
        let agent = self.shared.lock().expect("test state").agent.clone().expect("an agent registered first");
        let path = ObjectPath::try_from("/org/freedesktop/NetworkManager/Settings/1").expect("a valid path");
        self.connection
            .call_method(Some(agent.as_str()), "/org/freedesktop/NetworkManager/SecretAgent", Some("org.freedesktop.NetworkManager.SecretAgent"), "DeleteSecrets", &(connection, &path))
            .await?;
        Ok(())
    }

    pub fn calls(&self) -> Vec<String> {
        self.shared.lock().expect("test state").calls.clone()
    }

    pub fn profile_count(&self) -> usize {
        self.shared.lock().expect("test state").profiles.len()
    }

    /// A stored setting of a profile, as the service holds it.
    pub fn setting(&self, uuid: &str, section: &str, key: &str) -> Option<OwnedVariant> {
        let shared = self.shared.lock().expect("test state");
        let (plain, _) = shared.profiles.values().find(|(plain, _)| {
            plain.get("connection").and_then(|entry| entry.get("uuid")).and_then(|entry| entry.downcast_ref::<&str>().ok().map(|text| text == uuid)).unwrap_or(false)
        })?;
        plain.get(section)?.get(key).cloned()
    }

    /// A profile's secrets as the service holds them, by section and key.
    pub fn secret(&self, uuid: &str, section: &str, key: &str) -> Option<String> {
        let shared = self.shared.lock().expect("test state");
        let (_, secrets) = shared.profiles.values().find(|(plain, _)| {
            plain.get("connection").and_then(|entry| entry.get("uuid")).and_then(|entry| entry.downcast_ref::<&str>().ok().map(|text| text == uuid)).unwrap_or(false)
        })?;
        secrets.get(section)?.get(key)?.downcast_ref::<&str>().ok().map(str::to_string)
    }

    /// Takes the service off the bus, as when it stops or crashes. Clients see the name lose its owner,
    /// which is all they can see of a service going away.
    pub async fn stop(self) -> anyhow::Result<()> {
        self.connection.release_name(BUS_NAME).await?;
        Ok(())
    }
}
