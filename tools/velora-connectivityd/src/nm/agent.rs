//! The secret agent: NetworkManager asks it for passwords it doesn't hold, and it answers from the keyring or
//! by asking the person. It decides what to do in the same order as plasma-nm, except that a wrong password
//! leaves the profile in place.

use super::model::{self, Security};
use crate::prompts::{Answer, Prompts};
use crate::secret_store::SecretStore;
use crate::values::{self, Props, Settings};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use zbus::{interface, ObjectPath, Variant};

pub const AGENT_PATH: &str = "/org/freedesktop/NetworkManager/SecretAgent";
pub const AGENT_IDENTIFIER: &str = "org.velora.shell";
const CAPABILITY_VPN_HINTS: u32 = 0x1;

const FLAG_ALLOW_INTERACTION: u32 = 0x1;
const FLAG_REQUEST_NEW: u32 = 0x2;
const FLAG_USER_REQUESTED: u32 = 0x4;

const SECRET_AGENT_OWNED: i64 = 0x1;
const SECRET_NOT_REQUIRED: i64 = 0x4;

const VPN_MESSAGE_HINT: &str = "x-vpn-message:";

#[derive(zbus::DBusError, Debug)]
#[zbus(prefix = "org.freedesktop.NetworkManager.SecretAgent")]
pub enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    UserCanceled(String),
    AgentCanceled(String),
    NoSecrets(String),
}

/// What to do about a request for secrets.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    ReplyStored,
    Prompt,
    NoSecrets,
}

pub fn decide(flags: u32, is_vpn: bool, still_needed: bool, has_stored: bool) -> Decision {
    let request_new = flags & FLAG_REQUEST_NEW != 0;
    let allow = flags & FLAG_ALLOW_INTERACTION != 0;
    let user_requested = flags & FLAG_USER_REQUESTED != 0;
    if !request_new && has_stored && !still_needed {
        return Decision::ReplyStored;
    }
    if request_new || (allow && still_needed) || (allow && user_requested) {
        return Decision::Prompt;
    }
    if is_vpn && user_requested {
        return Decision::ReplyStored;
    }
    if !still_needed {
        return Decision::ReplyStored;
    }
    Decision::NoSecrets
}

fn flags_of(section: &Props, key: &str) -> i64 {
    values::number(section, &format!("{key}-flags")).unwrap_or(0)
}

fn wanted(section: &Props, key: &str, stored: &HashMap<String, Value>, request_new: bool) -> Option<String> {
    if flags_of(section, key) & SECRET_NOT_REQUIRED != 0 {
        return None;
    }
    let present = stored.contains_key(key) || values::text(section, key).is_some_and(|value| !value.is_empty());
    (request_new || !present).then(|| key.to_string())
}

/// The VPN secrets to ask for: what the plugin named in its hints, else whatever its flags say it keeps.
fn vpn_needed(section: &Props, hints: &[String], stored: &HashMap<String, Value>, request_new: bool) -> Vec<String> {
    let named: Vec<String> = hints.iter().filter(|hint| !hint.starts_with(VPN_MESSAGE_HINT)).cloned().collect();
    if !named.is_empty() {
        return named;
    }
    let data = section.get("data").map(|value| values::to_json(value)).unwrap_or(Value::Null);
    let Some(data) = data.as_object() else { return Vec::new() };
    let saved = section.get("secrets").map(|value| values::to_json(value)).unwrap_or(Value::Null);
    data.iter()
        .filter_map(|(key, value)| {
            let name = key.strip_suffix("-flags")?;
            let flags: i64 = value.as_str()?.parse().ok()?;
            let present = stored.contains_key(name) || saved.get(name).is_some();
            // A code the server asks for arrives as a hint of its own
            (flags & SECRET_NOT_REQUIRED == 0 && name != "challenge-response" && (request_new || !present)).then(|| name.to_string())
        })
        .collect()
}

/// Which secrets of a setting are missing, in the terms of that setting's keys.
pub fn needed_secrets(settings: &Settings, setting: &str, hints: &[String], stored: &HashMap<String, Value>, request_new: bool) -> Vec<String> {
    let Some(section) = settings.get(setting) else { return Vec::new() };
    let one = |key: &str| wanted(section, key, stored, request_new).into_iter().collect::<Vec<_>>();
    match setting {
        "802-11-wireless-security" => match model::profile_security(settings) {
            Security::WpaPsk | Security::Sae => one("psk"),
            Security::Wep => one("wep-key0"),
            Security::Leap => one("leap-password"),
            _ => Vec::new(),
        },
        "802-1x" => {
            if values::strings(section, "eap").iter().any(|method| method == "tls") {
                one("private-key-password")
            } else {
                one("password")
            }
        }
        "gsm" | "cdma" | "pppoe" | "adsl" => one("password"),
        "wireguard" => one("private-key"),
        "vpn" => vpn_needed(section, hints, stored, request_new),
        _ => Vec::new(),
    }
}

