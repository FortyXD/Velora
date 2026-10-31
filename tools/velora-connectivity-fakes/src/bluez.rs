//! A stand-in for BlueZ with what the daemon relies on: pairing that goes through the registered agent the way
//! each kind of device does, and the D-Bus errors BlueZ gives. Also obexd for files, and logind for sleep.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use zbus::object_server::SignalEmitter;
use zbus::{fdo, interface, Connection, ObjectPath, OwnedObjectPath, OwnedVariant, Variant};

pub const BUS_NAME: &str = "org.bluez";
const ADAPTER_PATH: &str = "/org/bluez/hci0";

fn path(text: &str) -> OwnedObjectPath {
    OwnedObjectPath::try_from(text.to_string()).expect("paths here are valid")
}

/// How a device goes about pairing.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Pairing {
    /// Nothing to enter, as most headphones.
    JustWorks,
    /// Asks the agent for a PIN and accepts only this one.
    Pin(String),
    /// Asks the agent for a number and accepts only this one.
    Passkey(u32),
    /// Asks the agent to confirm this number matches.
    Confirm(u32),
    /// Asks the agent to show this PIN to type on the device.
    ShowPin(String),
    /// Asks the agent to show this number to type on the device.
    ShowPasskey(u32),
    /// Asks the agent whether to allow it.
    Authorize,
    /// BlueZ fails it with this error name, after the given asking.
    Fails(&'static str),
}

#[derive(zbus::DBusError, Debug)]
#[zbus(prefix = "org.bluez.Error")]
pub enum BluezError {
    #[zbus(error)]
    ZBus(zbus::Error),
    AuthenticationFailed(String),
    AuthenticationCanceled(String),
    AuthenticationRejected(String),
    AuthenticationTimeout(String),
    ConnectionAttemptFailed(String),
    AlreadyExists(String),
    InProgress(String),
    NotReady(String),
    Failed(String),
    NotAvailable(String),
    DoesNotExist(String),
}

fn error_named(name: &str) -> BluezError {
    let message = "stand-in failure".to_string();
    match name {
        "AuthenticationFailed" => BluezError::AuthenticationFailed(message),
        "AuthenticationCanceled" => BluezError::AuthenticationCanceled(message),
        "AuthenticationRejected" => BluezError::AuthenticationRejected(message),
        "AuthenticationTimeout" => BluezError::AuthenticationTimeout(message),
        "ConnectionAttemptFailed" => BluezError::ConnectionAttemptFailed(message),
        "InProgress" => BluezError::InProgress(message),
        "NotAvailable" => BluezError::NotAvailable(message),
        _ => BluezError::Failed(message),
    }
}

#[derive(Default)]
struct Shared {
    agent: Option<(String, OwnedObjectPath)>,
    default_agent: bool,
    calls: Vec<String>,
    pairing: HashMap<String, Pairing>,
    connect_failure: HashMap<String, &'static str>,
    agent_answers: Vec<String>,
}

type SharedState = Arc<Mutex<Shared>>;

struct AgentManager {
    shared: SharedState,
}

#[interface(name = "org.bluez.AgentManager1")]
impl AgentManager {
    #[zbus(name = "RegisterAgent")]
    fn register_agent(&self, agent: ObjectPath<'_>, capability: String, #[zbus(header)] header: zbus::message::Header<'_>) {
        let mut shared = self.shared.lock().expect("test state");
        shared.calls.push(format!("RegisterAgent {capability}"));
        shared.agent = header.sender().map(|sender| (sender.to_string(), agent.into()));
    }

    #[zbus(name = "RequestDefaultAgent")]
    fn request_default_agent(&self, _agent: ObjectPath<'_>) {
        self.shared.lock().expect("test state").default_agent = true;
    }
}

struct Adapter {
    shared: SharedState,
    powered: bool,
    alias: String,
    discoverable: bool,
    discoverable_timeout: u32,
    pairable: bool,
    discovering: bool,
}

