//! Airplane mode, as in plasma-nm: every radio off, remembering which were on, so turning it off again brings
//! back just those. What was on is kept in a small file, whose presence is the mode itself.

use crate::bluez::client::BluezClient;
use crate::nm::client::NmClient;
use crate::protocol::ApiError;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Before {
    pub wifi: bool,
    pub wwan: bool,
    /// Adapter path → on
    pub bluetooth: BTreeMap<String, bool>,
}

fn state_file() -> PathBuf {
    let directory = std::env::var_os("XDG_STATE_HOME").map_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state"), PathBuf::from);
    directory.join("velora/airplane-mode.json")
}

pub fn is_on() -> bool {
    state_file().exists()
}

fn read() -> Option<Before> {
    serde_json::from_str(&std::fs::read_to_string(state_file()).ok()?).ok()
}

fn write(before: &Before) -> Result<(), ApiError> {
    let path = state_file();
    let failed = |_| ApiError::new(crate::protocol::ErrorCode::Failed, "Airplane mode's state couldn't be saved");
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(failed)?;
    }
    std::fs::write(&path, serde_json::to_string(before).expect("plain values")).map_err(failed)
}

pub async fn set(network: &NmClient, bluetooth: &BluezClient, enabled: bool) -> Result<(), ApiError> {
    if enabled {
        // Turning it on twice mustn't overwrite what was on with "nothing"
        if is_on() {
            return Ok(());
        }
        let adapters = bluetooth.snapshot().await.adapters;
        let before = Before {
            wifi: network.wifi_enabled().await.unwrap_or(false),
            wwan: network.wwan_enabled().await.unwrap_or(false),
            bluetooth: adapters.iter().map(|adapter| (adapter.path.clone(), adapter.powered)).collect(),
        };
        write(&before)?;
        network.set_wifi_enabled(false).await?;
        network.set_wwan_enabled(false).await?;
        for adapter in adapters.iter().filter(|adapter| adapter.powered) {
            bluetooth.set_powered(&adapter.path, false).await?;
        }
    } else {
        let before = read().unwrap_or(Before { wifi: true, wwan: true, bluetooth: BTreeMap::new() });
        let _ = std::fs::remove_file(state_file());
        if before.wifi {
            network.set_wifi_enabled(true).await?;
        }
        if before.wwan {
            network.set_wwan_enabled(true).await?;
        }
        for (adapter, powered) in before.bluetooth.iter().filter(|(_, powered)| **powered) {
            bluetooth.set_powered(adapter, *powered).await?;
        }
    }
    network.changed.notify_one();
    bluetooth.changed.notify_one();
    Ok(())
}
