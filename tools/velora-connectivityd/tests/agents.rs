//! NetworkManager asking the daemon for secrets, the way it does when it connects.

mod common;

use common::Daemon;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::time::Duration;
use velora_connectivity_fakes::bus::TestBus;
use velora_connectivity_fakes::nm::{value, FakeNm, Props, Settings};
use velora_connectivity_fakes::secrets::{FakeKWallet, FakeSecrets};

const ASK: u32 = 0x1;
const NEW: u32 = 0x3;

fn wifi(uuid: &str, extra: &[(&str, &str)]) -> Settings {
    let mut section = Props::new();
    section.insert("key-mgmt".to_string(), value("wpa-psk"));
    for (key, text) in extra {
        section.insert((*key).to_string(), value(*text));
    }
    let mut connection = Props::new();
    connection.insert("id".to_string(), value("Home"));
    connection.insert("uuid".to_string(), value(uuid));
    connection.insert("type".to_string(), value("802-11-wireless"));
    HashMap::from([("connection".to_string(), connection), ("802-11-wireless-security".to_string(), section)])
}

fn vpn(data: &[(&str, &str)]) -> Settings {
    let mut connection = Props::new();
    connection.insert("id".to_string(), value("Work"));
    connection.insert("uuid".to_string(), value("vpn-uuid"));
    connection.insert("type".to_string(), value("vpn"));
    let map: HashMap<String, String> = data.iter().map(|(key, text)| (key.to_string(), text.to_string())).collect();
    let mut section = Props::new();
    section.insert("data".to_string(), value(map));
    HashMap::from([("connection".to_string(), connection), ("vpn".to_string(), section)])
}

async fn setup() -> (TestBus, FakeNm, FakeSecrets, Daemon) {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let secrets = FakeSecrets::start(&bus).await.unwrap();
    let mut daemon = Daemon::start(&bus, &["--agents"]).await;
    let hello = daemon.wait_message("hello", |message| message["type"] == "hello").await;
    assert_eq!(hello["agents"], true);
    wait_registered(&nm).await;
    (bus, nm, secrets, daemon)
}

async fn wait_registered(nm: &FakeNm) {
    for _ in 0..100 {
        if nm.agent_registered() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(30)).await;
    }
    panic!("the agent never registered");
}

async fn prompt(daemon: &mut Daemon) -> Value {
    daemon.wait_message("a prompt", |message| message["name"] == "prompt").await["data"].clone()
}

fn text(reply: &Settings, section: &str, key: &str) -> Option<String> {
    reply.get(section)?.get(key)?.downcast_ref::<&str>().ok().map(str::to_string)
}

#[tokio::test]
async fn it_registers_only_when_asked_to_answer_prompts() {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let mut daemon = Daemon::start(&bus, &[]).await;
    assert_eq!(daemon.wait_message("hello", |message| message["type"] == "hello").await["agents"], false);
    daemon.wait_network("a snapshot", |state| state["available"] == true).await;
    assert!(!nm.agent_registered());

    let mut with_agents = Daemon::start(&bus, &["--agents"]).await;
    assert_eq!(with_agents.wait_message("hello", |message| message["type"] == "hello").await["agents"], true);
    wait_registered(&nm).await;
    assert!(nm.calls().contains(&"RegisterAgent org.velora.shell capabilities=1".to_string()));

    // A second shell doesn't fight the first for it
    let mut second = Daemon::start(&bus, &["--agents"]).await;
    assert_eq!(second.wait_message("hello", |message| message["type"] == "hello").await["agents"], false);
}

#[tokio::test]
async fn a_missing_password_is_asked_for_and_handed_on() {
    let (_bus, nm, _secrets, mut daemon) = setup().await;
    let request = tokio::spawn({
        let settings = wifi("u", &[]);
        async move { nm.ask_agent(&settings, "802-11-wireless-security", Vec::new(), ASK).await.map(|reply| (reply, nm)) }
    });
    let question = prompt(&mut daemon).await;
    assert_eq!(question["kind"], "secrets");
    assert_eq!(question["connectionName"], "Home");
    assert_eq!(question["connectionType"], "802-11-wireless");
    assert_eq!(question["fields"], json!(["psk"]));
    assert_eq!(question["retry"], false);
    let answer = daemon.call("prompt.answer", json!({ "id": question["id"], "accepted": true, "values": { "psk": "typed-password" } })).await;
    assert_eq!(answer["result"]["stillOpen"], true);
    let (reply, _nm) = request.await.unwrap().unwrap();
    assert_eq!(text(&reply, "802-11-wireless-security", "psk").as_deref(), Some("typed-password"));
    // The prompt carried no secret, and the typed one isn't echoed anywhere
    assert!(!daemon.transcript.iter().any(|line| line.contains("typed-password")));
}

