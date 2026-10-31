//! What Bluetooth should do at login and after sleep, as in bluedevil: stay as it was left, or be turned on
//! or off. What it was left as is kept in a small file: which adapters were on and what was connected.

use super::model::BluetoothSnapshot;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OnLogin {
    Remember,
    On,
    Off,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SavedState {
    /// Adapter address → on
    pub powered: BTreeMap<String, bool>,
    /// Addresses of connected devices
    pub connected: Vec<String>,
}

pub fn capture(snapshot: &BluetoothSnapshot) -> SavedState {
    SavedState {
        powered: snapshot.adapters.iter().map(|adapter| (adapter.address.clone(), adapter.powered)).collect(),
        connected: snapshot.saved.iter().filter(|device| device.connected).map(|device| device.address.clone()).collect(),
    }
}

/// What to do to reach the wanted state.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Plan {
    pub power: Vec<(String, bool)>,
    pub connect: Vec<String>,
}

pub fn plan(mode: OnLogin, saved: &SavedState, snapshot: &BluetoothSnapshot) -> Plan {
    let mut plan = Plan::default();
    for adapter in &snapshot.adapters {
        let wanted = match mode {
            OnLogin::On => true,
            OnLogin::Off => false,
            // An adapter never seen before stays as it is
            OnLogin::Remember => saved.powered.get(&adapter.address).copied().unwrap_or(adapter.powered),
        };
        if wanted != adapter.powered {
            plan.power.push((adapter.path.clone(), wanted));
        }
    }
    if mode != OnLogin::Off {
        for device in snapshot.saved.iter().filter(|device| !device.connected && !device.blocked && saved.connected.contains(&device.address)) {
            plan.connect.push(device.path.clone());
        }
    }
    plan
}

pub fn state_file() -> PathBuf {
    let directory = std::env::var_os("XDG_STATE_HOME").map_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state"), PathBuf::from);
    directory.join("velora/bluetooth-state.json")
}

pub fn load() -> SavedState {
    std::fs::read_to_string(state_file()).ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_default()
}

pub fn save(state: &SavedState) {
    let path = state_file();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let staged = path.with_extension("new");
    if std::fs::write(&staged, serde_json::to_string(state).expect("plain values")).is_ok() {
        let _ = std::fs::rename(&staged, &path);
    }
}

#[cfg(test)]
mod tests {
    use super::super::model::{AdapterInfo, DeviceInfo};
    use super::*;

    fn adapter(address: &str, powered: bool) -> AdapterInfo {
        AdapterInfo { path: format!("/{address}"), name: String::new(), address: address.to_string(), powered, discoverable: false, discoverable_timeout: 0, pairable: false, discovering: false, hci: "hci0".to_string() }
    }

    fn device(address: &str, connected: bool, blocked: bool) -> DeviceInfo {
        DeviceInfo {
            path: format!("/dev/{address}"), adapter: String::new(), adapter_name: String::new(), address: address.to_string(), name: address.to_string(), full_name: address.to_string(), named: true,
            device_type: "unknown", icon: String::new(), paired: true, bonded: true, trusted: true, blocked, connected, services_resolved: false, rssi: None, battery: None, services: Vec::new(), uuids: Vec::new(),
            can_receive_files: false, can_share_network: false, can_dial_up: false,
        }
    }

    fn snapshot(adapters: Vec<AdapterInfo>, saved: Vec<DeviceInfo>) -> BluetoothSnapshot {
        BluetoothSnapshot { available: true, soft_blocked: false, hard_blocked: false, powered: false, discovering: false, adapters, saved, nearby: Vec::new() }
    }

    #[test]
    fn what_is_captured() {
        let state = capture(&snapshot(vec![adapter("A", true), adapter("B", false)], vec![device("X", true, false), device("Y", false, false)]));
        assert_eq!(state.powered, BTreeMap::from([("A".to_string(), true), ("B".to_string(), false)]));
        assert_eq!(state.connected, ["X"]);
    }

    #[test]
    fn remember_restores_adapters_and_connections() {
        let saved = SavedState { powered: BTreeMap::from([("A".to_string(), true), ("B".to_string(), false)]), connected: vec!["X".to_string(), "Gone".to_string(), "Up".to_string(), "Blocked".to_string()] };
        let now = snapshot(vec![adapter("A", false), adapter("B", true), adapter("New", true)], vec![device("X", false, false), device("Up", true, false), device("Blocked", false, true), device("Other", false, false)]);
        let plan = plan(OnLogin::Remember, &saved, &now);
        assert_eq!(plan.power, [("/A".to_string(), true), ("/B".to_string(), false)]);
        assert_eq!(plan.connect, ["/dev/X"]);
    }

    #[test]
    fn on_and_off_ignore_what_was_left() {
        let saved = SavedState { powered: BTreeMap::from([("A".to_string(), false)]), connected: vec!["X".to_string()] };
        let now = snapshot(vec![adapter("A", false)], vec![device("X", false, false)]);
        assert_eq!(plan(OnLogin::On, &saved, &now).power, [("/A".to_string(), true)]);
        assert_eq!(plan(OnLogin::On, &saved, &now).connect, ["/dev/X"]);
        let on = snapshot(vec![adapter("A", true)], vec![device("X", false, false)]);
        let off = plan(OnLogin::Off, &saved, &on);
        assert_eq!(off.power, [("/A".to_string(), false)]);
        assert!(off.connect.is_empty());
    }

    #[test]
    fn nothing_to_do_when_it_is_already_so() {
        let saved = SavedState { powered: BTreeMap::from([("A".to_string(), true)]), connected: Vec::new() };
        assert_eq!(plan(OnLogin::Remember, &saved, &snapshot(vec![adapter("A", true)], Vec::new())), Plan::default());
    }

    #[test]
    fn modes_read_from_settings_words() {
        assert_eq!(serde_json::from_str::<OnLogin>("\"remember\"").unwrap(), OnLogin::Remember);
        assert_eq!(serde_json::from_str::<OnLogin>("\"on\"").unwrap(), OnLogin::On);
        assert_eq!(serde_json::from_str::<OnLogin>("\"off\"").unwrap(), OnLogin::Off);
    }
}
