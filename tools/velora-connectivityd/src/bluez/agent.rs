//! The pairing agent: BlueZ asks it when a device wants a PIN, a passkey confirmed, or a service allowed. Like
//! bluedevil's, it keeps no decisions of its own; everything goes to the person, or to the PIN database.

use super::{model, pins};
use crate::prompts::{Answer, Prompts};
use crate::values::{self, Props};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use zbus::{interface, Connection, ObjectPath};

pub const AGENT_PATH: &str = "/org/velora/bluetooth/agent";
const BUS_NAME: &str = "org.bluez";
const CAPABILITY: &str = "KeyboardDisplay";

#[derive(zbus::DBusError, Debug)]
#[zbus(prefix = "org.bluez.Error")]
pub enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Rejected(String),
    Canceled(String),
}

fn answered(answer: Answer) -> Result<HashMap<String, crate::secret::Secret>, AgentError> {
    match answer {
        Answer::Accepted(values) => Ok(values),
        Answer::Declined => Err(AgentError::Rejected("Declined".to_string())),
        Answer::Gone => Err(AgentError::Canceled("Went away".to_string())),
    }
}

/// The shape of a passkey as it's shown: always six digits.
pub fn passkey_text(passkey: u32) -> String {
    format!("{passkey:06}")
}

pub struct PairingAgent {
    pub connection: Connection,
    pub prompts: Arc<Prompts>,
    /// Questions and notes showing right now, which `Cancel` takes back
    pub open: Mutex<Vec<u64>>,
    /// The device a code is being shown for: the note stays until that device has paired
    pub showing_for: Mutex<Option<String>>,
}

impl PairingAgent {
    async fn describe(&self, device: &ObjectPath<'_>) -> (String, String, String) {
        let reply = self.connection.call_method(Some(BUS_NAME), device.as_str(), Some("org.freedesktop.DBus.Properties"), "GetAll", &(model::IFACE_DEVICE,)).await;
        let props: Props = reply.ok().and_then(|reply| reply.body().deserialize().ok()).unwrap_or_default();
        let address = values::text_or_empty(&props, "Address");
        let name = values::text(&props, "Alias").unwrap_or_else(|| address.clone());
        let kind = model::device_type(&values::text_or_empty(&props, "Icon"), values::number(&props, "Class").unwrap_or(0));
        (name, address, kind.to_string())
    }

    async fn question(&self, kind: &str, device: &ObjectPath<'_>, extra: Value) -> Answer {
        let (name, address, device_type) = self.describe(device).await;
        let mut data = json!({ "deviceName": name, "deviceAddress": address, "deviceType": device_type });
        if let (Value::Object(target), Value::Object(more)) = (&mut data, extra) {
            target.extend(more);
        }
        let (id, receiver) = self.prompts.open(kind, data);
        self.open.lock().expect("no panics while holding this lock").push(id);
        let answer = self.prompts.wait(id, receiver).await;
        self.open.lock().expect("no panics while holding this lock").retain(|open| *open != id);
        answer
    }

    /// A note with no answer: a code to type on the other device. It stays until pairing ends.
    async fn note(&self, kind: &str, device: &ObjectPath<'_>, code: String) {
        let (name, address, device_type) = self.describe(device).await;
        let previous: Vec<u64> = std::mem::take(&mut *self.open.lock().expect("no panics while holding this lock"));
        for id in previous {
            self.prompts.withdraw(id);
        }
        let (id, _receiver) = self.prompts.open(kind, json!({ "deviceName": name, "deviceAddress": address, "deviceType": device_type, "code": code }));
        self.open.lock().expect("no panics while holding this lock").push(id);
        *self.showing_for.lock().expect("no panics while holding this lock") = Some(device.to_string());
    }

    /// Takes a shown code down once its device has paired, since nothing else ends that note.
    pub fn settle(&self, snapshot: &model::BluetoothSnapshot) {
        let showing = self.showing_for.lock().expect("no panics while holding this lock").clone();
        if showing.is_some_and(|device| snapshot.saved.iter().any(|saved| saved.path == device && saved.paired)) {
            self.clear();
        }
    }