#[interface(name = "org.bluez.Adapter1")]
impl Adapter {
    #[zbus(property, name = "Address")]
    fn address(&self) -> String {
        "AA:AA:AA:AA:AA:AA".to_string()
    }
    #[zbus(property, name = "Alias")]
    fn alias(&self) -> String {
        self.alias.clone()
    }
    #[zbus(property, name = "Alias")]
    fn set_alias(&mut self, alias: String) {
        self.alias = alias;
    }
    #[zbus(property, name = "Powered")]
    fn powered(&self) -> bool {
        self.powered
    }
    #[zbus(property, name = "Powered")]
    fn set_powered(&mut self, powered: bool) {
        self.shared.lock().expect("test state").calls.push(format!("Powered {powered}"));
        self.powered = powered;
    }
    #[zbus(property, name = "Discoverable")]
    fn discoverable(&self) -> bool {
        self.discoverable
    }
    #[zbus(property, name = "Discoverable")]
    fn set_discoverable(&mut self, discoverable: bool) {
        self.discoverable = discoverable;
    }
    #[zbus(property, name = "DiscoverableTimeout")]
    fn discoverable_timeout(&self) -> u32 {
        self.discoverable_timeout
    }
    #[zbus(property, name = "DiscoverableTimeout")]
    fn set_discoverable_timeout(&mut self, seconds: u32) {
        self.discoverable_timeout = seconds;
    }
    #[zbus(property, name = "Pairable")]
    fn pairable(&self) -> bool {
        self.pairable
    }
    #[zbus(property, name = "Pairable")]
    fn set_pairable(&mut self, pairable: bool) {
        self.pairable = pairable;
    }
    #[zbus(property, name = "Discovering")]
    fn discovering(&self) -> bool {
        self.discovering
    }

    #[zbus(name = "StartDiscovery")]
    async fn start_discovery(&mut self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) -> Result<(), BluezError> {
        if !self.powered {
            return Err(BluezError::NotReady("Resource Not Ready".to_string()));
        }
        self.discovering = true;
        let _ = self.discovering_changed(&emitter).await;
        Ok(())
    }

    #[zbus(name = "StopDiscovery")]
    async fn stop_discovery(&mut self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) -> Result<(), BluezError> {
        if !self.discovering {
            return Err(BluezError::Failed("No discovery started".to_string()));
        }
        self.discovering = false;
        let _ = self.discovering_changed(&emitter).await;
        Ok(())
    }

    #[zbus(name = "RemoveDevice")]
    async fn remove_device(&self, device: ObjectPath<'_>, #[zbus(connection)] connection: &Connection) -> Result<(), BluezError> {
        self.shared.lock().expect("test state").calls.push(format!("RemoveDevice {}", device.as_str()));
        let removed = connection.object_server().remove::<Device, _>(device.as_str()).await.map_err(BluezError::ZBus)?;
        if removed {
            Ok(())
        } else {
            Err(BluezError::DoesNotExist("Does Not Exist".to_string()))
        }
    }
}

struct Device {
    shared: SharedState,
    connection: Connection,
    path: String,
    address: String,
    alias: String,
    icon: String,
    uuids: Vec<String>,
    // Atomic, as it changes while the agent is being asked, and the agent reads this object meanwhile
    paired: AtomicBool,
    trusted: bool,
    blocked: bool,
    connected: bool,
}

