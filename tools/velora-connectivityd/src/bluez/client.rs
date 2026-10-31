//! Talking to BlueZ: reading its state, watching for changes and acting on adapters and devices.

use super::model::{self, BluetoothSnapshot, IFACE_ADAPTER, IFACE_DEVICE};
use crate::protocol::{ApiError, ErrorCode};
use crate::values::{Interfaces, Objects};
use futures_util::StreamExt;
use std::collections::HashMap;
use std::num::NonZeroUsize;
use std::path::PathBuf;
use std::process::Stdio;
use tokio::process::Command;
use tokio::sync::Notify;
use zbus::message::Type as MessageType;
use zbus::{Connection, MatchRule, MessageStream, ObjectPath, OwnedObjectPath, Variant};

pub const BUS_NAME: &str = "org.bluez";

/// A BlueZ error, in the terms the settings page explains to people.
pub fn bluez_error(error: &zbus::Error) -> ApiError {
    let (name, detail) = match error {
        zbus::Error::MethodError(name, message, _) => (name.to_string(), message.clone().unwrap_or_default()),
        zbus::Error::FDO(inner) => (inner.to_string(), String::new()),
        other => return ApiError::new(ErrorCode::Failed, other.to_string()),
    };
    let short = name.rsplit('.').next().unwrap_or_default().split(':').next().unwrap_or_default();
    match short {
        "AuthenticationFailed" | "AuthenticationRejected" => ApiError::new(ErrorCode::WrongSecret, "The device refused the pairing"),
        "AuthenticationCanceled" => ApiError::new(ErrorCode::Canceled, "Pairing was canceled"),
        "AuthenticationTimeout" | "ConnectionAttemptFailed" | "Timeout" | "TimedOut" | "NoReply" => ApiError::new(ErrorCode::Timeout, "The device didn't answer. Make sure it's on and in range."),
        "AlreadyExists" => ApiError::new(ErrorCode::Conflict, "The device is already paired"),
        "AlreadyConnected" => ApiError::new(ErrorCode::Conflict, "The device is already connected"),
        "InProgress" => ApiError::new(ErrorCode::Conflict, "The device is busy with another request. Try again in a moment."),
        "NotReady" => ApiError::new(ErrorCode::Unavailable, "Bluetooth isn't ready yet"),
        "NotAvailable" | "NotSupported" => ApiError::new(ErrorCode::Unavailable, "The device doesn't offer anything this computer can connect to"),
        "NotPermitted" | "NotAuthorized" | "AccessDenied" => ApiError::new(ErrorCode::PermissionDenied, "This isn't allowed"),
        "DoesNotExist" | "UnknownObject" | "UnknownMethod" => ApiError::new(ErrorCode::NotFound, "The device is gone"),
        "ServiceUnknown" | "NameHasNoOwner" => ApiError::new(ErrorCode::Unavailable, "The Bluetooth service isn't running"),
        "InvalidArguments" | "InvalidArgs" => ApiError::invalid("The request wasn't valid"),
        _ => ApiError::new(ErrorCode::Failed, if detail.is_empty() { "The device couldn't be reached".to_string() } else { detail }),
    }
}

fn error(failure: zbus::Error) -> ApiError {
    bluez_error(&failure)
}

fn object_path(path: &str) -> Result<ObjectPath<'_>, ApiError> {
    ObjectPath::try_from(path).map_err(|_| ApiError::invalid(format!("not an object path: {path}")))
}

/// Whether the radio is blocked, softly (by a switch in software) and hard (by one on the machine).
pub fn radio_blocks(directory: &std::path::Path) -> (bool, bool) {
    let mut blocks = (false, false);
    let Ok(entries) = std::fs::read_dir(directory) else { return blocks };
    for entry in entries.filter_map(Result::ok) {
        let read = |name: &str| std::fs::read_to_string(entry.path().join(name)).unwrap_or_default();
        if read("type").trim() == "bluetooth" {
            blocks.0 |= read("soft").trim() == "1";
            blocks.1 |= read("hard").trim() == "1";
        }
    }
    blocks
}

fn rfkill_directory() -> PathBuf {
    std::env::var_os("VELORA_RFKILL_DIR").map_or_else(|| PathBuf::from("/sys/class/rfkill"), PathBuf::from)
}

pub struct BluezClient {
    connection: Connection,
    pub changed: Notify,
    /// Woken when the service comes or goes.
    pub availability_changed: Notify,
}

impl BluezClient {
    pub fn new(connection: Connection) -> Self {
        Self { connection, changed: Notify::new(), availability_changed: Notify::new() }
    }