#[tokio::test]
async fn declining_tells_the_service_so() {
    let (_bus, nm, _secrets, mut daemon) = setup().await;
    let request = tokio::spawn(async move { nm.ask_agent(&wifi("u", &[]), "802-11-wireless-security", Vec::new(), ASK).await });
    let question = prompt(&mut daemon).await;
    daemon.call("prompt.answer", json!({ "id": question["id"], "accepted": false })).await;
    let error = request.await.unwrap().unwrap_err();
    assert!(error.to_string().contains("UserCanceled"), "{error}");
}

#[tokio::test]
async fn the_service_giving_up_closes_the_dialog() {
    let (_bus, nm, _secrets, mut daemon) = setup().await;
    let nm = std::sync::Arc::new(nm);
    let asker = std::sync::Arc::clone(&nm);
    let request = tokio::spawn(async move { asker.ask_agent(&wifi("u", &[]), "802-11-wireless-security", Vec::new(), ASK).await });
    prompt(&mut daemon).await;
    nm.cancel_agent_request("802-11-wireless-security").await.unwrap();
    daemon.wait_message("the dialog to close", |message| message["name"] == "promptWithdrawn").await;
    let error = request.await.unwrap().unwrap_err();
    assert!(error.to_string().contains("AgentCanceled"), "{error}");
}

#[tokio::test]
async fn without_permission_to_ask_it_says_there_are_no_secrets() {
    let (_bus, nm, _secrets, _daemon) = setup().await;
    let error = nm.ask_agent(&wifi("u", &[]), "802-11-wireless-security", Vec::new(), 0).await.unwrap_err();
    assert!(error.to_string().contains("NoSecrets"), "{error}");
}

