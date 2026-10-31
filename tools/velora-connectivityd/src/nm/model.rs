//! What the shell shows about the network, worked out from NetworkManager's objects and profiles.
//! The rules follow plasma-nm: a saved profile takes over the access points it can use and stays
//! listed when they go, and profiles sort by available, active, type, last use, then name.

use crate::values::{self, Objects, Props, Settings};
use serde::Serialize;
use std::cmp::Ordering;
use std::collections::{BTreeMap, HashMap};
use std::net::Ipv6Addr;

pub const IFACE_MANAGER: &str = "org.freedesktop.NetworkManager";
pub const IFACE_DEVICE: &str = "org.freedesktop.NetworkManager.Device";
pub const IFACE_WIRELESS: &str = "org.freedesktop.NetworkManager.Device.Wireless";
pub const IFACE_WIRED: &str = "org.freedesktop.NetworkManager.Device.Wired";
pub const IFACE_AP: &str = "org.freedesktop.NetworkManager.AccessPoint";
pub const IFACE_ACTIVE: &str = "org.freedesktop.NetworkManager.Connection.Active";
pub const IFACE_VPN: &str = "org.freedesktop.NetworkManager.VPN.Connection";
pub const IFACE_IP4: &str = "org.freedesktop.NetworkManager.IP4Config";
pub const IFACE_IP6: &str = "org.freedesktop.NetworkManager.IP6Config";
pub const IFACE_SETTINGS_CONNECTION: &str = "org.freedesktop.NetworkManager.Settings.Connection";

pub const DEVICE_TYPE_ETHERNET: i64 = 1;
pub const DEVICE_TYPE_WIFI: i64 = 2;
pub const DEVICE_TYPE_WIFI_P2P: i64 = 30;
pub const DEVICE_TYPE_LOOPBACK: i64 = 32;

pub const ACTIVE_ACTIVATING: i64 = 1;
pub const ACTIVE_ACTIVATED: i64 = 2;

const AP_FLAG_PRIVACY: i64 = 0x1;
const SEC_KEY_PSK: i64 = 0x100;
const SEC_KEY_8021X: i64 = 0x200;
const SEC_KEY_SAE: i64 = 0x400;
const SEC_KEY_OWE: i64 = 0x800;
const SEC_KEY_OWE_TM: i64 = 0x1000;
const SEC_KEY_SUITE_B: i64 = 0x2000;

const CAPABILITY_WPA: i64 = 0x10;
const CAPABILITY_RSN: i64 = 0x20;
const CAPABILITY_AP: i64 = 0x40;

/// The ways a Wi-Fi network can ask to be joined, in the shell's terms.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Security {
    None,
    Wep,
    DynamicWep,
    Leap,
    WpaPsk,
    Sae,
    Owe,
    WpaEap,
    WpaEapSuiteB192,
    Unknown,
}

impl Security {
    /// True when joining takes one typed password.
    pub fn is_personal(self) -> bool {
        matches!(self, Security::Wep | Security::WpaPsk | Security::Sae)
    }

    /// True when joining needs the full enterprise form.
    pub fn is_enterprise(self) -> bool {
        matches!(self, Security::DynamicWep | Security::Leap | Security::WpaEap | Security::WpaEapSuiteB192)
    }

    pub fn key_mgmt(self) -> &'static str {
        match self {
            Security::None | Security::Unknown => "",
            Security::Wep => "none",
            Security::DynamicWep | Security::Leap => "ieee8021x",
            Security::WpaPsk => "wpa-psk",
            Security::Sae => "sae",
            Security::Owe => "owe",
            Security::WpaEap => "wpa-eap",
            Security::WpaEapSuiteB192 => "wpa-eap-suite-b-192",
        }
    }
}

/// The strongest way to join an access point that this Wi-Fi device can also do. A transition network
/// offering both WPA2 and WPA3 is joined as WPA3, as plasma-nm does.
pub fn best_security(ap_flags: i64, wpa_flags: i64, rsn_flags: i64, device_capabilities: i64) -> Security {
    let any = wpa_flags | rsn_flags;
    let rsn_ok = device_capabilities & CAPABILITY_RSN != 0;
    let wpa_ok = device_capabilities & CAPABILITY_WPA != 0;
    if any & SEC_KEY_SAE != 0 {
        return Security::Sae;
    }
    if any & SEC_KEY_SUITE_B != 0 {
        return Security::WpaEapSuiteB192;
    }
    if rsn_flags & SEC_KEY_8021X != 0 && rsn_ok {
        return Security::WpaEap;
    }
    if rsn_flags & SEC_KEY_PSK != 0 && rsn_ok {
        return Security::WpaPsk;
    }
    if wpa_flags & SEC_KEY_8021X != 0 && wpa_ok {
        return Security::WpaEap;
    }
    if wpa_flags & SEC_KEY_PSK != 0 && wpa_ok {
        return Security::WpaPsk;
    }
    if any & (SEC_KEY_OWE | SEC_KEY_OWE_TM) != 0 {
        return Security::Owe;
    }
    if any == 0 && ap_flags & AP_FLAG_PRIVACY != 0 {
        return Security::Wep;
    }
    if any == 0 {
        return Security::None;
    }
    Security::Unknown
}

/// The protocols an access point advertises, in the words `nmcli` uses: "WPA2 WPA3", "WEP", or nothing.
pub fn security_words(ap_flags: i64, wpa_flags: i64, rsn_flags: i64) -> String {
    let mut words = Vec::new();
    if wpa_flags == 0 && rsn_flags == 0 && ap_flags & AP_FLAG_PRIVACY != 0 {
        words.push("WEP");
    }
    if wpa_flags != 0 {
        words.push("WPA1");
    }
    if rsn_flags & (SEC_KEY_PSK | SEC_KEY_8021X) != 0 {
        words.push("WPA2");
    }
    if rsn_flags & (SEC_KEY_SAE | SEC_KEY_SUITE_B) != 0 {
        words.push("WPA3");
    }
    if rsn_flags & SEC_KEY_OWE_TM != 0 {
        words.push("OWE-TM");
    } else if rsn_flags & SEC_KEY_OWE != 0 {
        words.push("OWE");
    }
    if (wpa_flags | rsn_flags) & SEC_KEY_8021X != 0 {
        words.push("802.1X");
    }
    words.join(" ")
}

