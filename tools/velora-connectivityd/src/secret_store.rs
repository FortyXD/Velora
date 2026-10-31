//! Secrets of profiles marked "only for me", where plasma-nm keeps them: QtKeychain's service
//! `Network Management`, one entry per profile and setting named `{uuid};setting`, with the secrets as JSON.
//! That lands in the Secret Service (this system's keyring) or, for reading what Plasma left, KWallet.

use serde_json::{Map, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Duration;
use zbus::{Connection, OwnedObjectPath, OwnedVariant, Variant};
use zeroize::Zeroizing;

const SERVICE: &str = "Network Management";
const SECRETS_BUS: &str = "org.freedesktop.secrets";
const SECRETS_PATH: &str = "/org/freedesktop/secrets";
const IFACE_SERVICE: &str = "org.freedesktop.Secret.Service";
const IFACE_ITEM: &str = "org.freedesktop.Secret.Item";
const IFACE_COLLECTION: &str = "org.freedesktop.Secret.Collection";
const DEFAULT_COLLECTION: &str = "/org/freedesktop/secrets/aliases/default";
const KWALLET_BUS: &str = "org.kde.kwalletd6";
const KWALLET_PATH: &str = "/modules/kwalletd6";
const KWALLET_IFACE: &str = "org.kde.KWallet";
/// A keyring that doesn't answer shouldn't hold up connecting; the person gets asked instead.
const PATIENCE: Duration = Duration::from_secs(5);

pub fn entry_key(uuid: &str, setting: &str) -> String {
    format!("{{{uuid}}};{setting}")
}

/// `(session, parameters, value, content type)`, how the Secret Service passes a secret.
type SecretStruct = (OwnedObjectPath, Vec<u8>, Vec<u8>, String);

pub struct SecretStore {
    session: Option<Connection>,
    /// Where KWallet keeps its files: reading goes there only if one exists, since asking would create it.
    wallet_directory: PathBuf,
}

fn attributes<'a>(key: &'a str, kind: &'a str) -> HashMap<&'static str, &'a str> {
    HashMap::from([("user", key), ("server", SERVICE), ("type", kind)])
}

fn parse_entry(text: &str) -> HashMap<String, Zeroizing<String>> {
    let Ok(Value::Object(map)) = serde_json::from_str::<Value>(text) else { return HashMap::new() };
    map.into_iter().filter_map(|(key, value)| value.as_str().map(|value| (key, Zeroizing::new(value.to_string())))).collect()
}

