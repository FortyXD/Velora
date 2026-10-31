//! The daemon's life: say hello, answer requests from stdin, publish snapshots on stdout, and stop when
//! the shell closes stdin.

use crate::airplane;
use crate::bluez::agent::{self as pairing, PairingAgent};
use crate::bluez::client::BluezClient;
use crate::bluez::model::BluetoothSnapshot;
use crate::bluez::obex::{self, ObexAgent, ObexShared, ReceivePolicy, ReceiveSettings};
use crate::bluez::state::{self, OnLogin};
use crate::nm::agent::{self, SecretAgent, AGENT_PATH};
use crate::nm::client::NmClient;
use crate::prompts::Prompts;
use crate::secret_store::SecretStore;
use crate::protocol::{ApiError, ErrorCode, Outgoing, Request, PROTOCOL_VERSION};
use crate::service::Service;
use futures_util::StreamExt;
use serde_json::Value;
use std::num::NonZeroUsize;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, Notify};
use zbus::fdo::{RequestNameFlags, RequestNameReply};
use zbus::message::Type as MessageType;
use zbus::object_server::InterfaceRef;
use zbus::{Connection, MatchRule, MessageStream};
use zeroize::Zeroizing;

/// Bursts of signals, like a scan's, collapse into one snapshot.
const SNAPSHOT_DELAY: Duration = Duration::from_millis(150);
const RECONNECT_DELAY: Duration = Duration::from_secs(5);
const AGENTS_BUS_NAME: &str = "org.velora.Connectivity";
const RESUME_DELAY: Duration = Duration::from_secs(1);
const STATE_SAVE_INTERVAL: Duration = Duration::from_secs(2);

fn default_receive_folder() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join("Downloads")
}

#[derive(Debug, Default, Clone, Copy)]
pub struct Options {
    pub agents: bool,
}

async fn write_lines(mut lines: mpsc::UnboundedReceiver<String>) {
    let mut stdout = tokio::io::stdout();
    while let Some(line) = lines.recv().await {
        if stdout.write_all(line.as_bytes()).await.is_err() || stdout.flush().await.is_err() {
            // The shell is gone; stdin closing will finish the rest
            break;
        }
    }
}

fn network_value(service: &Service, snapshot: &crate::nm::model::NetworkSnapshot) -> Value {
    let scanning = service.network.scanning(snapshot);
    let mut value = serde_json::to_value(snapshot).expect("snapshots hold plain values");
    value["wifiScanning"] = Value::Bool(scanning);
    value["airplaneMode"] = Value::Bool(airplane::is_on());
    value
}

async fn publish_network(service: Arc<Service>, out: mpsc::UnboundedSender<String>) {
    let mut last = None;
    loop {
        let snapshot = service.network.snapshot().await;
        let value = network_value(&service, &snapshot);
        if last.as_ref() != Some(&value) {
            let line = Outgoing::Snapshot { domain: "network", data: &value }.to_line();
            if out.send(line).is_err() {
                return;
            }
            last = Some(value);
        }
        // A scan that never reports back still has to stop showing as one
        let wait = service.network.changed.notified();
        let _ = tokio::time::timeout(Duration::from_secs(5), wait).await;
        tokio::time::sleep(SNAPSHOT_DELAY).await;
    }
}

async fn watch_network(service: Arc<Service>) {
    loop {
        if service.network.watch().await.is_err() {
            service.network.changed.notify_one();
        }
        tokio::time::sleep(RECONNECT_DELAY).await;
    }
}

/// One process answers prompts. Whichever holds this name does; a second copy of the shell doesn't fight it.
async fn claim_agents(session: Option<&Connection>) -> bool {
    let Some(session) = session else { return true };
    let flags = RequestNameFlags::DO_NOT_QUEUE;
    matches!(session.request_name_with_flags(AGENTS_BUS_NAME, flags).await, Ok(RequestNameReply::PrimaryOwner | RequestNameReply::AlreadyOwner))
}

