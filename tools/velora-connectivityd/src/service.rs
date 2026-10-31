//! The requests the shell can make, by name. Parameters are moved out of the message rather than copied,
//! and nothing here logs them, so a password in a request only ever reaches the call it is for.

use crate::bluez::client::BluezClient;
use crate::bluez::obex::{self, ObexShared, ReceivePolicy};
use crate::bluez::state::OnLogin;
use crate::nm::client::{JoinRequest, NmClient};
use crate::prompts::{Answer, Prompts};
use crate::airplane;
use crate::protocol::{ApiError, ErrorCode};
use crate::secret::Secret;
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, Notify};
use zbus::Connection;

pub struct Service {
    pub network: NmClient,
    pub bluetooth: BluezClient,
    pub prompts: Arc<Prompts>,
    pub session: Option<Connection>,
    pub out: mpsc::UnboundedSender<String>,
    pub receive: Arc<ObexShared>,
    pub on_login: Mutex<Option<OnLogin>>,
    pub configured: Notify,
}

#[derive(Deserialize)]
struct Device {
    device: String,
}

#[derive(Deserialize)]
struct DeviceFlag {
    device: String,
    value: bool,
}

#[derive(Deserialize)]
struct DeviceName {
    device: String,
    name: String,
}

#[derive(Deserialize)]
struct Adapter {
    adapter: String,
    #[serde(default)]
    value: bool,
    #[serde(default)]
    seconds: u32,
    #[serde(default)]
    name: String,
}