impl SecretStore {
    pub fn new(session: Option<Connection>) -> Self {
        let data = std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| format!("{}/.local/share", std::env::var("HOME").unwrap_or_default()));
        Self { session, wallet_directory: PathBuf::from(data).join("kwalletd") }
    }

    async fn open_session(connection: &Connection) -> zbus::Result<OwnedObjectPath> {
        let reply = connection.call_method(Some(SECRETS_BUS), SECRETS_PATH, Some(IFACE_SERVICE), "OpenSession", &("plain", Variant::from(""))).await?;
        let (_output, session): (OwnedVariant, OwnedObjectPath) = reply.body().deserialize()?;
        Ok(session)
    }

    async fn read_secret_service(connection: &Connection, key: &str, kind: &str) -> zbus::Result<Option<Zeroizing<String>>> {
        let session = Self::open_session(connection).await?;
        let reply = connection.call_method(Some(SECRETS_BUS), SECRETS_PATH, Some(IFACE_SERVICE), "SearchItems", &(attributes(key, kind),)).await?;
        let (unlocked, _locked): (Vec<OwnedObjectPath>, Vec<OwnedObjectPath>) = reply.body().deserialize()?;
        let Some(item) = unlocked.first() else { return Ok(None) };
        let reply = connection.call_method(Some(SECRETS_BUS), item.as_str(), Some(IFACE_ITEM), "GetSecret", &(&session,)).await?;
        let (_session, _parameters, value, _content_type): SecretStruct = reply.body().deserialize()?;
        let value = Zeroizing::new(value);
        Ok(Some(Zeroizing::new(String::from_utf8_lossy(&value).into_owned())))
    }

    async fn read_kwallet(&self, key: &str) -> zbus::Result<Option<Zeroizing<String>>> {
        let Some(connection) = &self.session else { return Ok(None) };
        let wallet_exists = std::fs::read_dir(&self.wallet_directory).is_ok_and(|mut entries| entries.any(|entry| entry.is_ok_and(|entry| entry.path().extension().is_some_and(|extension| extension == "kwl"))));
        if !wallet_exists {
            return Ok(None);
        }
        let reply = connection.call_method(Some(KWALLET_BUS), KWALLET_PATH, Some(KWALLET_IFACE), "open", &("kdewallet", 0i64, "velora")).await?;
        let handle: i32 = reply.body().deserialize()?;
        if handle < 0 {
            return Ok(None);
        }
        let reply = connection.call_method(Some(KWALLET_BUS), KWALLET_PATH, Some(KWALLET_IFACE), "hasEntry", &(handle, SERVICE, key, "velora")).await?;
        let found: bool = reply.body().deserialize()?;
        if !found {
            return Ok(None);
        }
        let reply = connection.call_method(Some(KWALLET_BUS), KWALLET_PATH, Some(KWALLET_IFACE), "readPassword", &(handle, SERVICE, key, "velora")).await?;
        let text: String = reply.body().deserialize()?;
        Ok(Some(Zeroizing::new(text)))
    }

    /// What's stored for one setting of a profile; nothing if it isn't, or nothing can be asked.
    pub async fn read(&self, uuid: &str, setting: &str) -> HashMap<String, Zeroizing<String>> {
        tokio::time::timeout(PATIENCE, self.read_entry(uuid, setting)).await.unwrap_or_default()
    }

    async fn read_entry(&self, uuid: &str, setting: &str) -> HashMap<String, Zeroizing<String>> {
        let key = entry_key(uuid, setting);
        if let Some(connection) = &self.session {
            for kind in ["plaintext", "base64"] {
                if let Ok(Some(text)) = Self::read_secret_service(connection, &key, kind).await {
                    if kind == "plaintext" {
                        return parse_entry(&text);
                    }
                }
            }
        }
        match self.read_kwallet(&key).await {
            Ok(Some(text)) => parse_entry(&text),
            _ => HashMap::new(),
        }
    }

    pub async fn write(&self, uuid: &str, setting: &str, secrets: &Map<String, Value>) -> zbus::Result<()> {
        let Some(connection) = &self.session else { return Ok(()) };
        let key = entry_key(uuid, setting);
        let session = Self::open_session(connection).await?;
        let text = Zeroizing::new(serde_json::to_string(secrets).expect("plain text values"));
        let mut properties: HashMap<&str, Variant> = HashMap::new();
        properties.insert("org.freedesktop.Secret.Item.Label", Variant::from(format!("{SERVICE}: {key}")));
        properties.insert("org.freedesktop.Secret.Item.Attributes", Variant::from(attributes(&key, "plaintext")));
        let secret: SecretStruct = (session, Vec::new(), text.as_bytes().to_vec(), "text/plain".to_string());
        connection.call_method(Some(SECRETS_BUS), DEFAULT_COLLECTION, Some(IFACE_COLLECTION), "CreateItem", &(properties, secret, true)).await?;
        Ok(())
    }

    pub async fn delete(&self, uuid: &str, setting: &str) -> zbus::Result<()> {
        let Some(connection) = &self.session else { return Ok(()) };
        let key = entry_key(uuid, setting);
        let reply = connection.call_method(Some(SECRETS_BUS), SECRETS_PATH, Some(IFACE_SERVICE), "SearchItems", &(attributes(&key, "plaintext"),)).await?;
        let (unlocked, locked): (Vec<OwnedObjectPath>, Vec<OwnedObjectPath>) = reply.body().deserialize()?;
        for item in unlocked.iter().chain(&locked) {
            connection.call_method(Some(SECRETS_BUS), item.as_str(), Some(IFACE_ITEM), "Delete", &()).await?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entries_are_named_as_plasma_names_them() {
        assert_eq!(entry_key("abc", "802-11-wireless-security"), "{abc};802-11-wireless-security");
    }

    #[test]
    fn entries_are_json_and_anything_else_is_empty() {
        let parsed = parse_entry(r#"{"psk":"hunter2","number":5}"#);
        assert_eq!(parsed["psk"].as_str(), "hunter2");
        assert_eq!(parsed.len(), 1);
        assert!(parse_entry("not json").is_empty());
        assert!(parse_entry("[1]").is_empty());
    }

    #[tokio::test]
    async fn without_a_session_bus_nothing_is_stored_and_nothing_fails() {
        let store = SecretStore::new(None);
        assert!(store.read("u", "vpn").await.is_empty());
        store.write("u", "vpn", &Map::new()).await.unwrap();
        store.delete("u", "vpn").await.unwrap();
    }
}