    async fn objects(&self) -> Result<Objects, ApiError> {
        let reply = self.connection.call_method(Some(BUS_NAME), "/", Some("org.freedesktop.DBus.ObjectManager"), "GetManagedObjects", &()).await.map_err(error)?;
        let objects: HashMap<OwnedObjectPath, Interfaces> = reply.body().deserialize().map_err(error)?;
        Ok(objects.into_iter().map(|(path, interfaces)| (path.to_string(), interfaces)).collect())
    }

    pub async fn snapshot(&self) -> BluetoothSnapshot {
        let blocks = radio_blocks(&rfkill_directory());
        match self.objects().await {
            Ok(objects) => model::snapshot(&objects, blocks),
            Err(_) => BluetoothSnapshot { soft_blocked: blocks.0, hard_blocked: blocks.1, ..BluetoothSnapshot::unavailable() },
        }
    }

    pub async fn is_running(&self) -> bool {
        self.objects().await.is_ok()
    }

    /// Follows the service, poking `changed` on anything that could alter a snapshot.
    pub async fn watch(&self) -> Result<(), ApiError> {
        let rule = MatchRule::builder().msg_type(MessageType::Signal).sender(BUS_NAME).build().map_err(error)?;
        let mut signals = MessageStream::for_match_rule(rule, &self.connection, NonZeroUsize::new(256)).await.map_err(error)?;
        let owner_rule = MatchRule::builder().msg_type(MessageType::Signal).sender("org.freedesktop.DBus").member("NameOwnerChanged").arg(0, BUS_NAME).build().map_err(error)?;
        let mut owners = MessageStream::for_match_rule(owner_rule, &self.connection, NonZeroUsize::new(16)).await.map_err(error)?;
        self.changed.notify_one();
        loop {
            tokio::select! {
                Some(Ok(_)) = signals.next() => self.changed.notify_one(),
                Some(Ok(_)) = owners.next() => {
                    self.changed.notify_one();
                    self.availability_changed.notify_one();
                }
                else => return Ok(()),
            }
        }
    }