    /// Pairing has ended, however it did: nothing should stay on screen.
    pub fn clear(&self) {
        *self.showing_for.lock().expect("no panics while holding this lock") = None;
        let open: Vec<u64> = std::mem::take(&mut *self.open.lock().expect("no panics while holding this lock"));
        for id in open {
            self.prompts.withdraw(id);
        }
    }
}

#[interface(name = "org.bluez.Agent1")]
impl PairingAgent {
    #[zbus(name = "Release")]
    fn release(&self) {
        self.clear();
    }

    #[zbus(name = "RequestPinCode")]
    async fn request_pin_code(&self, device: ObjectPath<'_>) -> Result<String, AgentError> {
        let (name, address, device_type) = self.describe(&device).await;
        if let Some(pin) = pins::known_pin(&device_type, &address, &name) {
            return Ok(pin);
        }
        let values = answered(self.question("bluetooth-pin", &device, json!({})).await)?;
        values.get("pin").map(|pin| pin.expose().to_string()).filter(|pin| !pin.is_empty()).ok_or_else(|| AgentError::Rejected("No PIN".to_string()))
    }

    #[zbus(name = "DisplayPinCode")]
    async fn display_pin_code(&self, device: ObjectPath<'_>, pin: String) {
        self.note("bluetooth-show-code", &device, pin).await;
    }

    #[zbus(name = "RequestPasskey")]
    async fn request_passkey(&self, device: ObjectPath<'_>) -> Result<u32, AgentError> {
        let values = answered(self.question("bluetooth-passkey", &device, json!({})).await)?;
        values.get("passkey").and_then(|passkey| passkey.expose().trim().parse().ok()).ok_or_else(|| AgentError::Rejected("Not a number".to_string()))
    }

    #[zbus(name = "DisplayPasskey")]
    async fn display_passkey(&self, device: ObjectPath<'_>, passkey: u32, entered: u16) {
        // Called again as digits are typed; the note on screen is already right
        if entered == 0 {
            self.note("bluetooth-show-code", &device, passkey_text(passkey)).await;
        }
    }

    #[zbus(name = "RequestConfirmation")]
    async fn request_confirmation(&self, device: ObjectPath<'_>, passkey: u32) -> Result<(), AgentError> {
        answered(self.question("bluetooth-confirm", &device, json!({ "code": passkey_text(passkey) })).await).map(|_| ())
    }

    #[zbus(name = "RequestAuthorization")]
    async fn request_authorization(&self, device: ObjectPath<'_>) -> Result<(), AgentError> {
        answered(self.question("bluetooth-authorize", &device, json!({})).await).map(|_| ())
    }

    #[zbus(name = "AuthorizeService")]
    async fn authorize_service(&self, device: ObjectPath<'_>, uuid: String) -> Result<(), AgentError> {
        let service = model::service_name(&uuid).unwrap_or_default();
        let values = answered(self.question("bluetooth-service", &device, json!({ "service": service })).await)?;
        // "Accept and trust": it won't be asked about this device again
        if values.contains_key("trust") {
            let properties = self.connection.call_method(Some(BUS_NAME), device.as_str(), Some("org.freedesktop.DBus.Properties"), "Set", &(model::IFACE_DEVICE, "Trusted", zbus::Variant::from(true))).await;
            properties.map_err(AgentError::ZBus)?;
        }
        Ok(())
    }

    #[zbus(name = "Cancel")]
    fn cancel(&self) {
        self.clear();
    }
}

/// Registers as the agent BlueZ asks by default, which it must be again after BlueZ restarts.
pub async fn register(connection: &Connection) -> zbus::Result<()> {
    let path = ObjectPath::try_from(AGENT_PATH).expect("a valid path");
    connection.call_method(Some(BUS_NAME), "/org/bluez", Some("org.bluez.AgentManager1"), "RegisterAgent", &(&path, CAPABILITY)).await?;
    connection.call_method(Some(BUS_NAME), "/org/bluez", Some("org.bluez.AgentManager1"), "RequestDefaultAgent", &(&path,)).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn passkeys_keep_their_leading_zeros() {
        assert_eq!(passkey_text(123), "000123");
        assert_eq!(passkey_text(999_999), "999999");
    }
}
