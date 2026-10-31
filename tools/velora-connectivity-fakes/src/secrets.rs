//! A stand-in for the Secret Service (what gnome-keyring and KWallet offer), holding items in memory.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use zbus::{interface, Connection, ObjectPath, OwnedObjectPath, OwnedVariant, Variant};

const BUS_NAME: &str = "org.freedesktop.secrets";
const SERVICE_PATH: &str = "/org/freedesktop/secrets";
const COLLECTION_PATH: &str = "/org/freedesktop/secrets/aliases/default";
const SESSION_PATH: &str = "/org/freedesktop/secrets/session/1";

type Item = (HashMap<String, String>, Vec<u8>);

#[derive(Default)]
struct Shared {
    next: u32,
    items: HashMap<String, Item>,
}

type SharedState = Arc<Mutex<Shared>>;

struct Service {
    shared: SharedState,
}

fn path(text: &str) -> OwnedObjectPath {
    OwnedObjectPath::try_from(text.to_string()).expect("paths here are valid")
}

#[interface(name = "org.freedesktop.Secret.Service")]
impl Service {
    #[zbus(name = "OpenSession")]
    fn open_session(&self, _algorithm: String, _input: OwnedVariant) -> (OwnedVariant, OwnedObjectPath) {
        (Variant::from("").try_into_owned().expect("plain text"), path(SESSION_PATH))
    }

    #[zbus(name = "SearchItems")]
    fn search_items(&self, attributes: HashMap<String, String>) -> (Vec<OwnedObjectPath>, Vec<OwnedObjectPath>) {
        let shared = self.shared.lock().expect("test state");
        let found = shared.items.iter().filter(|(_, (stored, _))| attributes.iter().all(|(key, value)| stored.get(key) == Some(value))).map(|(item, _)| path(item)).collect();
        (found, Vec::new())
    }
}

struct Collection {
    shared: SharedState,
}

#[interface(name = "org.freedesktop.Secret.Collection")]
impl Collection {
    #[zbus(name = "CreateItem")]
    async fn create_item(
        &self,
        properties: HashMap<String, OwnedVariant>,
        secret: (OwnedObjectPath, Vec<u8>, Vec<u8>, String),
        _replace: bool,
        #[zbus(connection)] connection: &Connection,
    ) -> zbus::fdo::Result<(OwnedObjectPath, OwnedObjectPath)> {
        let attributes: HashMap<String, String> = properties
            .get("org.freedesktop.Secret.Item.Attributes")
            .and_then(|value| HashMap::<String, String>::try_from(value.clone()).ok())
            .ok_or_else(|| zbus::fdo::Error::InvalidArgs("no attributes".to_string()))?;
        let (item_path, created) = {
            let mut shared = self.shared.lock().expect("test state");
            let existing = shared.items.iter().find(|(_, (stored, _))| stored == &attributes).map(|(item, _)| item.clone());
            match existing {
                Some(item) => {
                    shared.items.insert(item.clone(), (attributes, secret.2));
                    (item, false)
                }
                None => {
                    shared.next += 1;
                    let item = format!("{COLLECTION_PATH}/{}", shared.next);
                    shared.items.insert(item.clone(), (attributes, secret.2));
                    (item, true)
                }
            }
        };
        if created {
            connection.object_server().at(item_path.as_str(), SecretItem { shared: Arc::clone(&self.shared), path: item_path.clone() }).await.map_err(|error| zbus::fdo::Error::Failed(error.to_string()))?;
        }
        Ok((path(&item_path), path("/")))
    }
}

struct SecretItem {
    shared: SharedState,
    path: String,
}

#[interface(name = "org.freedesktop.Secret.Item")]
impl SecretItem {
    #[zbus(name = "GetSecret")]
    fn get_secret(&self, session: ObjectPath<'_>) -> zbus::fdo::Result<(OwnedObjectPath, Vec<u8>, Vec<u8>, String)> {
        let shared = self.shared.lock().expect("test state");
        let (_, value) = shared.items.get(&self.path).ok_or_else(|| zbus::fdo::Error::UnknownObject(self.path.clone()))?;
        Ok((session.into(), Vec::new(), value.clone(), "text/plain".to_string()))
    }

    #[zbus(name = "Delete")]
    fn delete(&self) -> OwnedObjectPath {
        self.shared.lock().expect("test state").items.remove(&self.path);
        path("/")
    }
}

/// The running stand-in.
pub struct FakeSecrets {
    shared: SharedState,
    _connection: Connection,
}

impl FakeSecrets {
    pub async fn start(bus: &crate::bus::TestBus) -> anyhow::Result<Self> {
        let connection = bus.connect().await?;
        let shared = SharedState::default();
        connection.object_server().at(SERVICE_PATH, Service { shared: Arc::clone(&shared) }).await?;
        connection.object_server().at(COLLECTION_PATH, Collection { shared: Arc::clone(&shared) }).await?;
        connection.request_name(BUS_NAME).await?;
        Ok(Self { shared, _connection: connection })
    }

    /// Puts an entry in place as plasma-nm would have.
    pub async fn seed(&self, user: &str, json: &str) -> anyhow::Result<()> {
        let attributes = HashMap::from([("user".to_string(), user.to_string()), ("server".to_string(), "Network Management".to_string()), ("type".to_string(), "plaintext".to_string())]);
        let item = {
            let mut shared = self.shared.lock().expect("test state");
            shared.next += 1;
            let item = format!("{COLLECTION_PATH}/{}", shared.next);
            shared.items.insert(item.clone(), (attributes, json.as_bytes().to_vec()));
            item
        };
        self._connection.object_server().at(item.as_str(), SecretItem { shared: Arc::clone(&self.shared), path: item.clone() }).await?;
        Ok(())
    }

    pub fn entry(&self, user: &str) -> Option<String> {
        let shared = self.shared.lock().expect("test state");
        shared.items.values().find(|(attributes, _)| attributes.get("user").map(String::as_str) == Some(user)).map(|(_, value)| String::from_utf8_lossy(value).into_owned())
    }

    pub fn count(&self) -> usize {
        self.shared.lock().expect("test state").items.len()
    }
}

struct KWallet {
    entries: HashMap<String, String>,
}

#[interface(name = "org.kde.KWallet")]
impl KWallet {
    #[zbus(name = "open")]
    fn open(&self, _wallet: String, _window: i64, _app: String) -> i32 {
        7
    }

    #[zbus(name = "hasEntry")]
    fn has_entry(&self, _handle: i32, folder: String, key: String, _app: String) -> bool {
        folder == "Network Management" && self.entries.contains_key(&key)
    }

    #[zbus(name = "readPassword")]
    fn read_password(&self, _handle: i32, _folder: String, key: String, _app: String) -> String {
        self.entries.get(&key).cloned().unwrap_or_default()
    }
}

/// A stand-in for KWallet, with these `{uuid};setting` entries in its network folder.
pub struct FakeKWallet {
    _connection: Connection,
}

impl FakeKWallet {
    pub async fn start(bus: &crate::bus::TestBus, entries: &[(&str, &str)]) -> anyhow::Result<Self> {
        let connection = bus.connect().await?;
        let entries = entries.iter().map(|(key, value)| ((*key).to_string(), (*value).to_string())).collect();
        connection.object_server().at("/modules/kwalletd6", KWallet { entries }).await?;
        connection.request_name("org.kde.kwalletd6").await?;
        Ok(Self { _connection: connection })
    }
}
