//! What the shell shows about Bluetooth, from BlueZ's objects. Devices are listed as in bluedevil: the paired
//! or connected ones, connected first and blocked last, by name.

use crate::values::{self, Objects, Props};
use serde::Serialize;
use std::collections::HashMap;

pub const IFACE_ADAPTER: &str = "org.bluez.Adapter1";
pub const IFACE_DEVICE: &str = "org.bluez.Device1";
pub const IFACE_BATTERY: &str = "org.bluez.Battery1";

const UUID_OBEX_PUSH: &str = "00001105-0000-1000-8000-00805f9b34fb";
const UUID_NAP: &str = "00001116-0000-1000-8000-00805f9b34fb";
const UUID_DUN: &str = "00001103-0000-1000-8000-00805f9b34fb";

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdapterInfo {
    pub path: String,
    pub name: String,
    pub address: String,
    pub powered: bool,
    pub discoverable: bool,
    pub discoverable_timeout: i64,
    pub pairable: bool,
    pub discovering: bool,
    pub hci: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceInfo {
    pub path: String,
    pub adapter: String,
    pub adapter_name: String,
    pub address: String,
    pub name: String,
    /// `name`, with the adapter added when the same device is seen by two of them
    pub full_name: String,
    /// The device has a name of its own, rather than just its address
    pub named: bool,
    pub device_type: &'static str,
    pub icon: String,
    pub paired: bool,
    pub bonded: bool,
    pub trusted: bool,
    pub blocked: bool,
    pub connected: bool,
    pub services_resolved: bool,
    pub rssi: Option<i64>,
    pub battery: Option<i64>,
    pub services: Vec<&'static str>,
    pub uuids: Vec<String>,
    pub can_receive_files: bool,
    pub can_share_network: bool,
    pub can_dial_up: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BluetoothSnapshot {
    pub available: bool,
    /// A soft or hard radio block is on, or absent if unknown
    pub soft_blocked: bool,
    pub hard_blocked: bool,
    pub powered: bool,
    pub discovering: bool,
    pub adapters: Vec<AdapterInfo>,
    /// Paired or connected devices, in display order
    pub saved: Vec<DeviceInfo>,
    /// The rest, those around right now, strongest first
    pub nearby: Vec<DeviceInfo>,
}

impl BluetoothSnapshot {
    pub fn unavailable() -> Self {
        Self { available: false, soft_blocked: false, hard_blocked: false, powered: false, discovering: false, adapters: Vec::new(), saved: Vec::new(), nearby: Vec::new() }
    }
}

/// The name of a Bluetooth service, for those a person might recognise.
pub fn service_name(uuid: &str) -> Option<&'static str> {
    let short = uuid.strip_suffix("-0000-1000-8000-00805f9b34fb")?.strip_prefix("0000")?;
    Some(match short.to_ascii_lowercase().as_str() {
        "1101" => "Serial port",
        "1103" => "Dial-up networking",
        "1105" => "Sending files",
        "1106" => "File transfer",
        "1108" => "Headset",
        "110a" => "Audio source",
        "110b" => "Audio playback",
        "110c" | "110e" | "110f" => "Remote control",
        "1112" => "Headset gateway",
        "1115" => "Network access",
        "1116" => "Network sharing",
        "1117" => "Network sharing (group)",
        "111e" => "Hands-free calls",
        "111f" => "Hands-free gateway",
        "1124" => "Input device",
        "112f" => "Phone book",
        "1132" => "Messages",
        "1200" => "Device information",
        "1800" | "1801" => return None,
        "180a" => "Device information",
        "180f" => "Battery level",
        "1812" => "Input device",
        "184e" | "184f" | "1850" | "1853" | "1854" | "1856" => "LE audio",
        _ => return None,
    })
}

/// What kind of device it is, from what it says of itself: its icon when it has one, else its class.
pub fn device_type(icon: &str, class: i64) -> &'static str {
    match icon {
        "phone" => return "phone",
        "modem" => return "modem",
        "computer" => return "computer",
        "network-wireless" => return "network",
        "audio-headset" => return "headset",
        "audio-headphones" => return "headphones",
        "audio-card" | "audio-speakers" | "multimedia-player" => return "audio",
        "input-keyboard" => return "keyboard",
        "input-mouse" => return "mouse",
        "input-gaming" => return "joypad",
        "input-tablet" => return "tablet",
        "camera-photo" | "camera-video" => return "camera",
        "printer" => return "printer",
        "video-display" => return "display",
        _ => {}
    }
    match (class >> 8) & 0x1f {
        1 => "computer",
        2 => "phone",
        3 => "network",
        4 => match (class >> 2) & 0x3f {
            1 | 2 => "headset",
            6 => "headphones",
            _ => "audio",
        },
        5 => match (class >> 6) & 0x3 {
            1 => "keyboard",
            2 => "mouse",
            _ => match (class >> 2) & 0xf {
                1 | 2 => "joypad",
                5 => "tablet",
                _ => "peripheral",
            },
        },
        6 => {
            if class & 0x80 != 0 {
                "printer"
            } else if class & 0x20 != 0 {
                "camera"
            } else {
                "imaging"
            }
        }
        7 => "wearable",
        8 => "toy",
        9 => "health",
        _ => "unknown",
    }
}