async fn ask_agent(connection: &Connection, shared: &SharedState, method: &str, device: &str, pairing: &Pairing) -> Result<(), BluezError> {
    let (agent, agent_path) = shared.lock().expect("test state").agent.clone().ok_or_else(|| BluezError::AuthenticationCanceled("no agent".to_string()))?;
    let device_path = ObjectPath::try_from(device).expect("a valid path");
    let reply = match pairing {
        Pairing::Confirm(passkey) => connection.call_method(Some(agent.as_str()), agent_path.as_str(), Some("org.bluez.Agent1"), method, &(&device_path, *passkey)).await,
        Pairing::ShowPin(pin) => connection.call_method(Some(agent.as_str()), agent_path.as_str(), Some("org.bluez.Agent1"), method, &(&device_path, pin.as_str())).await,
        Pairing::ShowPasskey(passkey) => connection.call_method(Some(agent.as_str()), agent_path.as_str(), Some("org.bluez.Agent1"), method, &(&device_path, *passkey, 0u16)).await,
        _ => connection.call_method(Some(agent.as_str()), agent_path.as_str(), Some("org.bluez.Agent1"), method, &(&device_path,)).await,
    };
    match reply {
        Ok(reply) => {
            if let Pairing::Pin(expected) = pairing {
                let pin: String = reply.body().deserialize().map_err(BluezError::ZBus)?;
                shared.lock().expect("test state").agent_answers.push(pin.clone());
                if &pin != expected {
                    return Err(BluezError::AuthenticationFailed("Wrong PIN".to_string()));
                }
            }
            if let Pairing::Passkey(expected) = pairing {
                let passkey: u32 = reply.body().deserialize().map_err(BluezError::ZBus)?;
                shared.lock().expect("test state").agent_answers.push(passkey.to_string());
                if passkey != *expected {
                    return Err(BluezError::AuthenticationFailed("Wrong passkey".to_string()));
                }
            }
            Ok(())
        }
        Err(zbus::Error::MethodError(name, _, _)) if name.as_str().ends_with("Rejected") => Err(BluezError::AuthenticationRejected("Rejected by the agent".to_string())),
        Err(zbus::Error::MethodError(name, _, _)) if name.as_str().ends_with("Canceled") => Err(BluezError::AuthenticationCanceled("Canceled by the agent".to_string())),
        Err(failure) => Err(BluezError::ZBus(failure)),
    }
}

#[interface(name = "org.bluez.Device1")]
impl Device {
    #[zbus(property, name = "Address")]
    fn address(&self) -> String {
        self.address.clone()
    }
    #[zbus(property, name = "Alias")]
    fn alias(&self) -> String {
        self.alias.clone()
    }
    #[zbus(property, name = "Alias")]
    fn set_alias(&mut self, alias: String) {
        self.alias = alias;
    }
    #[zbus(property, name = "Name")]
    fn name(&self) -> String {
        self.alias.clone()
    }
    #[zbus(property, name = "Icon")]
    fn icon(&self) -> String {
        self.icon.clone()
    }
    #[zbus(property, name = "Adapter")]
    fn adapter(&self) -> OwnedObjectPath {
        path(ADAPTER_PATH)
    }
    #[zbus(property, name = "UUIDs")]
    fn uuids(&self) -> Vec<String> {
        self.uuids.clone()
    }
    #[zbus(property, name = "Paired")]
    fn paired(&self) -> bool {
        self.paired.load(Ordering::SeqCst)
    }
    #[zbus(property, name = "Bonded")]
    fn bonded(&self) -> bool {
        self.paired.load(Ordering::SeqCst)
    }
    #[zbus(property, name = "Trusted")]
    fn trusted(&self) -> bool {
        self.trusted
    }
    #[zbus(property, name = "Trusted")]
    fn set_trusted(&mut self, trusted: bool) {
        self.shared.lock().expect("test state").calls.push(format!("Trusted {trusted}"));
        self.trusted = trusted;
    }
    #[zbus(property, name = "Blocked")]
    fn blocked(&self) -> bool {
        self.blocked
    }
    #[zbus(property, name = "Blocked")]
    fn set_blocked(&mut self, blocked: bool) {
        self.blocked = blocked;
    }
    #[zbus(property, name = "Connected")]
    fn connected(&self) -> bool {
        self.connected
    }