/// The reply a setting's secrets go out as: a VPN's sit in a dictionary of their own.
pub fn secrets_reply(setting: &str, secrets: &HashMap<String, String>) -> Settings {
    let mut section = Props::new();
    if setting == "vpn" {
        section.insert("secrets".to_string(), Variant::from(secrets.clone()).try_into_owned().expect("text only"));
    } else {
        for (key, value) in secrets {
            section.insert(key.clone(), Variant::from(value.clone()).try_into_owned().expect("text only"));
        }
    }
    HashMap::from([(setting.to_string(), section)])
}

/// A setting's secrets, for profiles that keep them with this agent ("only for me").
pub fn agent_owned_secrets(settings: &Settings) -> Vec<(String, Map<String, Value>)> {
    let mut found = Vec::new();
    for (name, section) in settings {
        let mut secrets = Map::new();
        if name == "vpn" {
            let data = section.get("data").map(|value| values::to_json(value)).unwrap_or(Value::Null);
            if let Some(Value::Object(saved)) = section.get("secrets").map(|value| values::to_json(value)) {
                for (key, value) in saved {
                    let flags = data.get(format!("{key}-flags")).and_then(Value::as_str).and_then(|flags| flags.parse::<i64>().ok()).unwrap_or(0);
                    if flags & SECRET_AGENT_OWNED != 0 {
                        secrets.insert(key, value);
                    }
                }
            }
        } else {
            for (key, value) in section {
                if flags_of(section, key) & SECRET_AGENT_OWNED == 0 {
                    continue;
                }
                if let Variant::Str(text) = &**value {
                    secrets.insert(key.clone(), json!(text.to_string()));
                }
            }
        }
        if !secrets.is_empty() {
            found.push((name.clone(), secrets));
        }
    }
    found
}

fn describe(settings: &Settings) -> (String, String, String) {
    let connection = settings.get("connection");
    let id = connection.map(|section| values::text_or_empty(section, "id")).unwrap_or_default();
    let uuid = connection.map(|section| values::text_or_empty(section, "uuid")).unwrap_or_default();
    let kind = connection.map(|section| values::text_or_empty(section, "type")).unwrap_or_default();
    (id, uuid, kind)
}

fn call_id(path: &str, setting: &str) -> String {
    format!("{path}/{setting}")
}

pub struct SecretAgent {
    pub prompts: Arc<Prompts>,
    pub store: Arc<SecretStore>,
    /// Open questions by connection and setting, for `CancelGetSecrets`
    pub open: Mutex<HashMap<String, u64>>,
}

#[interface(name = "org.freedesktop.NetworkManager.SecretAgent")]
impl SecretAgent {
    #[zbus(name = "GetSecrets")]
    async fn get_secrets(
        &self,
        connection: Settings,
        connection_path: ObjectPath<'_>,
        setting_name: String,
        hints: Vec<String>,
        flags: u32,
    ) -> Result<Settings, AgentError> {
        let (id, uuid, kind) = describe(&connection);
        let is_vpn = setting_name == "vpn";
        let request_new = flags & FLAG_REQUEST_NEW != 0;
        let mut stored: HashMap<String, Value> = HashMap::new();
        if !request_new {
            for (key, value) in self.store.read(&uuid, &setting_name).await {
                stored.insert(key, json!(value.as_str()));
            }
        }
        let needed = needed_secrets(&connection, &setting_name, &hints, &stored, request_new);
        let reply_with = |extra: HashMap<String, String>| {
            let mut all: HashMap<String, String> = stored.iter().filter_map(|(key, value)| value.as_str().map(|value| (key.clone(), value.to_string()))).collect();
            all.extend(extra);
            secrets_reply(&setting_name, &all)
        };
        match decide(flags, is_vpn, !needed.is_empty(), !stored.is_empty()) {
            Decision::ReplyStored => Ok(reply_with(HashMap::new())),
            Decision::NoSecrets => Err(AgentError::NoSecrets("No secrets are available and asking isn't allowed".to_string())),
            Decision::Prompt => {
                let message = hints.iter().find_map(|hint| hint.strip_prefix(VPN_MESSAGE_HINT)).unwrap_or_default();
                let fields = if needed.is_empty() { vec!["password".to_string()] } else { needed };
                let question = json!({
                    "connectionName": id,
                    "connectionType": kind,
                    "setting": setting_name,
                    "fields": fields,
                    "message": message,
                    "retry": request_new,
                });
                let (prompt, receiver) = self.prompts.open("secrets", question);
                let key = call_id(connection_path.as_str(), &setting_name);
                self.open.lock().expect("no panics while holding this lock").insert(key.clone(), prompt);
                let answer = self.prompts.wait(prompt, receiver).await;
                self.open.lock().expect("no panics while holding this lock").remove(&key);
                match answer {
                    Answer::Accepted(values) => Ok(reply_with(values.into_iter().map(|(key, value)| (key, value.expose().to_string())).collect())),
                    Answer::Declined => Err(AgentError::UserCanceled("The password request was canceled".to_string())),
                    Answer::Gone => Err(AgentError::AgentCanceled("The password request went away".to_string())),
                }
            }
        }
    }