/// Registers the pairing agent whenever BlueZ is there, as it forgets agents when it restarts.
async fn keep_pairing_agent_registered(system: Connection, service: Arc<Service>) {
    let mut registered = false;
    loop {
        let available = service.bluetooth.is_running().await;
        if available && !registered {
            registered = pairing::register(&system).await.is_ok();
        } else if !available {
            registered = false;
        }
        service.bluetooth.availability_changed.notified().await;
    }
}

/// Registers the agent whenever NetworkManager is there, which matters again after each of its restarts.
async fn keep_agent_registered(system: Connection, service: Arc<Service>) {
    let mut registered = false;
    loop {
        let available = service.network.is_running().await;
        if available && !registered {
            registered = agent::register(&system).await.is_ok();
        } else if !available {
            registered = false;
        }
        service.network.availability_changed.notified().await;
    }
}

async fn publish_bluetooth_from(service: Arc<Service>, out: mpsc::UnboundedSender<String>, agent: Option<InterfaceRef<PairingAgent>>) {
    let mut last = None;
    loop {
        let snapshot = service.bluetooth.snapshot().await;
        if let Some(agent) = &agent {
            agent.get().await.settle(&snapshot);
        }
        let value = serde_json::to_value(&snapshot).expect("snapshots hold plain values");
        if last.as_ref() != Some(&value) {
            let line = Outgoing::Snapshot { domain: "bluetooth", data: &value }.to_line();
            if out.send(line).is_err() {
                return;
            }
            last = Some(value);
        }
        let wait = service.bluetooth.changed.notified();
        // The radio's block state has no signal of its own
        let _ = tokio::time::timeout(Duration::from_secs(5), wait).await;
        tokio::time::sleep(SNAPSHOT_DELAY).await;
    }
}

async fn watch_bluetooth(service: Arc<Service>) {
    loop {
        if service.bluetooth.watch().await.is_err() {
            service.bluetooth.changed.notify_one();
        }
        tokio::time::sleep(RECONNECT_DELAY).await;
    }
}

async fn apply_plan(service: &Service, mode: OnLogin, saved: &state::SavedState, snapshot: &BluetoothSnapshot) {
    let plan = state::plan(mode, saved, snapshot);
    for (adapter, powered) in plan.power {
        let _ = service.bluetooth.set_powered(&adapter, powered).await;
    }
    // Nothing to answer to, and a device that's off now just stays unconnected
    for device in plan.connect {
        let _ = service.bluetooth.connect(&device).await;
    }
}

/// Puts Bluetooth where it should be at login and after sleep, and keeps track of how it's left.
async fn follow_login_state(service: Arc<Service>, system: Connection) {
    // The shell says what it wants right after it starts; a shell that doesn't get the default
    let _ = tokio::time::timeout(Duration::from_secs(3), service.configured.notified()).await;
    let mode = service.on_login.lock().expect("no panics while holding this lock").unwrap_or(OnLogin::Remember);
    let mut saved = state::load();
    let mut snapshot = service.bluetooth.snapshot().await;
    while !snapshot.available {
        service.bluetooth.availability_changed.notified().await;
        snapshot = service.bluetooth.snapshot().await;
    }
    apply_plan(&service, mode, &saved, &snapshot).await;

    let Ok(rule) = MatchRule::builder().msg_type(MessageType::Signal).sender("org.freedesktop.login1").member("PrepareForSleep").build() else { return };
    let Ok(mut sleeps) = MessageStream::for_match_rule(rule, &system, NonZeroUsize::new(4)).await else { return };
    let mut asleep = false;
    loop {
        tokio::select! {
            Some(Ok(message)) = sleeps.next() => {
                let Ok(going) = message.body().deserialize::<bool>() else { continue };
                asleep = going;
                if !going {
                    // Devices take a moment to be back; they're asked once, the same as at login
                    tokio::time::sleep(RESUME_DELAY).await;
                    let snapshot = service.bluetooth.snapshot().await;
                    let mode = service.on_login.lock().expect("no panics while holding this lock").unwrap_or(OnLogin::Remember);
                    let keep = if mode == OnLogin::Off { OnLogin::Remember } else { mode };
                    apply_plan(&service, keep, &saved, &snapshot).await;
                }
            }
            () = tokio::time::sleep(STATE_SAVE_INTERVAL) => {}
        }
        if asleep {
            continue;
        }
        let snapshot = service.bluetooth.snapshot().await;
        // No adapters is the system shutting down, not a choice
        if snapshot.available {
            let current = state::capture(&snapshot);
            if current != saved {
                state::save(&current);
                saved = current;
            }
        }
    }
}