#[derive(Deserialize)]
struct SendFiles {
    address: String,
    files: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Configure {
    on_login: OnLogin,
    receive_policy: ReceivePolicy,
    receive_folder: String,
}

#[derive(Deserialize)]
struct PromptAnswer {
    id: u64,
    accepted: bool,
    #[serde(default)]
    values: HashMap<String, Secret>,
}

#[derive(Deserialize)]
struct Uuid {
    uuid: String,
}

#[derive(Deserialize)]
struct Enabled {
    enabled: bool,
}

#[derive(Deserialize)]
struct Scan {
    #[serde(default)]
    force: bool,
}

#[derive(Deserialize)]
struct Join {
    ssid: String,
    #[serde(default)]
    bssid: Option<String>,
    #[serde(default)]
    password: Option<Secret>,
    #[serde(default)]
    hidden: bool,
}

#[derive(Deserialize)]
struct Hotspot {
    ssid: String,
    #[serde(default)]
    password: Option<Secret>,
}

#[derive(Deserialize)]
struct SaveProfile {
    uuid: String,
    #[serde(default)]
    revision: Option<String>,
    changes: Map<String, Value>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AddProfile {
    connection_type: String,
    #[serde(default)]
    vpn_service: Option<String>,
    changes: Map<String, Value>,
}

#[derive(Deserialize)]
struct ImportFile {
    path: String,
}

#[derive(Deserialize)]
struct ExportFile {
    uuid: String,
    path: String,
}

#[derive(Deserialize)]
struct ChangePassword {
    uuid: String,
    password: Secret,
}

fn params<T: serde::de::DeserializeOwned>(value: Value) -> Result<T, ApiError> {
    // The parse error names the field at fault, never its value
    serde_json::from_value(value).map_err(|error| ApiError::invalid(format!("bad parameters: {}", field_error(&error))))
}

fn field_error(error: &serde_json::Error) -> String {
    let text = error.to_string();
    if text.starts_with("missing field") {
        text
    } else {
        "wrong type".to_string()
    }
}

impl Service {
    pub async fn call(&self, method: &str, parameters: Value) -> Result<Value, ApiError> {
        match method {
            "ping" => Ok(json!("pong")),
            "prompt.answer" => {
                let PromptAnswer { id, accepted, values } = params(parameters)?;
                let answer = if accepted { Answer::Accepted(values) } else { Answer::Declined };
                Ok(json!({ "stillOpen": self.prompts.answer(id, answer) }))
            }
            "network.setWifiEnabled" => {
                let Enabled { enabled } = params(parameters)?;
                self.network.set_wifi_enabled(enabled).await?;
                Ok(Value::Null)
            }
            "network.scan" => {
                let Scan { force } = params(parameters)?;
                Ok(json!({ "requested": self.network.scan(force).await? }))
            }
            "network.activate" => {
                let Uuid { uuid } = params(parameters)?;
                Ok(json!({ "active": self.network.activate(&uuid).await? }))
            }
            "network.deactivate" => {
                let Uuid { uuid } = params(parameters)?;
                self.network.deactivate(&uuid).await?;
                Ok(Value::Null)
            }
            "network.forget" => {
                let Uuid { uuid } = params(parameters)?;
                self.network.forget(&uuid).await?;
                Ok(Value::Null)
            }
            "network.join" => {
                let Join { ssid, bssid, password, hidden } = params(parameters)?;
                Ok(json!({ "active": self.network.join(JoinRequest { ssid, bssid, password, hidden }).await? }))
            }
            "network.changePassword" => {
                let ChangePassword { uuid, password } = params(parameters)?;
                Ok(json!({ "active": self.network.change_password(&uuid, &password).await? }))
            }
            "network.secrets" => {
                let Uuid { uuid } = params(parameters)?;
                Ok(json!({ "secrets": self.network.saved_secrets(&uuid).await? }))
            }
            "network.qrCode" => {
                let Uuid { uuid } = params(parameters)?;
                Ok(json!({ "image": self.network.wifi_qr_code(&uuid).await? }))
            }
            "network.copyPassword" => {
                let Uuid { uuid } = params(parameters)?;
                self.network.copy_wifi_password(&uuid).await?;
                Ok(Value::Null)
            }
            "network.profile" => {
                let Uuid { uuid } = params(parameters)?;
                Ok(serde_json::to_value(self.network.profile_form(&uuid).await?).expect("plain values"))
            }
            "network.saveProfile" => {
                let SaveProfile { uuid, revision, changes } = params(parameters)?;
                self.network.save_profile(&uuid, revision.as_deref(), &changes).await?;
                Ok(Value::Null)
            }
            "network.addProfile" => {
                let AddProfile { connection_type, vpn_service, changes } = params(parameters)?;
                Ok(json!({ "uuid": self.network.add_profile(&connection_type, vpn_service.as_deref(), &changes).await? }))
            }
            "network.importVpn" => {
                let ImportFile { path } = params(parameters)?;
                Ok(json!({ "uuid": self.network.import_vpn(&path).await? }))
            }
            "network.exportVpn" => {
                let ExportFile { uuid, path } = params(parameters)?;
                self.network.export_vpn(&uuid, &path).await?;
                Ok(Value::Null)
            }
            "network.startHotspot" => {
                let Hotspot { ssid, password } = params(parameters)?;
                Ok(json!({ "active": self.network.start_hotspot(&ssid, password.as_ref()).await? }))
            }
            "network.stopHotspot" => {
                self.network.stop_hotspot().await?;
                Ok(Value::Null)
            }
            "network.setAirplaneMode" => {
                let Enabled { enabled } = params(parameters)?;
                airplane::set(&self.network, &self.bluetooth, enabled).await?;
                Ok(Value::Null)
            }
            "bluetooth.setEnabled" => {
                let Enabled { enabled } = params(parameters)?;
                self.bluetooth.set_enabled(enabled).await?;
                Ok(Value::Null)
            }
            "bluetooth.setPowered" => {
                let Adapter { adapter, value, .. } = params(parameters)?;
                self.bluetooth.set_powered(&adapter, value).await?;
                Ok(Value::Null)
            }
            "bluetooth.setDiscoverable" => {
                let Adapter { adapter, value, .. } = params(parameters)?;
                self.bluetooth.set_discoverable(&adapter, value).await?;
                Ok(Value::Null)
            }
            "bluetooth.setDiscoverableTimeout" => {
                let Adapter { adapter, seconds, .. } = params(parameters)?;
                self.bluetooth.set_discoverable_timeout(&adapter, seconds).await?;
                Ok(Value::Null)
            }
            "bluetooth.setAdapterName" => {
                let Adapter { adapter, name, .. } = params(parameters)?;
                self.bluetooth.set_adapter_name(&adapter, &name).await?;
                Ok(Value::Null)
            }
            "bluetooth.setDiscovering" => {
                let Enabled { enabled } = params(parameters)?;
                self.bluetooth.set_discovering(enabled).await?;
                Ok(Value::Null)
            }
            "bluetooth.pair" => {
                let Device { device } = params(parameters)?;
                self.bluetooth.pair_and_connect(&device).await?;
                Ok(Value::Null)
            }
            "bluetooth.cancelPairing" => {
                let Device { device } = params(parameters)?;
                self.bluetooth.cancel_pairing(&device).await?;
                Ok(Value::Null)
            }
            "bluetooth.connect" => {
                let Device { device } = params(parameters)?;
                self.bluetooth.connect(&device).await?;
                Ok(Value::Null)
            }
            "bluetooth.disconnect" => {
                let Device { device } = params(parameters)?;
                self.bluetooth.disconnect(&device).await?;
                Ok(Value::Null)
            }
            "bluetooth.setTrusted" => {
                let DeviceFlag { device, value } = params(parameters)?;
                self.bluetooth.set_trusted(&device, value).await?;
                Ok(Value::Null)
            }
            "bluetooth.setBlocked" => {
                let DeviceFlag { device, value } = params(parameters)?;
                self.bluetooth.set_blocked(&device, value).await?;
                Ok(Value::Null)
            }
            "bluetooth.rename" => {
                let DeviceName { device, name } = params(parameters)?;
                self.bluetooth.rename(&device, &name).await?;
                Ok(Value::Null)
            }
            "bluetooth.forget" => {
                let Device { device } = params(parameters)?;
                self.bluetooth.forget(&device).await?;
                Ok(Value::Null)
            }
            "bluetooth.sendFiles" => {
                let SendFiles { address, files } = params(parameters)?;
                let session = self.session.as_ref().ok_or_else(|| ApiError::new(ErrorCode::Unavailable, "File transfer needs a session bus"))?;
                obex::send_files(session, &address, &files, &self.out).await?;
                Ok(Value::Null)
            }
            "bluetooth.configure" => {
                let Configure { on_login, receive_policy, receive_folder } = params(parameters)?;
                *self.receive.settings.lock().expect("no panics while holding this lock") = obex::ReceiveSettings { policy: receive_policy, folder: PathBuf::from(receive_folder) };
                *self.on_login.lock().expect("no panics while holding this lock") = Some(on_login);
                self.configured.notify_one();
                Ok(Value::Null)
            }
            other => Err(ApiError::new(ErrorCode::UnknownMethod, format!("unknown method: {other}"))),
        }
    }
}