    async fn set_property<'a>(&self, path: &str, interface: &str, name: &str, value: Variant<'a>) -> Result<(), ApiError> {
        self.connection.call_method(Some(BUS_NAME), path, Some("org.freedesktop.DBus.Properties"), "Set", &(interface, name, value)).await.map_err(error)?;
        Ok(())
    }

    /// Turns Bluetooth on or off everywhere, as bluedevil's switch does: the radio block and every adapter.
    pub async fn set_enabled(&self, enabled: bool) -> Result<(), ApiError> {
        if enabled {
            // Without this, turning on an adapter fails while the radio is blocked; it's also harmless if rfkill is missing
            let _ = Command::new("rfkill").args(["unblock", "bluetooth"]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status().await;
        }
        for adapter in self.snapshot().await.adapters {
            self.set_property(&adapter.path, IFACE_ADAPTER, "Powered", Variant::from(enabled)).await?;
        }
        self.changed.notify_one();
        Ok(())
    }

    pub async fn set_powered(&self, adapter: &str, powered: bool) -> Result<(), ApiError> {
        self.set_property(adapter, IFACE_ADAPTER, "Powered", Variant::from(powered)).await
    }

    /// Being found goes with accepting pairing, or a phone that finds this computer couldn't pair with it.
    pub async fn set_discoverable(&self, adapter: &str, discoverable: bool) -> Result<(), ApiError> {
        if discoverable {
            self.set_property(adapter, IFACE_ADAPTER, "Pairable", Variant::from(true)).await?;
        }
        self.set_property(adapter, IFACE_ADAPTER, "Discoverable", Variant::from(discoverable)).await
    }

    pub async fn set_discoverable_timeout(&self, adapter: &str, seconds: u32) -> Result<(), ApiError> {
        self.set_property(adapter, IFACE_ADAPTER, "DiscoverableTimeout", Variant::from(seconds)).await
    }

    pub async fn set_adapter_name(&self, adapter: &str, name: &str) -> Result<(), ApiError> {
        self.set_property(adapter, IFACE_ADAPTER, "Alias", Variant::from(name)).await
    }

    /// Looks for devices for as long as this process wants; BlueZ stops by itself if it goes away.
    pub async fn set_discovering(&self, discovering: bool) -> Result<(), ApiError> {
        let method = if discovering { "StartDiscovery" } else { "StopDiscovery" };
        for adapter in self.snapshot().await.adapters.iter().filter(|adapter| adapter.powered) {
            match self.connection.call_method(Some(BUS_NAME), adapter.path.as_str(), Some(IFACE_ADAPTER), method, &()).await {
                Ok(_) => {}
                // Already doing as asked, by this process or another
                Err(failure) if matches!(bluez_error(&failure).code, ErrorCode::Conflict | ErrorCode::Failed) => {}
                Err(failure) => return Err(error(failure)),
            }
        }
        Ok(())
    }

    /// Pairs a device, marks it trusted so it reconnects by itself, and connects, in the order bluedevil's
    /// wizard does. A device that's already paired just connects.
    pub async fn pair_and_connect(&self, device: &str) -> Result<(), ApiError> {
        let reply = self.connection.call_method(Some(BUS_NAME), device, Some("org.freedesktop.DBus.Properties"), "Get", &(IFACE_DEVICE, "Paired")).await.map_err(error)?;
        let paired: bool = reply.body().deserialize::<zbus::OwnedVariant>().map_err(error).and_then(|value| bool::try_from(value).map_err(error))?;
        if !paired {
            self.connection.call_method(Some(BUS_NAME), device, Some(IFACE_DEVICE), "Pair", &()).await.map_err(error)?;
        }
        self.set_property(device, IFACE_DEVICE, "Trusted", Variant::from(true)).await?;
        self.connect(device).await
    }

    pub async fn cancel_pairing(&self, device: &str) -> Result<(), ApiError> {
        self.connection.call_method(Some(BUS_NAME), device, Some(IFACE_DEVICE), "CancelPairing", &()).await.map_err(error)?;
        Ok(())
    }

    pub async fn connect(&self, device: &str) -> Result<(), ApiError> {
        self.connection.call_method(Some(BUS_NAME), device, Some(IFACE_DEVICE), "Connect", &()).await.map_err(error)?;
        Ok(())
    }

    pub async fn disconnect(&self, device: &str) -> Result<(), ApiError> {
        self.connection.call_method(Some(BUS_NAME), device, Some(IFACE_DEVICE), "Disconnect", &()).await.map_err(error)?;
        Ok(())
    }

    pub async fn set_trusted(&self, device: &str, trusted: bool) -> Result<(), ApiError> {
        self.set_property(device, IFACE_DEVICE, "Trusted", Variant::from(trusted)).await
    }

    pub async fn set_blocked(&self, device: &str, blocked: bool) -> Result<(), ApiError> {
        self.set_property(device, IFACE_DEVICE, "Blocked", Variant::from(blocked)).await
    }

    pub async fn rename(&self, device: &str, name: &str) -> Result<(), ApiError> {
        self.set_property(device, IFACE_DEVICE, "Alias", Variant::from(name)).await
    }

    /// Forgets a paired device. `RemoveDevice` is called on its adapter, and undoes the pairing too.
    pub async fn forget(&self, device: &str) -> Result<(), ApiError> {
        let adapter = device.rsplit_once('/').map(|(adapter, _)| adapter).ok_or_else(|| ApiError::invalid("not a device"))?;
        self.connection.call_method(Some(BUS_NAME), adapter, Some(IFACE_ADAPTER), "RemoveDevice", &(object_path(device)?,)).await.map_err(error)?;
        self.changed.notify_one();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn radio_blocks_are_read_for_bluetooth_only() {
        let directory = std::env::temp_dir().join(format!("velora-rfkill-test-{}", std::process::id()));
        let wifi = directory.join("rfkill1");
        let bluetooth = directory.join("rfkill0");
        std::fs::create_dir_all(&wifi).unwrap();
        std::fs::create_dir_all(&bluetooth).unwrap();
        for (path, kind, soft, hard) in [(&wifi, "wlan", "1", "1"), (&bluetooth, "bluetooth", "0", "0")] {
            std::fs::write(path.join("type"), format!("{kind}\n")).unwrap();
            std::fs::write(path.join("soft"), format!("{soft}\n")).unwrap();
            std::fs::write(path.join("hard"), format!("{hard}\n")).unwrap();
        }
        assert_eq!(radio_blocks(&directory), (false, false));
        std::fs::write(bluetooth.join("soft"), "1\n").unwrap();
        assert_eq!(radio_blocks(&directory), (true, false));
        std::fs::write(bluetooth.join("hard"), "1\n").unwrap();
        assert_eq!(radio_blocks(&directory), (true, true));
        std::fs::remove_dir_all(&directory).unwrap();
        assert_eq!(radio_blocks(&directory), (false, false));
    }
}