    #[zbus(name = "Pair")]
    async fn pair(&self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) -> Result<(), BluezError> {
        let pairing = {
            let mut shared = self.shared.lock().expect("test state");
            shared.calls.push(format!("Pair {}", self.alias));
            shared.pairing.get(&self.address).cloned().unwrap_or(Pairing::JustWorks)
        };
        let method = match &pairing {
            Pairing::JustWorks => None,
            Pairing::Pin(_) => Some("RequestPinCode"),
            Pairing::Passkey(_) => Some("RequestPasskey"),
            Pairing::Confirm(_) => Some("RequestConfirmation"),
            Pairing::ShowPin(_) => Some("DisplayPinCode"),
            Pairing::ShowPasskey(_) => Some("DisplayPasskey"),
            Pairing::Authorize => Some("RequestAuthorization"),
            Pairing::Fails(name) => return Err(error_named(name)),
        };
        if let Some(method) = method {
            ask_agent(&self.connection, &self.shared, method, &self.path, &pairing).await?;
        }
        self.paired.store(true, Ordering::SeqCst);
        let _ = self.paired_changed(&emitter).await;
        Ok(())
    }

    #[zbus(name = "CancelPairing")]
    fn cancel_pairing(&self) {
        self.shared.lock().expect("test state").calls.push(format!("CancelPairing {}", self.alias));
    }

    #[zbus(name = "Connect")]
    async fn connect(&mut self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) -> Result<(), BluezError> {
        let failure = {
            let mut shared = self.shared.lock().expect("test state");
            shared.calls.push(format!("Connect {}", self.alias));
            shared.connect_failure.get(&self.address).copied()
        };
        if let Some(name) = failure {
            return Err(error_named(name));
        }
        self.connected = true;
        let _ = self.connected_changed(&emitter).await;
        Ok(())
    }

    #[zbus(name = "Disconnect")]
    async fn disconnect(&mut self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) -> Result<(), BluezError> {
        self.shared.lock().expect("test state").calls.push(format!("Disconnect {}", self.alias));
        self.connected = false;
        let _ = self.connected_changed(&emitter).await;
        Ok(())
    }
}

struct Battery {
    percentage: u8,
}

#[interface(name = "org.bluez.Battery1")]
impl Battery {
    #[zbus(property, name = "Percentage")]
    fn percentage(&self) -> u8 {
        self.percentage
    }
}

/// A device to add.
pub struct DeviceSpec<'a> {
    pub address: &'a str,
    pub name: &'a str,
    pub icon: &'a str,
    pub uuids: &'a [&'a str],
    pub paired: bool,
    pub connected: bool,
    pub battery: Option<u8>,
}

impl Default for DeviceSpec<'_> {
    fn default() -> Self {
        Self { address: "00:00:00:00:00:01", name: "Device", icon: "", uuids: &[], paired: false, connected: false, battery: None }
    }
}

pub fn device_path(address: &str) -> String {
    format!("{ADAPTER_PATH}/dev_{}", address.replace(':', "_"))
}

/// The running stand-in, and its controls for tests.
pub struct FakeBluez {
    connection: Connection,
    shared: SharedState,
}

impl FakeBluez {
    pub async fn start(bus: &crate::bus::TestBus) -> anyhow::Result<Self> {
        Self::start_on(bus.connect().await?).await
    }

    pub async fn start_on(connection: Connection) -> anyhow::Result<Self> {
        let shared = SharedState::default();
        let server = connection.object_server();
        server.at("/", fdo::ObjectManager).await?;
        server.at("/org/bluez", AgentManager { shared: Arc::clone(&shared) }).await?;
        server
            .at(ADAPTER_PATH, Adapter { shared: Arc::clone(&shared), powered: true, alias: "laptop".to_string(), discoverable: false, discoverable_timeout: 180, pairable: false, discovering: false })
            .await?;
        connection.request_name(BUS_NAME).await?;
        Ok(Self { connection, shared })
    }