/// What a saved Wi-Fi profile's security section asks for.
pub fn profile_security(settings: &Settings) -> Security {
    let Some(section) = settings.get("802-11-wireless-security") else { return Security::None };
    match values::text_or_empty(section, "key-mgmt").as_str() {
        "none" => Security::Wep,
        "ieee8021x" => {
            if values::text_or_empty(section, "auth-alg") == "leap" {
                Security::Leap
            } else {
                Security::DynamicWep
            }
        }
        "wpa-psk" => Security::WpaPsk,
        "sae" => Security::Sae,
        "owe" => Security::Owe,
        "wpa-eap" => Security::WpaEap,
        "wpa-eap-suite-b-192" => Security::WpaEapSuiteB192,
        _ => Security::Unknown,
    }
}

pub fn channel(frequency: i64) -> i64 {
    match frequency {
        2484 => 14,
        2412..=2472 => (frequency - 2407) / 5,
        5000..=5895 => (frequency - 5000) / 5,
        5955..=7115 => (frequency - 5950) / 5,
        _ => 0,
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IpDetails {
    pub addresses: Vec<String>,
    pub gateway: String,
    pub dns: Vec<String>,
    pub domains: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceInfo {
    pub path: String,
    pub interface: String,
    pub device_type: i64,
    pub state: i64,
    pub state_reason: i64,
    pub hw_address: String,
    pub driver: String,
    pub mtu: i64,
    pub active_connection: String,
    pub ip4: IpDetails,
    pub ip6: IpDetails,
    /// Mbit/s; the Wi-Fi link rate or the cable's speed.
    pub speed: i64,
    pub carrier: bool,
    pub supports_ap: bool,
    pub last_scan: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WifiNetwork {
    pub ssid: String,
    /// The name as bytes in hex, which is what identifies it when it isn't valid text.
    pub ssid_hex: String,
    pub bssid: String,
    pub strength: i64,
    pub frequency: i64,
    pub channel: i64,
    pub max_bitrate: i64,
    pub active: bool,
    pub security: String,
    pub security_type: Security,
    pub saved_uuid: String,
    pub saved_credentials: bool,
    pub never_used: bool,
    pub device: String,
    pub access_point: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileInfo {
    pub uuid: String,
    pub path: String,
    pub id: String,
    pub connection_type: String,
    pub autoconnect: bool,
    pub timestamp: i64,
    pub ssid: String,
    pub security_type: Security,
    /// The VPN's kind: `openvpn`, `vpnc`, `wireguard`.
    pub vpn_type: String,
    pub available: bool,
    pub in_range: bool,
    pub active_state: i64,
    pub device: String,
    pub signal: i64,
    pub read_only: bool,
    pub hidden: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActiveInfo {
    pub path: String,
    pub uuid: String,
    pub id: String,
    pub connection_type: String,
    pub state: i64,
    pub vpn: bool,
    pub vpn_state: i64,
    pub devices: Vec<String>,
    /// Sharing this computer's connection rather than using one.
    pub hotspot: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NetworkSnapshot {
    pub available: bool,
    pub networking_enabled: bool,
    pub wifi_enabled: bool,
    pub wifi_hardware_enabled: bool,
    pub wwan_enabled: bool,
    pub wwan_hardware_enabled: bool,
    pub connectivity: &'static str,
    pub wifi_status: &'static str,
    pub wifi_connected: bool,
    pub ethernet_connected: bool,
    pub wifi_details: Option<DeviceInfo>,
    pub ethernet_details: Option<DeviceInfo>,
    pub devices: Vec<DeviceInfo>,
    pub networks: Vec<WifiNetwork>,
    pub profiles: Vec<ProfileInfo>,
    pub active_connections: Vec<ActiveInfo>,
    pub vpn_plugins: Vec<String>,
    pub hotspot_active: bool,
}

impl NetworkSnapshot {
    pub fn unavailable() -> Self {
        Self {
            available: false,
            networking_enabled: false,
            wifi_enabled: false,
            wifi_hardware_enabled: false,
            wwan_enabled: false,
            wwan_hardware_enabled: false,
            connectivity: "unknown",
            wifi_status: "disconnected",
            wifi_connected: false,
            ethernet_connected: false,
            wifi_details: None,
            ethernet_details: None,
            devices: Vec::new(),
            networks: Vec::new(),
            profiles: Vec::new(),
            active_connections: Vec::new(),
            vpn_plugins: Vec::new(),
            hotspot_active: false,
        }
    }
}

pub fn connectivity_word(value: i64) -> &'static str {
    match value {
        1 => "none",
        2 => "portal",
        3 => "limited",
        4 => "full",
        _ => "unknown",
    }
}

fn wifi_status_word(state: i64, connectivity: &str) -> &'static str {
    match state {
        100 => {
            if connectivity == "limited" {
                "limited"
            } else {
                "connected"
            }
        }
        40..=90 => "connecting",
        10 | 20 => "disabled",
        _ => "disconnected",
    }
}

fn interface<'a>(objects: &'a Objects, path: &str, name: &str) -> Option<&'a Props> {
    objects.get(path)?.get(name)
}

fn ip4(objects: &Objects, config: Option<String>) -> IpDetails {
    let Some(props) = config.and_then(|path| interface(objects, &path, IFACE_IP4)) else { return IpDetails::default() };
    IpDetails {
        addresses: address_data(props),
        gateway: values::text_or_empty(props, "Gateway"),
        dns: values::dicts(props, "NameserverData").iter().filter_map(|entry| values::text(entry, "address")).collect(),
        domains: values::strings(props, "Domains"),
    }
}

fn ip6(objects: &Objects, config: Option<String>) -> IpDetails {
    let Some(props) = config.and_then(|path| interface(objects, &path, IFACE_IP6)) else { return IpDetails::default() };
    let dns = match props.get("Nameservers").map(|value| crate::values::to_json(value)) {
        Some(serde_json::Value::Array(entries)) => entries.iter().filter_map(ipv6_from_json).collect(),
        _ => Vec::new(),
    };
    IpDetails {
        addresses: address_data(props),
        gateway: values::text_or_empty(props, "Gateway"),
        dns,
        domains: values::strings(props, "Domains"),
    }
}

fn ipv6_from_json(value: &serde_json::Value) -> Option<String> {
    let bytes: Vec<u8> = value.as_array()?.iter().map(|byte| byte.as_u64().and_then(|byte| u8::try_from(byte).ok())).collect::<Option<_>>()?;
    let octets: [u8; 16] = bytes.try_into().ok()?;
    Some(Ipv6Addr::from(octets).to_string())
}

fn address_data(props: &Props) -> Vec<String> {
    values::dicts(props, "AddressData")
        .iter()
        .filter_map(|entry| {
            let address = values::text(entry, "address")?;
            Some(match values::number(entry, "prefix") {
                Some(prefix) => format!("{address}/{prefix}"),
                None => address,
            })
        })
        .collect()
}

fn device_info(objects: &Objects, path: &str, props: &Props) -> DeviceInfo {
    let wireless = interface(objects, path, IFACE_WIRELESS);
    let wired = interface(objects, path, IFACE_WIRED);
    let hw_address = wireless
        .or(wired)
        .map(|extra| values::text_or_empty(extra, "HwAddress"))
        .filter(|address| !address.is_empty())
        .unwrap_or_else(|| values::text_or_empty(props, "HwAddress"));
    let speed = match (wireless, wired) {
        (Some(wifi), _) => values::number(wifi, "Bitrate").unwrap_or(0) / 1000,
        (_, Some(cable)) => values::number(cable, "Speed").unwrap_or(0),
        _ => 0,
    };
    let state_reason = match props.get("StateReason").map(|value| values::to_json(value)) {
        Some(serde_json::Value::Array(pair)) => pair.get(1).and_then(serde_json::Value::as_i64).unwrap_or(0),
        _ => 0,
    };
    DeviceInfo {
        path: path.to_string(),
        interface: values::text_or_empty(props, "Interface"),
        device_type: values::number(props, "DeviceType").unwrap_or(0),
        state: values::number(props, "State").unwrap_or(0),
        state_reason,
        hw_address,
        driver: values::text_or_empty(props, "Driver"),
        mtu: values::number(props, "Mtu").unwrap_or(0),
        active_connection: values::path(props, "ActiveConnection").unwrap_or_default(),
        ip4: ip4(objects, values::path(props, "Ip4Config")),
        ip6: ip6(objects, values::path(props, "Ip6Config")),
        speed,
        carrier: wired.and_then(|cable| values::flag(cable, "Carrier")).unwrap_or(false),
        supports_ap: wireless.and_then(|wifi| values::number(wifi, "WirelessCapabilities")).unwrap_or(0) & CAPABILITY_AP != 0,
        last_scan: wireless.and_then(|wifi| values::number(wifi, "LastScan")).unwrap_or(0),
    }
}

fn connection_section(settings: &Settings) -> Option<&Props> {
    settings.get("connection")
}

fn profile_ssid(settings: &Settings) -> Option<Vec<u8>> {
    values::bytes(settings.get("802-11-wireless")?, "ssid")
}

fn profile_timestamp(settings: &Settings) -> i64 {
    connection_section(settings).and_then(|section| values::number(section, "timestamp")).unwrap_or(0)
}

/// Bond and bridge members and the like are parts of another profile, not things to list.
fn is_port(settings: &Settings) -> bool {
    connection_section(settings).is_some_and(|section| {
        ["master", "controller"].iter().any(|key| !values::text_or_empty(section, key).is_empty())
    })
}

fn vpn_type(settings: &Settings, connection_type: &str) -> String {
    match connection_type {
        "wireguard" => "wireguard".to_string(),
        "vpn" => settings
            .get("vpn")
            .map(|section| values::text_or_empty(section, "service-type"))
            .and_then(|service| service.rsplit('.').next().map(str::to_string))
            .unwrap_or_default(),
        _ => String::new(),
    }
}

/// Picks the profile a visible network belongs to: the one in use, else the most recently joined,
/// and one that never connected only when nothing else matches.
fn pick_profile<'a>(
    candidates: &[&'a (String, &'a Settings)],
    active_uuids: &HashMap<String, i64>,
) -> Option<&'a (String, &'a Settings)> {
    candidates
        .iter()
        .copied()
        .max_by_key(|(_, settings)| {
            let uuid = connection_section(settings).map(|section| values::text_or_empty(section, "uuid")).unwrap_or_default();
            (active_uuids.contains_key(&uuid), profile_timestamp(settings))
        })
}