    #[zbus(name = "CancelGetSecrets")]
    async fn cancel_get_secrets(&self, connection_path: ObjectPath<'_>, setting_name: String) {
        let prompt = self.open.lock().expect("no panics while holding this lock").remove(&call_id(connection_path.as_str(), &setting_name));
        if let Some(prompt) = prompt {
            self.prompts.withdraw(prompt);
        }
    }

    #[zbus(name = "SaveSecrets")]
    async fn save_secrets(&self, connection: Settings, _connection_path: ObjectPath<'_>) {
        let (_, uuid, _) = describe(&connection);
        for (setting, secrets) in agent_owned_secrets(&connection) {
            // A keyring that's unavailable leaves it to be asked for next time
            let _ = self.store.write(&uuid, &setting, &secrets).await;
        }
    }

    #[zbus(name = "DeleteSecrets")]
    async fn delete_secrets(&self, connection: Settings, _connection_path: ObjectPath<'_>) {
        let (_, uuid, _) = describe(&connection);
        for setting in connection.keys() {
            let _ = self.store.delete(&uuid, setting).await;
        }
    }
}

/// Registers the agent with NetworkManager, which it must be again after the service restarts.
pub async fn register(connection: &zbus::Connection) -> zbus::Result<()> {
    connection
        .call_method(
            Some(super::client::BUS_NAME),
            "/org/freedesktop/NetworkManager/AgentManager",
            Some("org.freedesktop.NetworkManager.AgentManager"),
            "RegisterWithCapabilities",
            &(AGENT_IDENTIFIER, CAPABILITY_VPN_HINTS),
        )
        .await?;
    Ok(())
}


#[cfg(test)]
mod tests {
    use super::*;
    use crate::values::build::{owned, props};

    fn wifi(key_mgmt: &str, extra: Props) -> Settings {
        let mut section = props([("key-mgmt", owned(key_mgmt))]);
        section.extend(extra);
        HashMap::from([
            ("connection".to_string(), props([("id", owned("Home")), ("uuid", owned("u")), ("type", owned("802-11-wireless"))])),
            ("802-11-wireless-security".to_string(), section),
        ])
    }

    const ASK: u32 = FLAG_ALLOW_INTERACTION;
    const NEW: u32 = FLAG_REQUEST_NEW | FLAG_ALLOW_INTERACTION;

    #[test]
    fn the_order_of_decisions() {
        // Stored and complete: no need to bother anyone
        assert_eq!(decide(ASK, false, false, true), Decision::ReplyStored);
        // Missing, asking allowed
        assert_eq!(decide(ASK, false, true, false), Decision::Prompt);
        // Missing, asking not allowed
        assert_eq!(decide(0, false, true, false), Decision::NoSecrets);
        // The stored one was refused
        assert_eq!(decide(NEW, false, false, true), Decision::Prompt);
        assert_eq!(decide(FLAG_REQUEST_NEW, false, false, true), Decision::Prompt);
        // Asked by the person, not the system
        assert_eq!(decide(ASK | FLAG_USER_REQUESTED, false, false, false), Decision::Prompt);
        assert_eq!(decide(FLAG_USER_REQUESTED, true, true, false), Decision::ReplyStored);
        // Nothing needed, nothing stored
        assert_eq!(decide(0, false, false, false), Decision::ReplyStored);
        // A VPN needing a code asks, even with its password stored
        assert_eq!(decide(ASK, true, true, true), Decision::Prompt);
        assert_eq!(decide(ASK, true, false, true), Decision::ReplyStored);
    }

    #[test]
    fn the_password_a_network_needs() {
        let none = HashMap::new();
        assert_eq!(needed_secrets(&wifi("wpa-psk", Props::new()), "802-11-wireless-security", &[], &none, false), ["psk"]);
        assert_eq!(needed_secrets(&wifi("sae", Props::new()), "802-11-wireless-security", &[], &none, false), ["psk"]);
        assert_eq!(needed_secrets(&wifi("none", Props::new()), "802-11-wireless-security", &[], &none, false), ["wep-key0"]);
        assert!(needed_secrets(&wifi("owe", Props::new()), "802-11-wireless-security", &[], &none, false).is_empty());
        let leap = wifi("ieee8021x", props([("auth-alg", owned("leap"))]));
        assert_eq!(needed_secrets(&leap, "802-11-wireless-security", &[], &none, false), ["leap-password"]);
    }