    pub async fn add_device(&self, spec: DeviceSpec<'_>) -> anyhow::Result<String> {
        let device = device_path(spec.address);
        let object = Device {
            shared: Arc::clone(&self.shared),
            connection: self.connection.clone(),
            path: device.clone(),
            address: spec.address.to_string(),
            alias: spec.name.to_string(),
            icon: spec.icon.to_string(),
            uuids: spec.uuids.iter().map(ToString::to_string).collect(),
            paired: AtomicBool::new(spec.paired),
            trusted: spec.paired,
            blocked: false,
            connected: spec.connected,
        };
        let server = self.connection.object_server();
        server.at(device.as_str(), object).await?;
        if let Some(percentage) = spec.battery {
            server.at(device.as_str(), Battery { percentage }).await?;
        }
        Ok(device)
    }

    pub fn set_pairing(&self, address: &str, pairing: Pairing) {
        self.shared.lock().expect("test state").pairing.insert(address.to_string(), pairing);
    }

    pub fn set_connect_failure(&self, address: &str, name: &'static str) {
        self.shared.lock().expect("test state").connect_failure.insert(address.to_string(), name);
    }

    /// Simulates a device dropping off.
    pub async fn disconnect_device(&self, address: &str) -> anyhow::Result<()> {
        let reference = self.connection.object_server().interface::<_, Device>(device_path(address).as_str()).await?;
        reference.get_mut().await.connected = false;
        reference.get().await.connected_changed(reference.signal_emitter()).await?;
        Ok(())
    }

    pub async fn set_adapter_powered(&self, powered: bool) -> anyhow::Result<()> {
        let reference = self.connection.object_server().interface::<_, Adapter>(ADAPTER_PATH).await?;
        reference.get_mut().await.powered = powered;
        reference.get().await.powered_changed(reference.signal_emitter()).await?;
        Ok(())
    }

    pub fn agent_registered(&self) -> bool {
        let shared = self.shared.lock().expect("test state");
        shared.agent.is_some() && shared.default_agent
    }

    pub fn calls(&self) -> Vec<String> {
        self.shared.lock().expect("test state").calls.clone()
    }

    pub fn agent_answers(&self) -> Vec<String> {
        self.shared.lock().expect("test state").agent_answers.clone()
    }

    /// Asks the agent to allow a service, as a device connecting by itself makes BlueZ do.
    pub async fn authorize_service(&self, address: &str, uuid: &str) -> zbus::Result<()> {
        let (agent, agent_path) = self.shared.lock().expect("test state").agent.clone().expect("an agent registered first");
        let device = device_path(address);
        let device = ObjectPath::try_from(device.as_str()).expect("a valid path");
        self.connection.call_method(Some(agent.as_str()), agent_path.as_str(), Some("org.bluez.Agent1"), "AuthorizeService", &(&device, uuid)).await?;
        Ok(())
    }

    pub async fn agent_cancel(&self) -> zbus::Result<()> {
        let (agent, agent_path) = self.shared.lock().expect("test state").agent.clone().expect("an agent registered first");
        self.connection.call_method(Some(agent.as_str()), agent_path.as_str(), Some("org.bluez.Agent1"), "Cancel", &()).await?;
        Ok(())
    }

    pub async fn stop(self) -> anyhow::Result<()> {
        self.connection.release_name(BUS_NAME).await?;
        Ok(())
    }
}

// ---- obexd ----

const OBEX_BUS: &str = "org.bluez.obex";
const OBEX_ROOT: &str = "/org/bluez/obex";

#[derive(Default)]
struct ObexState {
    agent: Option<(String, OwnedObjectPath)>,
    next: u32,
    sent: Vec<(String, String)>,
    refuse_sends: bool,
    sessions_open: u32,
}

type ObexShared = Arc<Mutex<ObexState>>;

struct ObexClient {
    shared: ObexShared,
}