fn sort_rank(connection_type: &str) -> u8 {
    match connection_type {
        "802-3-ethernet" => 0,
        "802-11-wireless" => 1,
        "gsm" => 2,
        "cdma" => 3,
        "pppoe" => 4,
        "adsl" => 5,
        "infiniband" => 6,
        "bluetooth" => 7,
        "wireguard" => 8,
        "vpn" => 9,
        "vlan" => 10,
        "bridge" => 11,
        "bond" => 12,
        "team" => 13,
        _ => 14,
    }
}

fn compare_profiles(a: &ProfileInfo, b: &ProfileInfo) -> Ordering {
    let is_up = |profile: &ProfileInfo| profile.active_state == ACTIVE_ACTIVATING || profile.active_state == ACTIVE_ACTIVATED;
    b.available
        .cmp(&a.available)
        .then_with(|| is_up(b).cmp(&is_up(a)))
        .then_with(|| sort_rank(&a.connection_type).cmp(&sort_rank(&b.connection_type)))
        .then_with(|| a.vpn_type.cmp(&b.vpn_type))
        .then_with(|| b.timestamp.cmp(&a.timestamp))
        .then_with(|| a.id.to_lowercase().cmp(&b.id.to_lowercase()))
        .then_with(|| a.uuid.cmp(&b.uuid))
}