#[tokio::test]
async fn what_plasma_stored_is_found_without_asking() {
    let (_bus, nm, secrets, _daemon) = setup().await;
    secrets.seed("{u};802-11-wireless-security", r#"{"psk":"from-the-keyring"}"#).await.unwrap();
    let answer = tokio::time::timeout(Duration::from_secs(10), nm.ask_agent(&wifi("u", &[]), "802-11-wireless-security", Vec::new(), ASK)).await;
    let reply = answer.expect("found without asking anyone").unwrap();
    assert_eq!(text(&reply, "802-11-wireless-security", "psk").as_deref(), Some("from-the-keyring"));
}

#[tokio::test]
async fn a_refused_password_skips_the_keyring_and_asks_again() {
    let (_bus, nm, secrets, mut daemon) = setup().await;
    secrets.seed("{u};802-11-wireless-security", r#"{"psk":"old"}"#).await.unwrap();
    let request = tokio::spawn(async move { nm.ask_agent(&wifi("u", &[]), "802-11-wireless-security", Vec::new(), NEW).await });
    let question = prompt(&mut daemon).await;
    assert_eq!(question["retry"], true);
    daemon.call("prompt.answer", json!({ "id": question["id"], "accepted": true, "values": { "psk": "new" } })).await;
    let reply = request.await.unwrap().unwrap();
    assert_eq!(text(&reply, "802-11-wireless-security", "psk").as_deref(), Some("new"));
}

#[tokio::test]
async fn secrets_kept_for_this_user_land_where_plasma_looks_and_go_again() {
    let (_bus, nm, secrets, _daemon) = setup().await;
    let mut settings = wifi("u", &[("psk", "mine")]);
    settings.get_mut("802-11-wireless-security").unwrap().insert("psk-flags".to_string(), value(1u32));
    nm.agent_save(&settings).await.unwrap();
    assert_eq!(secrets.entry("{u};802-11-wireless-security").as_deref(), Some(r#"{"psk":"mine"}"#));
    // Saved again, it replaces rather than piles up
    let mut changed = wifi("u", &[("psk", "mine2")]);
    changed.get_mut("802-11-wireless-security").unwrap().insert("psk-flags".to_string(), value(1u32));
    nm.agent_save(&changed).await.unwrap();
    assert_eq!(secrets.entry("{u};802-11-wireless-security").as_deref(), Some(r#"{"psk":"mine2"}"#));
    assert_eq!(secrets.count(), 1);
    nm.agent_delete(&settings).await.unwrap();
    assert_eq!(secrets.count(), 0);
}

#[tokio::test]
async fn secrets_the_system_keeps_arent_copied_to_the_keyring() {
    let (_bus, nm, secrets, _daemon) = setup().await;
    nm.agent_save(&wifi("u", &[("psk", "system")])).await.unwrap();
    assert_eq!(secrets.count(), 0);
}

#[tokio::test]
async fn a_vpn_code_is_asked_for_with_the_servers_words() {
    let (_bus, nm, _secrets, mut daemon) = setup().await;
    let settings = vpn(&[("password-flags", "0"), ("challenge-response-flags", "2")]);
    let hints = vec!["x-vpn-message:Enter your one-time code".to_string(), "challenge-response".to_string()];
    let request = tokio::spawn(async move { nm.ask_agent(&settings, "vpn", hints, ASK).await });
    let question = prompt(&mut daemon).await;
    assert_eq!(question["fields"], json!(["challenge-response"]));
    assert_eq!(question["message"], "Enter your one-time code");
    assert_eq!(question["connectionType"], "vpn");
    daemon.call("prompt.answer", json!({ "id": question["id"], "accepted": true, "values": { "challenge-response": "123456" } })).await;
    let reply = request.await.unwrap().unwrap();
    let secrets = HashMap::<String, String>::try_from(reply["vpn"]["secrets"].clone()).unwrap();
    assert_eq!(secrets["challenge-response"], "123456");
}

#[tokio::test]
async fn it_registers_again_when_the_service_comes_back() {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let mut daemon = Daemon::start(&bus, &["--agents"]).await;
    wait_registered(&nm).await;
    nm.stop().await.unwrap();
    daemon.wait_network("it to go", |state| state["available"] == false).await;
    let nm = FakeNm::start(&bus).await.unwrap();
    wait_registered(&nm).await;
    daemon.wait_network("it to return", |state| state["available"] == true).await;
}

#[tokio::test]
async fn an_answer_to_a_closed_question_is_harmless() {
    let (_bus, _nm, _secrets, mut daemon) = setup().await;
    let answer = daemon.call("prompt.answer", json!({ "id": 12345, "accepted": true, "values": { "psk": "x" } })).await;
    assert_eq!(answer["result"]["stillOpen"], false);
}

#[tokio::test]
async fn it_runs_without_a_session_bus_and_without_a_keyring() {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let mut daemon = Daemon::start(&bus, &["--agents"]).await;
    wait_registered(&nm).await;
    let request = tokio::spawn(async move { nm.ask_agent(&wifi("u", &[]), "802-11-wireless-security", Vec::new(), ASK).await });
    let question = prompt(&mut daemon).await;
    daemon.call("prompt.answer", json!({ "id": question["id"], "accepted": true, "values": { "psk": "y" } })).await;
    assert!(request.await.unwrap().is_ok());
}

#[tokio::test]
async fn what_plasma_left_in_kwallet_is_read_when_a_wallet_exists() {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let _wallet = FakeKWallet::start(&bus, &[("{u};802-11-wireless-security", r#"{"psk":"from-the-wallet"}"#)]).await.unwrap();
    let home = common::TempHome::new("kwallet");
    let wallets = home.path.join("data/kwalletd");
    std::fs::create_dir_all(&wallets).unwrap();
    std::fs::write(wallets.join("kdewallet.kwl"), "").unwrap();
    let _daemon = Daemon::start_in(&bus, &home.path, &["--agents"], None).await;
    wait_registered(&nm).await;
    let answer = tokio::time::timeout(Duration::from_secs(10), nm.ask_agent(&wifi("u", &[]), "802-11-wireless-security", Vec::new(), ASK)).await;
    let reply = answer.expect("found without asking anyone").unwrap();
    assert_eq!(text(&reply, "802-11-wireless-security", "psk").as_deref(), Some("from-the-wallet"));
}

#[tokio::test]
async fn kwallet_isnt_touched_without_a_wallet_file_since_asking_would_create_one() {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let _wallet = FakeKWallet::start(&bus, &[("{u};802-11-wireless-security", r#"{"psk":"from-the-wallet"}"#)]).await.unwrap();
    let home = common::TempHome::new("nokwallet");
    let mut daemon = Daemon::start_in(&bus, &home.path, &["--agents"], None).await;
    wait_registered(&nm).await;
    let request = tokio::spawn(async move { nm.ask_agent(&wifi("u", &[]), "802-11-wireless-security", Vec::new(), ASK).await });
    let question = prompt(&mut daemon).await;
    assert_eq!(question["kind"], "secrets", "nothing found, so it asks");
    daemon.call("prompt.answer", json!({ "id": question["id"], "accepted": false })).await;
    assert!(request.await.unwrap().is_err());
}