#[interface(name = "org.bluez.obex.Client1")]
impl ObexClient {
    #[zbus(name = "CreateSession")]
    async fn create_session(&self, destination: String, _options: HashMap<String, OwnedVariant>, #[zbus(connection)] connection: &Connection) -> fdo::Result<OwnedObjectPath> {
        let session = {
            let mut shared = self.shared.lock().expect("test state");
            shared.next += 1;
            shared.sessions_open += 1;
            format!("{OBEX_ROOT}/client/session{}", shared.next)
        };
        connection
            .object_server()
            .at(session.as_str(), ObexPush { shared: Arc::clone(&self.shared), destination: destination.clone(), session: session.clone() })
            .await
            .map_err(|failure| fdo::Error::Failed(failure.to_string()))?;
        connection.object_server().at(session.as_str(), ObexSession { destination }).await.map_err(|failure| fdo::Error::Failed(failure.to_string()))?;
        Ok(path(&session))
    }

    #[zbus(name = "RemoveSession")]
    async fn remove_session(&self, _session: ObjectPath<'_>) {
        self.shared.lock().expect("test state").sessions_open -= 1;
    }
}

struct ObexPush {
    shared: ObexShared,
    destination: String,
    session: String,
}

#[interface(name = "org.bluez.obex.ObjectPush1")]
impl ObexPush {
    #[zbus(name = "SendFile")]
    async fn send_file(&self, file: String, #[zbus(connection)] connection: &Connection) -> fdo::Result<(OwnedObjectPath, HashMap<String, OwnedVariant>)> {
        let (transfer, refuse) = {
            let mut shared = self.shared.lock().expect("test state");
            shared.next += 1;
            shared.sent.push((self.destination.clone(), file.clone()));
            (format!("{}/transfer{}", self.session, shared.next), shared.refuse_sends)
        };
        let size = std::fs::metadata(&file).map(|data| data.len()).unwrap_or(0);
        connection
            .object_server()
            .at(transfer.as_str(), ObexTransfer { status: "queued".to_string(), name: file, size, transferred: 0, session: path(&self.session) })
            .await
            .map_err(|failure| fdo::Error::Failed(failure.to_string()))?;
        let finish = connection.clone();
        let target = transfer.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(30)).await;
            let _ = settle_transfer(&finish, &target, if refuse { "error" } else { "complete" }).await;
        });
        let mut properties = HashMap::new();
        properties.insert("Size".to_string(), Variant::from(size).try_into_owned().expect("a number"));
        Ok((path(&transfer), properties))
    }
}

async fn settle_transfer(connection: &Connection, transfer: &str, status: &str) -> anyhow::Result<()> {
    let reference = connection.object_server().interface::<_, ObexTransfer>(transfer).await?;
    let size = reference.get().await.size;
    reference.get_mut().await.transferred = size;
    reference.get().await.transferred_changed(reference.signal_emitter()).await?;
    reference.get_mut().await.status = status.to_string();
    reference.get().await.status_changed(reference.signal_emitter()).await?;
    Ok(())
}

struct ObexSession {
    destination: String,
}

#[interface(name = "org.bluez.obex.Session1")]
impl ObexSession {
    #[zbus(property, name = "Destination")]
    fn destination(&self) -> String {
        self.destination.clone()
    }
}

struct ObexTransfer {
    status: String,
    name: String,
    size: u64,
    transferred: u64,
    session: OwnedObjectPath,
}

#[interface(name = "org.bluez.obex.Transfer1")]
impl ObexTransfer {
    #[zbus(property, name = "Status")]
    fn status(&self) -> String {
        self.status.clone()
    }
    #[zbus(property, name = "Name")]
    fn name(&self) -> String {
        self.name.clone()
    }
    #[zbus(property, name = "Size")]
    fn size(&self) -> u64 {
        self.size
    }
    #[zbus(property, name = "Transferred")]
    fn transferred(&self) -> u64 {
        self.transferred
    }
    #[zbus(property, name = "Session")]
    fn session(&self) -> OwnedObjectPath {
        self.session.clone()
    }
}

struct ObexAgentManager {
    shared: ObexShared,
}

#[interface(name = "org.bluez.obex.AgentManager1")]
impl ObexAgentManager {
    #[zbus(name = "RegisterAgent")]
    fn register_agent(&self, agent: ObjectPath<'_>, #[zbus(header)] header: zbus::message::Header<'_>) {
        self.shared.lock().expect("test state").agent = header.sender().map(|sender| (sender.to_string(), agent.into()));
    }
}