/// The whole picture from what the service reports. `profiles` holds each profile's settings by path.
pub fn snapshot(objects: &Objects, profiles: &BTreeMap<String, Settings>, vpn_plugins: &[String]) -> NetworkSnapshot {
    let manager = objects.get("/org/freedesktop/NetworkManager").and_then(|interfaces| interfaces.get(IFACE_MANAGER));
    let Some(manager) = manager else { return NetworkSnapshot::unavailable() };
    let connectivity = connectivity_word(values::number(manager, "Connectivity").unwrap_or(0));

    let active_connections: Vec<ActiveInfo> = objects
        .iter()
        .filter_map(|(path, interfaces)| {
            let props = interfaces.get(IFACE_ACTIVE)?;
            let vpn = values::flag(props, "Vpn").unwrap_or(false);
            Some(ActiveInfo {
                path: path.clone(),
                uuid: values::text_or_empty(props, "Uuid"),
                id: values::text_or_empty(props, "Id"),
                connection_type: values::text_or_empty(props, "Type"),
                state: values::number(props, "State").unwrap_or(0),
                vpn,
                vpn_state: interfaces.get(IFACE_VPN).and_then(|extra| values::number(extra, "VpnState")).unwrap_or(0),
                devices: values::strings(props, "Devices"),
                hotspot: values::path(props, "Connection").and_then(|profile| profiles.get(&profile)).and_then(|settings| settings.get("802-11-wireless"))
                    .is_some_and(|wireless| values::text_or_empty(wireless, "mode") == "ap"),
            })
        })
        .collect();
    let active_states: HashMap<String, i64> = active_connections.iter().map(|active| (active.uuid.clone(), active.state)).collect();

    let mut devices: Vec<DeviceInfo> = objects
        .iter()
        .filter_map(|(path, interfaces)| Some((path, interfaces.get(IFACE_DEVICE)?)))
        .filter(|(_, props)| {
            values::flag(props, "Managed").unwrap_or(true)
                && !matches!(values::number(props, "DeviceType").unwrap_or(0), DEVICE_TYPE_LOOPBACK | DEVICE_TYPE_WIFI_P2P)
        })
        .map(|(path, props)| device_info(objects, path, props))
        .collect();
    devices.sort_by(|a, b| a.interface.cmp(&b.interface));

    // A Wi-Fi device's access points, grouped per name on that device
    let saved: Vec<(String, &Settings)> = profiles
        .iter()
        .filter(|(_, settings)| {
            connection_section(settings).is_some_and(|section| values::text_or_empty(section, "type") == "802-11-wireless")
        })
        .map(|(path, settings)| (path.clone(), settings))
        .collect();
    let mut networks: Vec<WifiNetwork> = Vec::new();
    let mut signal_by_profile: HashMap<String, (i64, String)> = HashMap::new();
    for device in devices.iter().filter(|device| device.device_type == DEVICE_TYPE_WIFI) {
        let Some(wireless) = interface(objects, &device.path, IFACE_WIRELESS) else { continue };
        let capabilities = values::number(wireless, "WirelessCapabilities").unwrap_or(0);
        let active_ap = values::path(wireless, "ActiveAccessPoint");
        let mut by_ssid: BTreeMap<Vec<u8>, Vec<(String, &Props)>> = BTreeMap::new();
        for ap_path in values::strings(wireless, "AccessPoints") {
            let Some(ap) = interface(objects, &ap_path, IFACE_AP) else { continue };
            let Some(ssid) = values::bytes(ap, "Ssid").filter(|ssid| !ssid.is_empty()) else { continue };
            by_ssid.entry(ssid).or_default().push((ap_path, ap));
        }
        for (ssid, access_points) in by_ssid {
            let candidates: Vec<&(String, &Settings)> =
                saved.iter().filter(|(_, settings)| profile_ssid(settings).as_deref() == Some(ssid.as_slice())).collect();
            let chosen = pick_profile(&candidates, &active_states);
            // A profile tied to one access point reads its signal from that one
            let pinned = chosen
                .and_then(|(_, settings)| settings.get("802-11-wireless"))
                .and_then(|section| values::bytes(section, "bssid"))
                .map(|bytes| values::mac_from_bytes(&bytes));
            let best = access_points
                .iter()
                .find(|(path, _)| active_ap.as_deref() == Some(path))
                .or_else(|| {
                    pinned.as_deref().and_then(|bssid| {
                        access_points.iter().find(|(_, ap)| values::text_or_empty(ap, "HwAddress").eq_ignore_ascii_case(bssid))
                    })
                })
                .or_else(|| access_points.iter().max_by_key(|(_, ap)| values::number(ap, "Strength").unwrap_or(0)));
            let Some((ap_path, ap)) = best else { continue };
            let (flags, wpa, rsn) = (
                values::number(ap, "Flags").unwrap_or(0),
                values::number(ap, "WpaFlags").unwrap_or(0),
                values::number(ap, "RsnFlags").unwrap_or(0),
            );
            let frequency = values::number(ap, "Frequency").unwrap_or(0);
            let strength = values::number(ap, "Strength").unwrap_or(0);
            let security = security_words(flags, wpa, rsn);
            let chosen_uuid = chosen
                .and_then(|(_, settings)| connection_section(settings))
                .map(|section| values::text_or_empty(section, "uuid"))
                .unwrap_or_default();
            for (path, _) in &candidates {
                let current = signal_by_profile.entry(path.clone()).or_insert((0, device.path.clone()));
                if strength >= current.0 {
                    *current = (strength, device.path.clone());
                }
            }
            networks.push(WifiNetwork {
                ssid: String::from_utf8_lossy(&ssid).into_owned(),
                ssid_hex: hex(&ssid),
                bssid: values::text_or_empty(ap, "HwAddress"),
                strength,
                frequency,
                channel: channel(frequency),
                max_bitrate: values::number(ap, "MaxBitrate").unwrap_or(0) / 1000,
                active: active_ap.as_deref() == Some(ap_path),
                saved_credentials: security.is_empty() || chosen.is_some_and(|(_, settings)| settings.contains_key("802-11-wireless-security")),
                security,
                security_type: best_security(flags, wpa, rsn, capabilities),
                never_used: chosen.is_some_and(|(_, settings)| profile_timestamp(settings) == 0),
                saved_uuid: chosen_uuid,
                device: device.path.clone(),
                access_point: ap_path.clone(),
            });
        }
    }
    networks.sort_by(|a, b| {
        b.active.cmp(&a.active).then_with(|| b.strength.cmp(&a.strength)).then_with(|| a.ssid.cmp(&b.ssid))
    });

    let mut available_paths: HashMap<String, String> = HashMap::new();
    for (path, interfaces) in objects {
        let Some(props) = interfaces.get(IFACE_DEVICE) else { continue };
        for connection in values::strings(props, "AvailableConnections") {
            available_paths.entry(connection).or_insert_with(|| path.clone());
        }
    }

    let mut profile_rows: Vec<ProfileInfo> = profiles
        .iter()
        .filter_map(|(path, settings)| {
            let section = connection_section(settings)?;
            let connection_type = values::text_or_empty(section, "type");
            let uuid = values::text(section, "uuid")?;
            let id = values::text(section, "id")?;
            if id.is_empty() || uuid.is_empty() || connection_type == "loopback" || is_port(settings) {
                return None;
            }
            let (signal, signal_device) = signal_by_profile.get(path).cloned().unwrap_or_default();
            let in_range = !signal_device.is_empty();
            let device = available_paths.get(path).cloned().or_else(|| in_range.then_some(signal_device)).unwrap_or_default();
            let is_vpn = connection_type == "vpn" || connection_type == "wireguard";
            Some(ProfileInfo {
                uuid: uuid.clone(),
                path: path.clone(),
                id,
                autoconnect: values::flag(section, "autoconnect").unwrap_or(true),
                timestamp: values::number(section, "timestamp").unwrap_or(0),
                ssid: profile_ssid(settings).map(|ssid| String::from_utf8_lossy(&ssid).into_owned()).unwrap_or_default(),
                security_type: if connection_type == "802-11-wireless" { profile_security(settings) } else { Security::None },
                vpn_type: vpn_type(settings, &connection_type),
                available: is_vpn || !device.is_empty(),
                in_range,
                active_state: active_states.get(&uuid).copied().unwrap_or(0),
                device,
                signal,
                read_only: objects
                    .get(path)
                    .and_then(|interfaces| interfaces.get(IFACE_SETTINGS_CONNECTION))
                    .and_then(|props| values::number(props, "Flags"))
                    .unwrap_or(0)
                    & 0x8
                    != 0,
                hidden: settings.get("802-11-wireless").and_then(|wireless| values::flag(wireless, "hidden")).unwrap_or(false),
                connection_type,
            })
        })
        .collect();
    profile_rows.sort_by(compare_profiles);

    let wifi_device = devices
        .iter()
        .filter(|device| device.device_type == DEVICE_TYPE_WIFI)
        .max_by_key(|device| device.state);
    let wifi_connected = wifi_device.is_some_and(|device| device.state == 100);
    let ethernet = devices.iter().filter(|device| device.device_type == DEVICE_TYPE_ETHERNET).max_by_key(|device| device.state);
    NetworkSnapshot {
        available: true,
        networking_enabled: values::flag(manager, "NetworkingEnabled").unwrap_or(false),
        wifi_enabled: values::flag(manager, "WirelessEnabled").unwrap_or(false),
        wifi_hardware_enabled: values::flag(manager, "WirelessHardwareEnabled").unwrap_or(false),
        wwan_enabled: values::flag(manager, "WwanEnabled").unwrap_or(false),
        wwan_hardware_enabled: values::flag(manager, "WwanHardwareEnabled").unwrap_or(false),
        connectivity,
        wifi_status: wifi_device.map_or("disconnected", |device| wifi_status_word(device.state, connectivity)),
        wifi_connected,
        ethernet_connected: ethernet.is_some_and(|device| device.state == 100),
        wifi_details: wifi_device.filter(|device| device.state == 100).cloned(),
        ethernet_details: ethernet.filter(|device| device.state == 100).cloned(),
        devices,
        networks,
        profiles: profile_rows,
        hotspot_active: active_connections.iter().any(|active| active.hotspot),
        active_connections,
        vpn_plugins: vpn_plugins.to_vec(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::values::build::{owned, props};
    use std::collections::HashMap;
    use zbus::{ObjectPath, Variant};

    const PSK: i64 = SEC_KEY_PSK;

    fn object(path: &str) -> ObjectPath<'static> {
        ObjectPath::try_from(path.to_string()).unwrap()
    }

    fn base() -> Objects {
        let mut objects = Objects::new();
        objects.entry("/org/freedesktop/NetworkManager".to_string()).or_default().insert(
            IFACE_MANAGER.to_string(),
            props([
                ("NetworkingEnabled", owned(true)),
                ("WirelessEnabled", owned(true)),
                ("WirelessHardwareEnabled", owned(true)),
                ("WwanEnabled", owned(false)),
                ("WwanHardwareEnabled", owned(false)),
                ("Connectivity", owned(4u32)),
            ]),
        );
        objects
    }

    fn add_wifi_device(objects: &mut Objects, access_points: &[&str], active: &str, state: u32) {
        let path = "/dev/wlan0".to_string();
        objects.entry(path.clone()).or_default().insert(
            IFACE_DEVICE.to_string(),
            props([
                ("Interface", owned("wlan0")),
                ("DeviceType", owned(2u32)),
                ("State", owned(state)),
                ("Managed", owned(true)),
                ("Mtu", owned(1500u32)),
            ]),
        );
        let list: Vec<ObjectPath> = access_points.iter().map(|path| object(path)).collect();
        objects.entry(path).or_default().insert(
            IFACE_WIRELESS.to_string(),
            props([
                ("AccessPoints", owned(list)),
                ("ActiveAccessPoint", owned(object(active))),
                ("WirelessCapabilities", owned((CAPABILITY_RSN | CAPABILITY_WPA | CAPABILITY_AP) as u32)),
                ("Bitrate", owned(866_000u32)),
                ("HwAddress", owned("AA:BB:CC:00:11:22")),
                ("LastScan", owned(1234i64)),
            ]),
        );
    }

    fn add_ap(objects: &mut Objects, path: &str, ssid: &[u8], bssid: &str, strength: u8, rsn: i64) {
        objects.entry(path.to_string()).or_default().insert(
            IFACE_AP.to_string(),
            props([
                ("Ssid", owned(ssid.to_vec())),
                ("HwAddress", owned(bssid)),
                ("Strength", owned(strength)),
                ("Frequency", owned(5180u32)),
                ("Flags", owned(1u32)),
                ("WpaFlags", owned(0u32)),
                ("RsnFlags", owned(rsn as u32)),
                ("MaxBitrate", owned(1_200_000u32)),
            ]),
        );
    }

    fn wifi_profile(uuid: &str, ssid: &[u8], timestamp: u64, key_mgmt: Option<&str>) -> Settings {
        let mut settings = Settings::new();
        settings.insert(
            "connection".to_string(),
            props([
                ("id", owned(uuid)),
                ("uuid", owned(uuid)),
                ("type", owned("802-11-wireless")),
                ("timestamp", owned(timestamp)),
            ]),
        );
        settings.insert("802-11-wireless".to_string(), props([("ssid", owned(ssid.to_vec()))]));
        if let Some(key_mgmt) = key_mgmt {
            settings.insert("802-11-wireless-security".to_string(), props([("key-mgmt", owned(key_mgmt))]));
        }
        settings
    }

    fn profile(uuid: &str, connection_type: &str, extra: &[(&str, &str)]) -> Settings {
        let mut settings = Settings::new();
        let mut section = props([("id", owned(uuid)), ("uuid", owned(uuid)), ("type", owned(connection_type))]);
        for (key, value) in extra {
            section.insert((*key).to_string(), owned(*value));
        }
        settings.insert("connection".to_string(), section);
        settings
    }

    #[test]
    fn no_manager_object_means_unavailable() {
        let result = snapshot(&Objects::new(), &BTreeMap::new(), &[]);
        assert!(!result.available);
        assert_eq!(result, NetworkSnapshot::unavailable());
    }

    #[test]
    fn several_access_points_of_a_name_become_one_network_with_the_best_signal() {
        let mut objects = base();
        add_wifi_device(&mut objects, &["/ap/1", "/ap/2", "/ap/3"], "/", 30);
        add_ap(&mut objects, "/ap/1", b"Home", "00:00:00:00:00:01", 40, PSK);
        add_ap(&mut objects, "/ap/2", b"Home", "00:00:00:00:00:02", 80, PSK);
        add_ap(&mut objects, "/ap/3", b"Cafe", "00:00:00:00:00:03", 60, 0);
        let result = snapshot(&objects, &BTreeMap::new(), &[]);
        assert_eq!(result.networks.len(), 2);
        assert_eq!(result.networks[0].ssid, "Home");
        assert_eq!(result.networks[0].strength, 80);
        assert_eq!(result.networks[0].bssid, "00:00:00:00:00:02");
        assert_eq!(result.networks[0].channel, 36);
    }

    #[test]
    fn the_connected_access_point_wins_over_a_stronger_one() {
        let mut objects = base();
        add_wifi_device(&mut objects, &["/ap/1", "/ap/2"], "/ap/1", 100);
        add_ap(&mut objects, "/ap/1", b"Home", "00:00:00:00:00:01", 40, PSK);
        add_ap(&mut objects, "/ap/2", b"Home", "00:00:00:00:00:02", 90, PSK);
        let result = snapshot(&objects, &BTreeMap::new(), &[]);
        assert!(result.networks[0].active);
        assert_eq!(result.networks[0].strength, 40);
        assert_eq!(result.wifi_status, "connected");
        assert!(result.wifi_connected);
    }

    #[test]
    fn a_profile_pinned_to_a_bssid_reads_that_access_points_signal() {
        let mut objects = base();
        add_wifi_device(&mut objects, &["/ap/1", "/ap/2"], "/", 30);
        add_ap(&mut objects, "/ap/1", b"Home", "00:00:00:00:00:01", 40, PSK);
        add_ap(&mut objects, "/ap/2", b"Home", "00:00:00:00:00:02", 90, PSK);
        let mut settings = wifi_profile("u1", b"Home", 5, Some("wpa-psk"));
        settings.get_mut("802-11-wireless").unwrap().insert("bssid".to_string(), owned(vec![0u8, 0, 0, 0, 0, 1]));
        let result = snapshot(&objects, &BTreeMap::from([("/c/1".to_string(), settings)]), &[]);
        assert_eq!(result.networks[0].strength, 40);
    }

    #[test]
    fn hidden_access_points_are_skipped_and_odd_names_are_kept_by_bytes() {
        let mut objects = base();
        add_wifi_device(&mut objects, &["/ap/1", "/ap/2"], "/", 30);
        add_ap(&mut objects, "/ap/1", b"", "00:00:00:00:00:01", 40, 0);
        add_ap(&mut objects, "/ap/2", &[0x41, 0xFF], "00:00:00:00:00:02", 40, 0);
        let result = snapshot(&objects, &BTreeMap::new(), &[]);
        assert_eq!(result.networks.len(), 1);
        assert_eq!(result.networks[0].ssid, "A\u{FFFD}");
        assert_eq!(result.networks[0].ssid_hex, "41ff");
    }

    #[test]
    fn a_network_uses_the_active_profile_then_the_most_recent_and_keeps_rank_for_never_used() {
        let mut objects = base();
        add_wifi_device(&mut objects, &["/ap/1"], "/", 30);
        add_ap(&mut objects, "/ap/1", b"Home", "00:00:00:00:00:01", 40, PSK);
        let profiles = BTreeMap::from([
            ("/c/1".to_string(), wifi_profile("old", b"Home", 10, Some("wpa-psk"))),
            ("/c/2".to_string(), wifi_profile("new", b"Home", 20, Some("wpa-psk"))),
            ("/c/3".to_string(), wifi_profile("never", b"Home", 0, Some("wpa-psk"))),
        ]);
        let result = snapshot(&objects, &profiles, &[]);
        assert_eq!(result.networks[0].saved_uuid, "new");
        assert!(!result.networks[0].never_used);

        objects.entry("/active/1".to_string()).or_default().insert(
            IFACE_ACTIVE.to_string(),
            props([("Uuid", owned("old")), ("State", owned(1u32))]),
        );
        let result = snapshot(&objects, &profiles, &[]);
        assert_eq!(result.networks[0].saved_uuid, "old");
    }

    #[test]
    fn a_profile_that_never_connected_is_flagged() {
        let mut objects = base();
        add_wifi_device(&mut objects, &["/ap/1"], "/", 30);
        add_ap(&mut objects, "/ap/1", b"Home", "00:00:00:00:00:01", 40, PSK);
        let profiles = BTreeMap::from([("/c/1".to_string(), wifi_profile("never", b"Home", 0, None))]);
        let result = snapshot(&objects, &profiles, &[]);
        assert!(result.networks[0].never_used);
        assert!(!result.networks[0].saved_credentials);
    }

    #[test]
    fn saved_profiles_stay_listed_out_of_range_with_their_protocol() {
        let mut objects = base();
        add_wifi_device(&mut objects, &[], "/", 30);
        let profiles = BTreeMap::from([
            ("/c/1".to_string(), wifi_profile("a", b"Far", 9, Some("sae"))),
            ("/c/2".to_string(), wifi_profile("b", b"Far2", 3, Some("wpa-psk"))),
            ("/c/3".to_string(), wifi_profile("c", b"Open", 1, None)),
        ]);
        let result = snapshot(&objects, &profiles, &[]);
        assert_eq!(result.profiles.iter().map(|row| row.id.as_str()).collect::<Vec<_>>(), ["a", "b", "c"]);
        assert_eq!(result.profiles[0].security_type, Security::Sae);
        assert_eq!(result.profiles[1].security_type, Security::WpaPsk);
        assert_eq!(result.profiles[2].security_type, Security::None);
        assert!(result.profiles.iter().all(|row| !row.in_range && row.signal == 0));
    }

    #[test]
    fn profiles_sort_like_plasma() {
        let mut objects = base();
        add_wifi_device(&mut objects, &["/ap/1"], "/ap/1", 100);
        add_ap(&mut objects, "/ap/1", b"Near", "00:00:00:00:00:01", 40, PSK);
        objects.entry("/active/1".to_string()).or_default().insert(
            IFACE_ACTIVE.to_string(),
            props([("Uuid", owned("near")), ("State", owned(2u32)), ("Type", owned("802-11-wireless")), ("Vpn", owned(false))]),
        );
        let mut vpn = profile("vpn-b", "vpn", &[]);
        vpn.insert("vpn".to_string(), props([("service-type", owned("org.freedesktop.NetworkManager.openvpn"))]));
        let mut vpn_earlier = profile("vpn-a", "vpn", &[]);
        vpn_earlier.insert("vpn".to_string(), props([("service-type", owned("org.freedesktop.NetworkManager.openvpn"))]));
        let profiles = BTreeMap::from([
            ("/c/1".to_string(), wifi_profile("far", b"Far", 50, Some("wpa-psk"))),
            ("/c/2".to_string(), wifi_profile("near", b"Near", 10, Some("wpa-psk"))),
            ("/c/3".to_string(), vpn),
            ("/c/4".to_string(), vpn_earlier),
            ("/c/5".to_string(), profile("wg", "wireguard", &[])),
        ]);
        let result = snapshot(&objects, &profiles, &[]);
        let order: Vec<&str> = result.profiles.iter().map(|row| row.id.as_str()).collect();
        // Available ones first: the active network, then WireGuard before VPN (by type), then what's out of reach
        assert_eq!(order, ["near", "wg", "vpn-a", "vpn-b", "far"]);
        assert_eq!(result.profiles[1].vpn_type, "wireguard");
        assert_eq!(result.profiles[2].vpn_type, "openvpn");
        assert_eq!(result.profiles[0].active_state, ACTIVE_ACTIVATED);
    }

    #[test]
    fn ports_loopback_and_nameless_profiles_are_not_listed() {
        let objects = base();
        let profiles = BTreeMap::from([
            ("/c/1".to_string(), profile("lo", "loopback", &[])),
            ("/c/2".to_string(), profile("port", "802-3-ethernet", &[("master", "bond0")])),
            ("/c/3".to_string(), profile("port2", "802-3-ethernet", &[("controller", "bond0")])),
            ("/c/4".to_string(), profile("cable", "802-3-ethernet", &[])),
        ]);
        let result = snapshot(&objects, &profiles, &[]);
        assert_eq!(result.profiles.iter().map(|row| row.id.as_str()).collect::<Vec<_>>(), ["cable"]);
    }

    #[test]
    fn wifi_status_words() {
        for (state, expected) in [(10, "disabled"), (20, "disabled"), (30, "disconnected"), (50, "connecting"), (70, "connecting"), (100, "connected"), (120, "disconnected")] {
            assert_eq!(wifi_status_word(state, "full"), expected, "state {state}");
        }
        assert_eq!(wifi_status_word(100, "limited"), "limited");
    }

    #[test]
    fn device_details_read_addresses_dns_and_speed() {
        let mut objects = base();
        add_wifi_device(&mut objects, &[], "/", 100);
        let mut address = HashMap::new();
        address.insert("address".to_string(), Variant::from("192.168.1.5"));
        address.insert("prefix".to_string(), Variant::from(24u32));
        let mut dns = HashMap::new();
        dns.insert("address".to_string(), Variant::from("1.1.1.1"));
        objects.entry("/ip4/1".to_string()).or_default().insert(
            IFACE_IP4.to_string(),
            props([
                ("AddressData", owned(vec![address])),
                ("Gateway", owned("192.168.1.1")),
                ("NameserverData", owned(vec![dns])),
                ("Domains", owned(vec!["lan"])),
            ]),
        );
        let mut address6 = HashMap::new();
        address6.insert("address".to_string(), Variant::from("fe80::1"));
        address6.insert("prefix".to_string(), Variant::from(64u32));
        let mut server = vec![0u8; 16];
        server[15] = 1;
        objects.entry("/ip6/1".to_string()).or_default().insert(
            IFACE_IP6.to_string(),
            props([("AddressData", owned(vec![address6])), ("Nameservers", owned(vec![server]))]),
        );
        let device = objects.get_mut("/dev/wlan0").unwrap().get_mut(IFACE_DEVICE).unwrap();
        device.insert("Ip4Config".to_string(), owned(object("/ip4/1")));
        device.insert("Ip6Config".to_string(), owned(object("/ip6/1")));
        let result = snapshot(&objects, &BTreeMap::new(), &[]);
        let details = result.wifi_details.unwrap();
        assert_eq!(details.ip4.addresses, ["192.168.1.5/24"]);
        assert_eq!(details.ip4.gateway, "192.168.1.1");
        assert_eq!(details.ip4.dns, ["1.1.1.1"]);
        assert_eq!(details.ip4.domains, ["lan"]);
        assert_eq!(details.ip6.addresses, ["fe80::1/64"]);
        assert_eq!(details.ip6.dns, ["::1"]);
        assert_eq!(details.speed, 866);
        assert_eq!(details.hw_address, "AA:BB:CC:00:11:22");
        assert!(details.supports_ap);
    }

    #[test]
    fn a_disconnected_device_gives_no_details_and_virtual_ones_are_hidden() {
        let mut objects = base();
        add_wifi_device(&mut objects, &[], "/", 30);
        objects.entry("/dev/p2p".to_string()).or_default().insert(
            IFACE_DEVICE.to_string(),
            props([("Interface", owned("p2p-dev-wlan0")), ("DeviceType", owned(30u32)), ("State", owned(30u32))]),
        );
        objects.entry("/dev/lo".to_string()).or_default().insert(
            IFACE_DEVICE.to_string(),
            props([("Interface", owned("lo")), ("DeviceType", owned(32u32)), ("State", owned(100u32))]),
        );
        let result = snapshot(&objects, &BTreeMap::new(), &[]);
        assert!(result.wifi_details.is_none());
        assert_eq!(result.devices.len(), 1);
        assert!(!result.ethernet_connected);
    }

    #[test]
    fn best_security_order() {
        let caps = CAPABILITY_RSN | CAPABILITY_WPA;
        assert_eq!(best_security(1, 0, SEC_KEY_SAE | PSK, caps), Security::Sae);
        assert_eq!(best_security(1, 0, SEC_KEY_SAE, caps), Security::Sae);
        assert_eq!(best_security(1, 0, SEC_KEY_SUITE_B, caps), Security::WpaEapSuiteB192);
        assert_eq!(best_security(1, 0, SEC_KEY_8021X, caps), Security::WpaEap);
        assert_eq!(best_security(1, 0, PSK, caps), Security::WpaPsk);
        assert_eq!(best_security(1, PSK, 0, caps), Security::WpaPsk);
        assert_eq!(best_security(1, SEC_KEY_8021X, 0, caps), Security::WpaEap);
        assert_eq!(best_security(1, 0, 0, caps), Security::Wep);
        assert_eq!(best_security(0, 0, SEC_KEY_OWE, caps), Security::Owe);
        assert_eq!(best_security(0, 0, 0, caps), Security::None);
        // A device that can't do the network's protocol
        assert_eq!(best_security(1, 0, PSK, CAPABILITY_WPA), Security::Unknown);
    }

    #[test]
    fn protocol_words_match_nmcli() {
        assert_eq!(security_words(0, 0, 0), "");
        assert_eq!(security_words(1, 0, 0), "WEP");
        assert_eq!(security_words(1, 0, PSK), "WPA2");
        assert_eq!(security_words(1, PSK, PSK), "WPA1 WPA2");
        assert_eq!(security_words(1, 0, PSK | SEC_KEY_SAE), "WPA2 WPA3");
        assert_eq!(security_words(1, 0, SEC_KEY_8021X), "WPA2 802.1X");
        assert_eq!(security_words(0, 0, SEC_KEY_OWE), "OWE");
        assert_eq!(security_words(0, 0, SEC_KEY_OWE_TM), "OWE-TM");
    }

    #[test]
    fn saved_security_kinds() {
        let with = |key_mgmt: &str, auth: Option<&str>| {
            let mut settings = wifi_profile("x", b"x", 0, Some(key_mgmt));
            if let Some(auth) = auth {
                settings.get_mut("802-11-wireless-security").unwrap().insert("auth-alg".to_string(), owned(auth));
            }
            profile_security(&settings)
        };
        assert_eq!(with("none", None), Security::Wep);
        assert_eq!(with("ieee8021x", None), Security::DynamicWep);
        assert_eq!(with("ieee8021x", Some("leap")), Security::Leap);
        assert_eq!(with("wpa-psk", None), Security::WpaPsk);
        assert_eq!(with("sae", None), Security::Sae);
        assert_eq!(with("owe", None), Security::Owe);
        assert_eq!(with("wpa-eap", None), Security::WpaEap);
        assert_eq!(with("wpa-eap-suite-b-192", None), Security::WpaEapSuiteB192);
        assert_eq!(with("weird", None), Security::Unknown);
    }

    #[test]
    fn security_kinds_know_how_they_join() {
        assert!(Security::WpaPsk.is_personal() && Security::Sae.is_personal() && Security::Wep.is_personal());
        assert!(!Security::Owe.is_personal() && !Security::None.is_personal());
        assert!(Security::WpaEap.is_enterprise() && Security::Leap.is_enterprise());
        assert_eq!(Security::Sae.key_mgmt(), "sae");
        assert_eq!(Security::Wep.key_mgmt(), "none");
        assert_eq!(Security::Leap.key_mgmt(), "ieee8021x");
    }

    #[test]
    fn channels_across_the_bands() {
        for (frequency, expected) in [(2412, 1), (2437, 6), (2484, 14), (5180, 36), (5825, 165), (5955, 1), (6135, 37), (900, 0)] {
            assert_eq!(channel(frequency), expected, "{frequency} MHz");
        }
    }

    #[test]
    fn connectivity_words() {
        assert_eq!(connectivity_word(4), "full");
        assert_eq!(connectivity_word(3), "limited");
        assert_eq!(connectivity_word(2), "portal");
        assert_eq!(connectivity_word(1), "none");
        assert_eq!(connectivity_word(0), "unknown");
    }

    #[test]
    fn it_serializes_in_the_shells_case() {
        let mut objects = base();
        add_wifi_device(&mut objects, &["/ap/1"], "/ap/1", 100);
        add_ap(&mut objects, "/ap/1", b"Home", "00:00:00:00:00:01", 40, PSK | SEC_KEY_SAE);
        let value = serde_json::to_value(snapshot(&objects, &BTreeMap::new(), &[])).unwrap();
        assert_eq!(value["wifiEnabled"], true);
        assert_eq!(value["networks"][0]["securityType"], "sae");
        assert_eq!(value["networks"][0]["security"], "WPA2 WPA3");
        assert_eq!(value["wifiDetails"]["interface"], "wlan0");
    }
}