fn handle_line(line: &str, service: &Arc<Service>, out: &mpsc::UnboundedSender<String>) {
    let request: Request = match serde_json::from_str(line) {
        Ok(request) => request,
        Err(_) => {
            // No id to answer to, and the line may hold a password, so it isn't repeated
            let error = ApiError::new(ErrorCode::Invalid, "a request wasn't valid JSON");
            let _ = out.send(Outgoing::Event { name: "protocolError", data: &serde_json::to_value(&error).expect("plain fields") }.to_line());
            return;
        }
    };
    let service = Arc::clone(service);
    let out = out.clone();
    tokio::spawn(async move {
        let result = service.call(&request.method, request.params).await;
        let _ = out.send(Outgoing::reply(request.id, &result));
    });
}

pub async fn run(options: Options) -> anyhow::Result<()> {
    let (out, lines) = mpsc::unbounded_channel();
    let writer = tokio::spawn(write_lines(lines));
    let session = Connection::session().await.ok();
    let agents_active = options.agents && claim_agents(session.as_ref()).await;
    out.send(Outgoing::Hello { protocol: PROTOCOL_VERSION, agents: agents_active }.to_line())?;

    let system = Connection::system().await?;
    let prompts = Arc::new(Prompts::new(out.clone()));
    let receive: Arc<ObexShared> = ObexShared::new(ReceiveSettings { policy: ReceivePolicy::Ask, folder: default_receive_folder() });
    let service = Arc::new(Service {
        network: NmClient::new(system.clone()),
        bluetooth: BluezClient::new(system.clone()),
        prompts: Arc::clone(&prompts),
        session: session.clone(),
        out: out.clone(),
        receive: Arc::clone(&receive),
        on_login: Mutex::default(),
        configured: Notify::new(),
    });
    tokio::spawn(watch_network(Arc::clone(&service)));
    tokio::spawn(watch_bluetooth(Arc::clone(&service)));
    let mut pairing_agent = None;
    if agents_active {
        let store = Arc::new(SecretStore::new(session.clone()));
        let agent = SecretAgent { prompts: Arc::clone(&prompts), store, open: Mutex::default() };
        system.object_server().at(AGENT_PATH, agent).await?;
        tokio::spawn(keep_agent_registered(system.clone(), Arc::clone(&service)));

        let agent = PairingAgent { connection: system.clone(), prompts: Arc::clone(&prompts), open: Mutex::default(), showing_for: Mutex::default() };
        system.object_server().at(pairing::AGENT_PATH, agent).await?;
        let reference = system.object_server().interface::<_, PairingAgent>(pairing::AGENT_PATH).await?;
        pairing_agent = Some(reference);
        tokio::spawn(keep_pairing_agent_registered(system.clone(), Arc::clone(&service)));
        tokio::spawn(follow_login_state(Arc::clone(&service), system.clone()));

        if let Some(session) = session.clone() {
            let agent = ObexAgent { session: session.clone(), system: system.clone(), prompts: Arc::clone(&prompts), shared: Arc::clone(&receive) };
            session.object_server().at(obex::AGENT_PATH, agent).await?;
            // obexd may not be installed; sending and receiving files just aren't available then
            let _ = obex::register_agent(&session).await;
            tokio::spawn(obex::follow_incoming(session, Arc::clone(&receive), out.clone()));
        }
    }
    tokio::spawn(publish_bluetooth_from(Arc::clone(&service), out.clone(), pairing_agent));
    tokio::spawn(publish_network(Arc::clone(&service), out.clone()));

    let mut stdin = BufReader::new(tokio::io::stdin());
    loop {
        let mut line = Zeroizing::new(String::new());
        if stdin.read_line(&mut line).await? == 0 {
            break;
        }
        if !line.trim().is_empty() {
            handle_line(&line, &service, &out);
        }
    }
    drop(out);
    writer.abort();
    Ok(())
}