fn adapter_info(path: &str, props: &Props) -> AdapterInfo {
    AdapterInfo {
        path: path.to_string(),
        name: values::text(props, "Alias").or_else(|| values::text(props, "Name")).unwrap_or_default(),
        address: values::text_or_empty(props, "Address"),
        powered: values::flag(props, "Powered").unwrap_or(false),
        discoverable: values::flag(props, "Discoverable").unwrap_or(false),
        discoverable_timeout: values::number(props, "DiscoverableTimeout").unwrap_or(0),
        pairable: values::flag(props, "Pairable").unwrap_or(false),
        discovering: values::flag(props, "Discovering").unwrap_or(false),
        hci: path.rsplit('/').next().unwrap_or_default().to_string(),
    }
}

/// The whole picture. `(soft, hard)` is the state of the radio switches, which BlueZ doesn't report.
pub fn snapshot(objects: &Objects, blocked: (bool, bool)) -> BluetoothSnapshot {
    let adapters: Vec<AdapterInfo> = objects.iter().filter_map(|(path, interfaces)| Some(adapter_info(path, interfaces.get(IFACE_ADAPTER)?))).collect();
    if adapters.is_empty() {
        return BluetoothSnapshot { soft_blocked: blocked.0, hard_blocked: blocked.1, ..BluetoothSnapshot::unavailable() };
    }
    let names: HashMap<&str, &AdapterInfo> = adapters.iter().map(|adapter| (adapter.path.as_str(), adapter)).collect();
    let mut seen: HashMap<String, u32> = HashMap::new();
    for interfaces in objects.values() {
        if let Some(props) = interfaces.get(IFACE_DEVICE) {
            *seen.entry(values::text_or_empty(props, "Address")).or_default() += 1;
        }
    }
    let mut saved = Vec::new();
    let mut nearby = Vec::new();
    for (path, interfaces) in objects {
        let Some(props) = interfaces.get(IFACE_DEVICE) else { continue };
        let address = values::text_or_empty(props, "Address");
        let alias = values::text(props, "Alias").unwrap_or_else(|| address.clone());
        let adapter_path = values::path(props, "Adapter").unwrap_or_default();
        let adapter = names.get(adapter_path.as_str());
        let full_name = match adapter {
            Some(adapter) if seen.get(&address).copied().unwrap_or(0) > 1 => format!("{alias} - {}", adapter.hci),
            _ => alias.clone(),
        };
        let uuids = values::strings(props, "UUIDs");
        let mut services: Vec<&'static str> = uuids.iter().filter_map(|uuid| service_name(uuid)).collect();
        services.sort_unstable();
        services.dedup();
        let has = |wanted: &str| uuids.iter().any(|uuid| uuid.eq_ignore_ascii_case(wanted));
        let icon = values::text_or_empty(props, "Icon");
        // BlueZ fills `Alias` with the address, with dashes, for a device with no name
        let named = values::text(props, "Name").is_some() || alias.replace('-', ":") != address;
        let device = DeviceInfo {
            path: path.clone(),
            adapter: adapter_path.clone(),
            adapter_name: adapter.map(|adapter| adapter.name.clone()).unwrap_or_default(),
            device_type: device_type(&icon, values::number(props, "Class").unwrap_or(0)),
            icon,
            name: alias,
            full_name,
            named,
            address,
            paired: values::flag(props, "Paired").unwrap_or(false),
            bonded: values::flag(props, "Bonded").unwrap_or(false),
            trusted: values::flag(props, "Trusted").unwrap_or(false),
            blocked: values::flag(props, "Blocked").unwrap_or(false),
            connected: values::flag(props, "Connected").unwrap_or(false),
            services_resolved: values::flag(props, "ServicesResolved").unwrap_or(false),
            rssi: values::number(props, "RSSI"),
            battery: interfaces.get(IFACE_BATTERY).and_then(|battery| values::number(battery, "Percentage")),
            can_receive_files: has(UUID_OBEX_PUSH),
            can_share_network: has(UUID_NAP),
            can_dial_up: has(UUID_DUN),
            services,
            uuids,
        };
        if device.paired || device.connected {
            saved.push(device);
        } else {
            nearby.push(device);
        }
    }
    saved.sort_by(|a, b| {
        a.blocked.cmp(&b.blocked).then_with(|| b.connected.cmp(&a.connected)).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())).then_with(|| a.path.cmp(&b.path))
    });
    nearby.sort_by(|a, b| {
        b.named.cmp(&a.named).then_with(|| b.rssi.unwrap_or(-200).cmp(&a.rssi.unwrap_or(-200))).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())).then_with(|| a.path.cmp(&b.path))
    });
    BluetoothSnapshot {
        available: true,
        soft_blocked: blocked.0,
        hard_blocked: blocked.1,
        powered: adapters.iter().any(|adapter| adapter.powered),
        discovering: adapters.iter().any(|adapter| adapter.discovering),
        adapters,
        saved,
        nearby,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::values::build::{owned, props};
    use zbus::{ObjectPath, Variant};

    fn adapter(objects: &mut Objects, path: &str, powered: bool) {
        objects.entry(path.to_string()).or_default().insert(
            IFACE_ADAPTER.to_string(),
            props([("Alias", owned("laptop")), ("Address", owned("AA:AA:AA:AA:AA:AA")), ("Powered", owned(powered)), ("Discoverable", owned(false)), ("Pairable", owned(true)), ("Discovering", owned(false)), ("DiscoverableTimeout", owned(180u32))]),
        );
    }

    fn device(objects: &mut Objects, path: &str, name: &str, address: &str, extra: Props) {
        let mut base = props([("Alias", owned(name)), ("Address", owned(address)), ("Name", owned(name)), ("Adapter", owned(ObjectPath::try_from("/org/bluez/hci0").unwrap()))]);
        base.extend(extra);
        objects.entry(path.to_string()).or_default().insert(IFACE_DEVICE.to_string(), base);
    }

    #[test]
    fn nothing_without_an_adapter() {
        let result = snapshot(&Objects::new(), (true, false));
        assert!(!result.available);
        assert!(result.soft_blocked);
    }

    #[test]
    fn saved_devices_are_ordered_as_bluedevil_does() {
        let mut objects = Objects::new();
        adapter(&mut objects, "/org/bluez/hci0", true);
        device(&mut objects, "/d/1", "Zed", "00:00:00:00:00:01", props([("Paired", owned(true))]));
        device(&mut objects, "/d/2", "alpha", "00:00:00:00:00:02", props([("Paired", owned(true))]));
        device(&mut objects, "/d/3", "Middle", "00:00:00:00:00:03", props([("Paired", owned(true)), ("Connected", owned(true))]));
        device(&mut objects, "/d/4", "Blocked", "00:00:00:00:00:04", props([("Paired", owned(true)), ("Connected", owned(true)), ("Blocked", owned(true))]));
        let result = snapshot(&objects, (false, false));
        let order: Vec<&str> = result.saved.iter().map(|device| device.name.as_str()).collect();
        assert_eq!(order, ["Middle", "alpha", "Zed", "Blocked"]);
        assert!(result.powered);
    }

    #[test]
    fn a_connected_device_counts_as_saved_and_the_rest_are_nearby() {
        let mut objects = Objects::new();
        adapter(&mut objects, "/org/bluez/hci0", true);
        device(&mut objects, "/d/1", "Linked", "00:00:00:00:00:01", props([("Connected", owned(true))]));
        device(&mut objects, "/d/2", "Weak", "00:00:00:00:00:02", props([("RSSI", owned(-80i16))]));
        device(&mut objects, "/d/3", "Strong", "00:00:00:00:00:03", props([("RSSI", owned(-40i16))]));
        let mut unnamed = props([("Alias", owned("00-00-00-00-00-04")), ("Address", owned("00:00:00:00:00:04")), ("RSSI", owned(-10i16))]);
        unnamed.insert("Adapter".to_string(), owned(ObjectPath::try_from("/org/bluez/hci0").unwrap()));
        objects.entry("/d/4".to_string()).or_default().insert(IFACE_DEVICE.to_string(), unnamed);
        let result = snapshot(&objects, (false, false));
        assert_eq!(result.saved.iter().map(|device| device.name.as_str()).collect::<Vec<_>>(), ["Linked"]);
        assert_eq!(result.nearby.iter().map(|device| device.name.as_str()).collect::<Vec<_>>(), ["Strong", "Weak", "00-00-00-00-00-04"]);
        assert!(!result.nearby[2].named);
        assert!(result.nearby[0].named);
    }

    #[test]
    fn a_device_seen_by_two_adapters_says_which() {
        let mut objects = Objects::new();
        adapter(&mut objects, "/org/bluez/hci0", true);
        adapter(&mut objects, "/org/bluez/hci1", false);
        device(&mut objects, "/d/1", "Phone", "00:00:00:00:00:01", props([("Paired", owned(true))]));
        device(&mut objects, "/d/2", "Phone", "00:00:00:00:00:01", props([("Paired", owned(true))]));
        device(&mut objects, "/d/3", "Other", "00:00:00:00:00:02", props([("Paired", owned(true))]));
        let result = snapshot(&objects, (false, false));
        assert_eq!(result.saved.iter().find(|device| device.path == "/d/1").unwrap().full_name, "Phone - hci0");
        assert_eq!(result.saved.iter().find(|device| device.path == "/d/3").unwrap().full_name, "Other");
    }

    #[test]
    fn battery_services_and_abilities() {
        let mut objects = Objects::new();
        adapter(&mut objects, "/org/bluez/hci0", true);
        let uuids = vec![
            "0000110b-0000-1000-8000-00805f9b34fb".to_string(),
            "0000110e-0000-1000-8000-00805f9b34fb".to_string(),
            UUID_OBEX_PUSH.to_string(),
            UUID_NAP.to_string(),
            UUID_DUN.to_string(),
            "12345678-0000-1000-8000-00805f9b34fb".to_string(),
        ];
        device(&mut objects, "/d/1", "Phone", "00:00:00:00:00:01", props([("Paired", owned(true)), ("UUIDs", owned(uuids)), ("Icon", owned("phone"))]));
        objects.get_mut("/d/1").unwrap().insert(IFACE_BATTERY.to_string(), props([("Percentage", owned(77u8))]));
        let result = snapshot(&objects, (false, false));
        let phone = &result.saved[0];
        assert_eq!(phone.battery, Some(77));
        assert_eq!(phone.services, ["Audio playback", "Dial-up networking", "Network sharing", "Remote control", "Sending files"]);
        assert!(phone.can_receive_files && phone.can_share_network && phone.can_dial_up);
        assert_eq!(phone.device_type, "phone");
    }

    #[test]
    fn device_kinds_come_from_the_icon_then_the_class() {
        for (icon, expected) in [("audio-headset", "headset"), ("audio-headphones", "headphones"), ("input-mouse", "mouse"), ("input-keyboard", "keyboard"), ("input-gaming", "joypad"), ("computer", "computer"), ("printer", "printer"), ("audio-card", "audio")] {
            assert_eq!(device_type(icon, 0), expected);
        }
        assert_eq!(device_type("", 0x200404), "headset");
        assert_eq!(device_type("", 0x240418), "headphones");
        assert_eq!(device_type("", 0x5a020c), "phone");
        assert_eq!(device_type("", 0x002540), "keyboard");
        assert_eq!(device_type("", 0x002580), "mouse");
        assert_eq!(device_type("", 0x002508), "joypad");
        assert_eq!(device_type("", 0x000100), "computer");
        assert_eq!(device_type("", 0x000680), "printer");
        assert_eq!(device_type("", 0), "unknown");
    }

    #[test]
    fn only_recognised_services_are_named() {
        assert_eq!(service_name("0000110b-0000-1000-8000-00805f9b34fb"), Some("Audio playback"));
        assert_eq!(service_name("0000110B-0000-1000-8000-00805F9B34FB"), None, "BlueZ reports lower case");
        assert_eq!(service_name("00001800-0000-1000-8000-00805f9b34fb"), None);
        assert_eq!(service_name("not a uuid"), None);
    }

    #[test]
    fn it_reads_values_nested_as_variants() {
        let mut objects = Objects::new();
        adapter(&mut objects, "/org/bluez/hci0", true);
        device(&mut objects, "/d/1", "X", "00:00:00:00:00:01", props([("Paired", owned(Variant::from(true)))]));
        assert!(snapshot(&objects, (false, false)).saved[0].paired);
    }

    #[test]
    fn it_serializes_in_the_shells_case() {
        let mut objects = Objects::new();
        adapter(&mut objects, "/org/bluez/hci0", true);
        let value = serde_json::to_value(snapshot(&objects, (false, false))).unwrap();
        assert_eq!(value["adapters"][0]["discoverableTimeout"], 180);
        assert_eq!(value["softBlocked"], false);
    }
}