pub struct FakeObex {
    connection: Connection,
    shared: ObexShared,
}

impl FakeObex {
    pub async fn start(bus: &crate::bus::TestBus) -> anyhow::Result<Self> {
        let connection = bus.connect().await?;
        let shared = ObexShared::default();
        let server = connection.object_server();
        server.at(OBEX_ROOT, ObexClient { shared: Arc::clone(&shared) }).await?;
        server.at(OBEX_ROOT, ObexAgentManager { shared: Arc::clone(&shared) }).await?;
        connection.request_name(OBEX_BUS).await?;
        Ok(Self { connection, shared })
    }

    pub fn agent_registered(&self) -> bool {
        self.shared.lock().expect("test state").agent.is_some()
    }

    pub fn sent(&self) -> Vec<(String, String)> {
        self.shared.lock().expect("test state").sent.clone()
    }

    pub fn sessions_open(&self) -> u32 {
        self.shared.lock().expect("test state").sessions_open
    }

    pub fn set_refuse_sends(&self, refuse: bool) {
        self.shared.lock().expect("test state").refuse_sends = refuse;
    }

    /// A device pushes a file: asks the agent where it goes, writes it there, and says it's done or failed.
    /// Returns where the agent put it, or the error it gave.
    pub async fn incoming(&self, from: &str, name: &str, contents: &[u8], fail: bool) -> Result<String, String> {
        let (agent, agent_path) = self.shared.lock().expect("test state").agent.clone().expect("an agent registered first");
        let (session, transfer) = {
            let mut shared = self.shared.lock().expect("test state");
            shared.next += 1;
            (format!("{OBEX_ROOT}/server/session{}", shared.next), format!("{OBEX_ROOT}/server/session{}/transfer", shared.next))
        };
        let server = self.connection.object_server();
        server.at(session.as_str(), ObexSession { destination: from.to_string() }).await.map_err(|failure| failure.to_string())?;
        server
            .at(transfer.as_str(), ObexTransfer { status: "queued".to_string(), name: name.to_string(), size: contents.len() as u64, transferred: 0, session: path(&session) })
            .await
            .map_err(|failure| failure.to_string())?;
        let transfer_path = ObjectPath::try_from(transfer.as_str()).expect("a valid path");
        let reply = self
            .connection
            .call_method(Some(agent.as_str()), agent_path.as_str(), Some("org.bluez.obex.Agent1"), "AuthorizePush", &(&transfer_path,))
            .await
            .map_err(|failure| failure.to_string())?;
        let target: String = reply.body().deserialize().map_err(|failure| failure.to_string())?;
        std::fs::write(&target, contents).map_err(|failure| failure.to_string())?;
        settle_transfer(&self.connection, &transfer, if fail { "error" } else { "complete" }).await.map_err(|failure| failure.to_string())?;
        Ok(target)
    }
}

// ---- logind ----

struct LoginManager;

#[interface(name = "org.freedesktop.login1.Manager")]
impl LoginManager {
    #[zbus(signal, name = "PrepareForSleep")]
    async fn prepare_for_sleep(emitter: &SignalEmitter<'_>, start: bool) -> zbus::Result<()>;
}

pub struct FakeLogind {
    connection: Connection,
}

impl FakeLogind {
    pub async fn start(bus: &crate::bus::TestBus) -> anyhow::Result<Self> {
        let connection = bus.connect().await?;
        connection.object_server().at("/org/freedesktop/login1", LoginManager).await?;
        connection.request_name("org.freedesktop.login1").await?;
        Ok(Self { connection })
    }

    pub async fn sleep(&self, start: bool) -> anyhow::Result<()> {
        let reference = self.connection.object_server().interface::<_, LoginManager>("/org/freedesktop/login1").await?;
        LoginManager::prepare_for_sleep(reference.signal_emitter(), start).await?;
        Ok(())
    }
}