    #[test]
    fn a_password_at_hand_isnt_needed_unless_a_new_one_is_wanted() {
        let settings = wifi("wpa-psk", props([("psk", owned("x"))]));
        assert!(needed_secrets(&settings, "802-11-wireless-security", &[], &HashMap::new(), false).is_empty());
        assert_eq!(needed_secrets(&settings, "802-11-wireless-security", &[], &HashMap::new(), true), ["psk"]);
        let settings = wifi("wpa-psk", Props::new());
        let stored = HashMap::from([("psk".to_string(), json!("y"))]);
        assert!(needed_secrets(&settings, "802-11-wireless-security", &[], &stored, false).is_empty());
    }

    #[test]
    fn a_secret_marked_not_required_is_never_needed() {
        let settings = wifi("wpa-psk", props([("psk-flags", owned(4u32))]));
        assert!(needed_secrets(&settings, "802-11-wireless-security", &[], &HashMap::new(), true).is_empty());
    }

    #[test]
    fn enterprise_secrets_depend_on_the_method() {
        let mut settings = wifi("wpa-eap", Props::new());
        settings.insert("802-1x".to_string(), props([("eap", owned(vec!["peap"]))]));
        assert_eq!(needed_secrets(&settings, "802-1x", &[], &HashMap::new(), false), ["password"]);
        settings.insert("802-1x".to_string(), props([("eap", owned(vec!["tls"]))]));
        assert_eq!(needed_secrets(&settings, "802-1x", &[], &HashMap::new(), false), ["private-key-password"]);
    }

    fn vpn(data: &[(&str, &str)], secrets: &[(&str, &str)]) -> Settings {
        let to_map = |entries: &[(&str, &str)]| entries.iter().map(|(key, value)| (key.to_string(), value.to_string())).collect::<HashMap<String, String>>();
        let mut section = props([("data", owned(to_map(data)))]);
        if !secrets.is_empty() {
            section.insert("secrets".to_string(), owned(to_map(secrets)));
        }
        HashMap::from([("vpn".to_string(), section)])
    }

    #[test]
    fn a_vpn_asks_for_what_its_plugin_names() {
        let settings = vpn(&[("password-flags", "0")], &[("password", "x")]);
        assert!(needed_secrets(&settings, "vpn", &[], &HashMap::new(), false).is_empty());
        let hints = vec!["x-vpn-message:Enter your code".to_string(), "challenge-response".to_string()];
        assert_eq!(needed_secrets(&settings, "vpn", &hints, &HashMap::new(), false), ["challenge-response"]);
    }

    #[test]
    fn a_vpn_without_hints_goes_by_its_flags() {
        let settings = vpn(&[("password-flags", "1"), ("cert-pass-flags", "4"), ("challenge-response-flags", "2"), ("remote", "x")], &[]);
        assert_eq!(needed_secrets(&settings, "vpn", &[], &HashMap::new(), false), ["password"]);
        let stored = HashMap::from([("password".to_string(), json!("y"))]);
        assert!(needed_secrets(&settings, "vpn", &[], &stored, false).is_empty());
    }

    #[test]
    fn replies_keep_a_vpns_secrets_in_their_dictionary() {
        let secrets = HashMap::from([("password".to_string(), "x".to_string())]);
        let wifi_reply = secrets_reply("802-11-wireless-security", &HashMap::from([("psk".to_string(), "x".to_string())]));
        assert_eq!(values::text(&wifi_reply["802-11-wireless-security"], "psk").as_deref(), Some("x"));
        let vpn_reply = secrets_reply("vpn", &secrets);
        assert_eq!(values::to_json(&vpn_reply["vpn"]["secrets"]), json!({ "password": "x" }));
    }

    #[test]
    fn only_secrets_marked_for_the_agent_are_kept_by_it() {
        let settings = wifi("wpa-psk", props([("psk", owned("mine")), ("psk-flags", owned(1u32))]));
        let found = agent_owned_secrets(&settings);
        assert_eq!(found, vec![("802-11-wireless-security".to_string(), Map::from_iter([("psk".to_string(), json!("mine"))]))]);
        let settings = wifi("wpa-psk", props([("psk", owned("system")), ("psk-flags", owned(0u32))]));
        assert!(agent_owned_secrets(&settings).is_empty());
        let settings = vpn(&[("password-flags", "1"), ("cert-pass-flags", "0")], &[("password", "mine"), ("cert-pass", "system")]);
        let found = agent_owned_secrets(&settings);
        assert_eq!(found, vec![("vpn".to_string(), Map::from_iter([("password".to_string(), json!("mine"))]))]);
    }
}
