//! The daemon against stand-in BlueZ, obexd and logind on a real, private message bus.

mod common;

use common::{Daemon, TempHome};
use serde_json::{json, Value};
use std::time::Duration;
use velora_connectivity_fakes::bluez::{device_path, DeviceSpec, FakeBluez, FakeLogind, FakeObex, Pairing};
use velora_connectivity_fakes::bus::TestBus;
use velora_connectivity_fakes::nm::FakeNm;

const PHONE: &str = "11:22:33:44:55:66";
const HEADSET: &str = "AA:BB:CC:DD:EE:FF";
const OBEX_PUSH: &str = "00001105-0000-1000-8000-00805f9b34fb";
const A2DP: &str = "0000110b-0000-1000-8000-00805f9b34fb";

async fn setup(name: &str) -> (TestBus, FakeBluez, Daemon, TempHome) {
    let bus = TestBus::start().unwrap();
    let bluez = FakeBluez::start(&bus).await.unwrap();
    let home = TempHome::new(name);
    let mut daemon = Daemon::start_in(&bus, &home.path, &["--agents"], None).await;
    wait_agent(&bluez).await;
    daemon.wait_bluetooth("the adapter", |state| state["available"] == true).await;
    (bus, bluez, daemon, home)
}

async fn wait_agent(bluez: &FakeBluez) {
    for _ in 0..150 {
        if bluez.agent_registered() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("the agent never registered");
}

fn saved<'a>(state: &'a Value, name: &str) -> Option<&'a Value> {
    state["saved"].as_array()?.iter().find(|device| device["name"] == name)
}

fn nearby<'a>(state: &'a Value, name: &str) -> Option<&'a Value> {
    state["nearby"].as_array()?.iter().find(|device| device["name"] == name)
}

async fn prompt(daemon: &mut Daemon) -> Value {
    daemon.wait_message("a prompt", |message| message["name"] == "prompt").await["data"].clone()
}

async fn answer(daemon: &mut Daemon, question: &Value, accepted: bool, values: Value) {
    let reply = daemon.call("prompt.answer", json!({ "id": question["id"], "accepted": accepted, "values": values })).await;
    assert_eq!(reply["result"]["stillOpen"], true, "{reply}");
}

#[tokio::test]
async fn it_shows_saved_devices_with_their_details_and_nearby_ones_apart() {
    let (_bus, bluez, mut daemon, _home) = setup("list").await;
    bluez.add_device(DeviceSpec { address: PHONE, name: "Phone", icon: "phone", uuids: &[OBEX_PUSH], paired: true, battery: Some(80), ..DeviceSpec::default() }).await.unwrap();
    bluez.add_device(DeviceSpec { address: HEADSET, name: "Headset", icon: "audio-headset", uuids: &[A2DP], paired: true, connected: true, ..DeviceSpec::default() }).await.unwrap();
    bluez.add_device(DeviceSpec { address: "00:00:00:00:00:09", name: "Speaker", ..DeviceSpec::default() }).await.unwrap();
    let state = daemon.wait_bluetooth("all three", |state| saved(state, "Phone").is_some() && saved(state, "Headset").is_some() && nearby(state, "Speaker").is_some()).await;
    assert_eq!(state["saved"][0]["name"], "Headset", "connected first");
    assert_eq!(state["saved"][0]["deviceType"], "headset");
    assert_eq!(state["saved"][0]["services"], json!(["Audio playback"]));
    let phone = saved(&state, "Phone").unwrap();
    assert_eq!(phone["battery"], 80);
    assert_eq!(phone["canReceiveFiles"], true);
    assert_eq!(phone["adapterName"], "laptop");
    assert_eq!(state["adapters"][0]["name"], "laptop");
    assert_eq!(state["powered"], true);
}

#[tokio::test]
async fn a_device_with_nothing_to_enter_pairs_trusts_and_connects() {
    let (_bus, bluez, mut daemon, _home) = setup("simple").await;
    let device = bluez.add_device(DeviceSpec { address: HEADSET, name: "Headset", ..DeviceSpec::default() }).await.unwrap();
    let reply = daemon.call("bluetooth.pair", json!({ "device": device })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    let calls = bluez.calls();
    let order: Vec<&str> = calls.iter().map(String::as_str).filter(|call| call.starts_with("Pair") || call.starts_with("Trusted") || call.starts_with("Connect")).collect();
    assert_eq!(order, ["Pair Headset", "Trusted true", "Connect Headset"]);
    let state = daemon.wait_bluetooth("it to be saved", |state| saved(state, "Headset").is_some_and(|device| device["connected"] == true)).await;
    assert_eq!(saved(&state, "Headset").unwrap()["trusted"], true);
}

#[tokio::test]
async fn an_already_paired_device_just_connects() {
    let (_bus, bluez, mut daemon, _home) = setup("paired").await;
    let device = bluez.add_device(DeviceSpec { address: HEADSET, name: "Headset", paired: true, ..DeviceSpec::default() }).await.unwrap();
    daemon.call("bluetooth.pair", json!({ "device": device })).await;
    assert!(!bluez.calls().iter().any(|call| call.starts_with("Pair")));
    assert!(bluez.calls().contains(&"Connect Headset".to_string()));
}

#[tokio::test]
async fn a_pin_is_asked_for_and_checked() {
    let (_bus, bluez, mut daemon, _home) = setup("pin").await;
    let device = bluez.add_device(DeviceSpec { address: PHONE, name: "Keyboard", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_pairing(PHONE, Pairing::Pin("4321".to_string()));
    let id = daemon.send("bluetooth.pair", json!({ "device": device })).await;
    let question = prompt(&mut daemon).await;
    assert_eq!(question["kind"], "bluetooth-pin");
    assert_eq!(question["deviceName"], "Keyboard");
    assert_eq!(question["deviceAddress"], PHONE);
    answer(&mut daemon, &question, true, json!({ "pin": "4321" })).await;
    assert_eq!(daemon.wait_response(id).await["ok"], true);
    assert_eq!(bluez.agent_answers(), ["4321"]);
}

#[tokio::test]
async fn a_wrong_pin_comes_back_as_refused() {
    let (_bus, bluez, mut daemon, _home) = setup("wrongpin").await;
    let device = bluez.add_device(DeviceSpec { address: PHONE, name: "Keyboard", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_pairing(PHONE, Pairing::Pin("4321".to_string()));
    let id = daemon.send("bluetooth.pair", json!({ "device": device })).await;
    let question = prompt(&mut daemon).await;
    answer(&mut daemon, &question, true, json!({ "pin": "0000" })).await;
    let reply = daemon.wait_response(id).await;
    assert_eq!(reply["error"]["code"], "wrong_secret");
    assert_eq!(reply["error"]["message"], "The device refused the pairing");
    assert!(!bluez.calls().iter().any(|call| call.starts_with("Connect")));
    // The real error, not a guess from a timer
}

#[tokio::test]
async fn a_passkey_is_asked_for_as_a_number() {
    let (_bus, bluez, mut daemon, _home) = setup("passkey").await;
    let device = bluez.add_device(DeviceSpec { address: PHONE, name: "Kb", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_pairing(PHONE, Pairing::Passkey(123));
    let id = daemon.send("bluetooth.pair", json!({ "device": device })).await;
    let question = prompt(&mut daemon).await;
    assert_eq!(question["kind"], "bluetooth-passkey");
    answer(&mut daemon, &question, true, json!({ "passkey": "000123" })).await;
    assert_eq!(daemon.wait_response(id).await["ok"], true);
}

#[tokio::test]
async fn something_other_than_a_number_is_rejected_for_a_passkey() {
    let (_bus, bluez, mut daemon, _home) = setup("badpasskey").await;
    let device = bluez.add_device(DeviceSpec { address: PHONE, name: "Kb", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_pairing(PHONE, Pairing::Passkey(123));
    let id = daemon.send("bluetooth.pair", json!({ "device": device })).await;
    let question = prompt(&mut daemon).await;
    answer(&mut daemon, &question, true, json!({ "passkey": "letters" })).await;
    assert_eq!(daemon.wait_response(id).await["error"]["code"], "wrong_secret");
}

#[tokio::test]
async fn numbers_that_must_match_are_shown_with_leading_zeros() {
    let (_bus, bluez, mut daemon, _home) = setup("confirm").await;
    let device = bluez.add_device(DeviceSpec { address: PHONE, name: "Phone", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_pairing(PHONE, Pairing::Confirm(42));
    let id = daemon.send("bluetooth.pair", json!({ "device": device })).await;
    let question = prompt(&mut daemon).await;
    assert_eq!(question["kind"], "bluetooth-confirm");
    assert_eq!(question["code"], "000042");
    answer(&mut daemon, &question, true, json!({})).await;
    assert_eq!(daemon.wait_response(id).await["ok"], true);
}

#[tokio::test]
async fn saying_the_numbers_dont_match_stops_the_pairing() {
    let (_bus, bluez, mut daemon, _home) = setup("nomatch").await;
    let device = bluez.add_device(DeviceSpec { address: PHONE, name: "Phone", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_pairing(PHONE, Pairing::Confirm(42));
    let id = daemon.send("bluetooth.pair", json!({ "device": device })).await;
    let question = prompt(&mut daemon).await;
    answer(&mut daemon, &question, false, json!({})).await;
    assert_eq!(daemon.wait_response(id).await["error"]["code"], "wrong_secret");
    assert!(!bluez.calls().iter().any(|call| call.starts_with("Connect")));
}

#[tokio::test]
async fn a_code_to_type_on_the_device_is_shown_until_it_has_paired() {
    let (_bus, bluez, mut daemon, _home) = setup("show").await;
    let device = bluez.add_device(DeviceSpec { address: PHONE, name: "Kb", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_pairing(PHONE, Pairing::ShowPasskey(7));
    let id = daemon.send("bluetooth.pair", json!({ "device": device })).await;
    let question = prompt(&mut daemon).await;
    assert_eq!(question["kind"], "bluetooth-show-code");
    assert_eq!(question["code"], "000007");
    assert_eq!(daemon.wait_response(id).await["ok"], true);
    daemon.wait_message("the note to go", |message| message["name"] == "promptWithdrawn" && message["data"]["id"] == question["id"]).await;
}

#[tokio::test]
async fn a_pin_to_type_on_the_device_is_shown_as_is() {
    let (_bus, bluez, mut daemon, _home) = setup("showpin").await;
    let device = bluez.add_device(DeviceSpec { address: PHONE, name: "Kb", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_pairing(PHONE, Pairing::ShowPin("0042".to_string()));
    let id = daemon.send("bluetooth.pair", json!({ "device": device })).await;
    let question = prompt(&mut daemon).await;
    assert_eq!(question["code"], "0042");
    daemon.wait_response(id).await;
}

#[tokio::test]
async fn allowing_a_device_can_be_declined() {
    let (_bus, bluez, mut daemon, _home) = setup("authorize").await;
    let device = bluez.add_device(DeviceSpec { address: PHONE, name: "Phone", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_pairing(PHONE, Pairing::Authorize);
    let id = daemon.send("bluetooth.pair", json!({ "device": device })).await;
    let question = prompt(&mut daemon).await;
    assert_eq!(question["kind"], "bluetooth-authorize");
    answer(&mut daemon, &question, false, json!({})).await;
    assert_eq!(daemon.wait_response(id).await["error"]["code"], "wrong_secret");
}

#[tokio::test]
async fn bluez_giving_up_takes_the_question_away() {
    let (_bus, bluez, mut daemon, _home) = setup("cancel").await;
    let device = bluez.add_device(DeviceSpec { address: PHONE, name: "Kb", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_pairing(PHONE, Pairing::Pin("1".to_string()));
    let id = daemon.send("bluetooth.pair", json!({ "device": device })).await;
    let question = prompt(&mut daemon).await;
    bluez.agent_cancel().await.unwrap();
    daemon.wait_message("the dialog to close", |message| message["name"] == "promptWithdrawn" && message["data"]["id"] == question["id"]).await;
    assert_eq!(daemon.wait_response(id).await["error"]["code"], "canceled");
}

#[tokio::test]
async fn pairing_errors_read_as_what_happened() {
    let (_bus, bluez, mut daemon, _home) = setup("errors").await;
    for (index, (name, code)) in [("AuthenticationFailed", "wrong_secret"), ("AuthenticationCanceled", "canceled"), ("AuthenticationTimeout", "timeout"), ("ConnectionAttemptFailed", "timeout"), ("InProgress", "conflict"), ("Failed", "failed")].iter().enumerate() {
        let address = format!("00:00:00:00:00:{index:02}");
        let device = bluez.add_device(DeviceSpec { address: &address, name: "D", ..DeviceSpec::default() }).await.unwrap();
        bluez.set_pairing(&address, Pairing::Fails(name));
        let reply = daemon.call("bluetooth.pair", json!({ "device": device })).await;
        assert_eq!(reply["error"]["code"], *code, "{name}: {reply}");
    }
}

#[tokio::test]
async fn a_connection_that_fails_after_pairing_says_so_and_stays_paired() {
    let (_bus, bluez, mut daemon, _home) = setup("connectfail").await;
    let device = bluez.add_device(DeviceSpec { address: HEADSET, name: "Headset", ..DeviceSpec::default() }).await.unwrap();
    bluez.set_connect_failure(HEADSET, "ConnectionAttemptFailed");
    let reply = daemon.call("bluetooth.pair", json!({ "device": device })).await;
    assert_eq!(reply["error"]["code"], "timeout");
    daemon.wait_bluetooth("it to stay paired", |state| saved(state, "Headset").is_some_and(|device| device["paired"] == true && device["connected"] == false)).await;
}

#[tokio::test]
async fn devices_can_be_connected_renamed_trusted_blocked_and_forgotten() {
    let (_bus, bluez, mut daemon, _home) = setup("actions").await;
    let device = bluez.add_device(DeviceSpec { address: HEADSET, name: "Headset", paired: true, ..DeviceSpec::default() }).await.unwrap();
    assert_eq!(daemon.call("bluetooth.connect", json!({ "device": device })).await["ok"], true);
    daemon.wait_bluetooth("connected", |state| saved(state, "Headset").is_some_and(|row| row["connected"] == true)).await;
    assert_eq!(daemon.call("bluetooth.disconnect", json!({ "device": device })).await["ok"], true);
    daemon.wait_bluetooth("disconnected", |state| saved(state, "Headset").is_some_and(|row| row["connected"] == false)).await;
    assert_eq!(daemon.call("bluetooth.rename", json!({ "device": device, "name": "My headset" })).await["ok"], true);
    assert_eq!(daemon.call("bluetooth.setTrusted", json!({ "device": device, "value": false })).await["ok"], true);
    assert_eq!(daemon.call("bluetooth.setBlocked", json!({ "device": device, "value": true })).await["ok"], true);
    let state = daemon.call("ping", Value::Null).await;
    assert_eq!(state["result"], "pong");
    assert_eq!(daemon.call("bluetooth.forget", json!({ "device": device })).await["ok"], true);
    assert!(bluez.calls().contains(&format!("RemoveDevice {device}")));
    daemon.wait_bluetooth("it to go", |state| saved(state, "My headset").is_none() && state["available"] == true).await;
    // Forgetting one that's gone says so
    assert_eq!(daemon.call("bluetooth.forget", json!({ "device": device })).await["ok"], false);
}

#[tokio::test]
async fn the_switch_and_adapter_settings_reach_the_service() {
    let (_bus, bluez, mut daemon, _home) = setup("adapter").await;
    assert_eq!(daemon.call("bluetooth.setEnabled", json!({ "enabled": false })).await["ok"], true);
    assert!(bluez.calls().contains(&"Powered false".to_string()));
    daemon.wait_bluetooth("off", |state| state["powered"] == false).await;
    assert_eq!(daemon.call("bluetooth.setEnabled", json!({ "enabled": true })).await["ok"], true);
    let stand_in = common::safe_path().split(':').next().unwrap().to_string();
    assert!(std::fs::read_to_string(format!("{stand_in}/rfkill.log")).unwrap().contains("unblock bluetooth"), "the radio is unblocked first, here by the stand-in");
    let adapter = "/org/bluez/hci0";
    assert_eq!(daemon.call("bluetooth.setAdapterName", json!({ "adapter": adapter, "name": "desk" })).await["ok"], true);
    assert_eq!(daemon.call("bluetooth.setDiscoverableTimeout", json!({ "adapter": adapter, "seconds": 60 })).await["ok"], true);
    assert_eq!(daemon.call("bluetooth.setDiscoverable", json!({ "adapter": adapter, "value": true })).await["ok"], true);
    let state = daemon.wait_bluetooth("the new settings", |state| state["adapters"][0]["name"] == "desk" && state["adapters"][0]["discoverable"] == true).await;
    assert_eq!(state["adapters"][0]["discoverableTimeout"], 60);
    assert_eq!(state["adapters"][0]["pairable"], true, "being found goes with accepting pairing");
}

#[tokio::test]
async fn looking_for_devices_starts_and_stops_and_doing_either_twice_is_fine() {
    let (_bus, _bluez, mut daemon, _home) = setup("discovery").await;
    assert_eq!(daemon.call("bluetooth.setDiscovering", json!({ "enabled": true })).await["ok"], true);
    daemon.wait_bluetooth("looking", |state| state["discovering"] == true).await;
    assert_eq!(daemon.call("bluetooth.setDiscovering", json!({ "enabled": false })).await["ok"], true);
    daemon.wait_bluetooth("stopped", |state| state["discovering"] == false && state["available"] == true).await;
    let reply = daemon.call("bluetooth.setDiscovering", json!({ "enabled": false })).await;
    assert_eq!(reply["ok"], true, "{reply}");
}

#[tokio::test]
async fn it_notices_bluez_going_and_coming_back_and_registers_again() {
    let bus = TestBus::start().unwrap();
    let bluez = FakeBluez::start(&bus).await.unwrap();
    let home = TempHome::new("restart");
    let mut daemon = Daemon::start_in(&bus, &home.path, &["--agents"], None).await;
    wait_agent(&bluez).await;
    daemon.wait_bluetooth("the adapter", |state| state["available"] == true).await;
    bluez.stop().await.unwrap();
    daemon.wait_bluetooth("it to go", |state| state["available"] == false).await;
    let bluez = FakeBluez::start(&bus).await.unwrap();
    wait_agent(&bluez).await;
    daemon.wait_bluetooth("it to return", |state| state["available"] == true).await;
}

#[tokio::test]
async fn the_settings_process_doesnt_register_an_agent() {
    let bus = TestBus::start().unwrap();
    let bluez = FakeBluez::start(&bus).await.unwrap();
    let home = TempHome::new("noagent");
    let mut daemon = Daemon::start_in(&bus, &home.path, &[], None).await;
    daemon.wait_bluetooth("the adapter", |state| state["available"] == true).await;
    assert!(!bluez.agent_registered());
}

#[tokio::test]
async fn a_blocked_radio_is_reported() {
    let bus = TestBus::start().unwrap();
    let _bluez = FakeBluez::start(&bus).await.unwrap();
    let home = TempHome::new("rfkill");
    let rfkill = home.path.join("rfkill");
    let radio = rfkill.join("rfkill0");
    std::fs::create_dir_all(&radio).unwrap();
    std::fs::write(radio.join("type"), "bluetooth\n").unwrap();
    std::fs::write(radio.join("soft"), "1\n").unwrap();
    std::fs::write(radio.join("hard"), "0\n").unwrap();
    let mut daemon = Daemon::start_in(&bus, &home.path, &[], Some(&rfkill)).await;
    let state = daemon.wait_bluetooth("the state", |state| state["available"] == true).await;
    assert_eq!(state["softBlocked"], true);
    assert_eq!(state["hardBlocked"], false);
}

// ---- files ----

async fn setup_files(name: &str) -> (TestBus, FakeBluez, FakeObex, Daemon, TempHome) {
    let bus = TestBus::start().unwrap();
    let bluez = FakeBluez::start(&bus).await.unwrap();
    let obex = FakeObex::start(&bus).await.unwrap();
    let home = TempHome::new(name);
    let mut daemon = Daemon::start_in(&bus, &home.path, &["--agents"], None).await;
    wait_agent(&bluez).await;
    for _ in 0..150 {
        if obex.agent_registered() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert!(obex.agent_registered());
    daemon.wait_bluetooth("the adapter", |state| state["available"] == true).await;
    let folder = home.path.join("Received");
    let reply = daemon.call("bluetooth.configure", json!({ "onLogin": "remember", "receivePolicy": "ask", "receiveFolder": folder })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    (bus, bluez, obex, daemon, home)
}

#[tokio::test]
async fn a_file_is_offered_and_lands_in_the_folder() {
    let (_bus, bluez, obex, mut daemon, home) = setup_files("receive").await;
    bluez.add_device(DeviceSpec { address: PHONE, name: "Phone", paired: true, ..DeviceSpec::default() }).await.unwrap();
    let incoming = tokio::spawn(async move { obex.incoming(PHONE, "photo.jpg", b"picture", false).await.map(|target| (target, obex)) });
    let question = prompt(&mut daemon).await;
    assert_eq!(question["kind"], "bluetooth-file");
    assert_eq!(question["fileName"], "photo.jpg");
    assert_eq!(question["fileSize"], 7);
    assert_eq!(question["deviceName"], "Phone");
    answer(&mut daemon, &question, true, json!({})).await;
    let (temporary, _obex) = incoming.await.unwrap().unwrap();
    assert!(temporary.contains("/cache/obexd/"), "{temporary}");
    let done = daemon.wait_message("the result", |message| message["name"] == "fileReceived").await;
    assert_eq!(done["data"]["ok"], true);
    let target = home.path.join("Received/photo.jpg");
    assert_eq!(done["data"]["path"], target.display().to_string());
    assert_eq!(std::fs::read(&target).unwrap(), b"picture");
    assert!(!std::path::Path::new(&temporary).exists(), "the temporary copy is gone");
}

#[tokio::test]
async fn a_declined_file_is_refused() {
    let (_bus, _bluez, obex, mut daemon, home) = setup_files("declined").await;
    let incoming = tokio::spawn(async move { obex.incoming(PHONE, "photo.jpg", b"x", false).await });
    let question = prompt(&mut daemon).await;
    answer(&mut daemon, &question, false, json!({})).await;
    assert!(incoming.await.unwrap().unwrap_err().contains("Rejected"));
    assert!(!home.path.join("Received").exists());
}

#[tokio::test]
async fn trusted_devices_can_send_without_asking_and_others_are_still_asked() {
    let (_bus, bluez, obex, mut daemon, home) = setup_files("trusted").await;
    let folder = home.path.join("Received");
    daemon.call("bluetooth.configure", json!({ "onLogin": "remember", "receivePolicy": "trusted", "receiveFolder": folder })).await;
    bluez.add_device(DeviceSpec { address: PHONE, name: "Phone", paired: true, ..DeviceSpec::default() }).await.unwrap();
    let obex = std::sync::Arc::new(obex);
    obex.incoming(PHONE, "from-trusted.txt", b"x", false).await.unwrap();
    daemon.wait_message("the result", |message| message["name"] == "fileReceived").await;
    assert!(folder.join("from-trusted.txt").exists());

    let asker = std::sync::Arc::clone(&obex);
    let stranger = tokio::spawn(async move { asker.incoming("99:99:99:99:99:99", "unknown.txt", b"x", false).await });
    let question = prompt(&mut daemon).await;
    assert_eq!(question["fileName"], "unknown.txt");
    answer(&mut daemon, &question, false, json!({})).await;
    assert!(stranger.await.unwrap().is_err());
}

#[tokio::test]
async fn always_means_no_questions() {
    let (_bus, _bluez, obex, mut daemon, home) = setup_files("always").await;
    let folder = home.path.join("Received");
    daemon.call("bluetooth.configure", json!({ "onLogin": "remember", "receivePolicy": "always", "receiveFolder": folder })).await;
    obex.incoming(PHONE, "a.txt", b"x", false).await.unwrap();
    daemon.wait_message("the result", |message| message["name"] == "fileReceived").await;
    assert!(folder.join("a.txt").exists());
}

#[tokio::test]
async fn a_batch_from_one_device_asks_once() {
    let (_bus, _bluez, obex, mut daemon, home) = setup_files("batch").await;
    let obex = std::sync::Arc::new(obex);
    let first = std::sync::Arc::clone(&obex);
    let incoming = tokio::spawn(async move { first.incoming(PHONE, "1.txt", b"x", false).await });
    let question = prompt(&mut daemon).await;
    answer(&mut daemon, &question, true, json!({})).await;
    incoming.await.unwrap().unwrap();
    daemon.wait_message("the first file", |message| message["name"] == "fileReceived").await;
    obex.incoming(PHONE, "2.txt", b"y", false).await.unwrap();
    daemon.wait_message("the second file", |message| message["name"] == "fileReceived").await;
    assert!(home.path.join("Received/2.txt").exists());
}

#[tokio::test]
async fn a_taken_name_gets_a_number_and_a_devious_one_stays_in_the_folder() {
    let (_bus, _bluez, obex, mut daemon, home) = setup_files("names").await;
    let folder = home.path.join("Received");
    daemon.call("bluetooth.configure", json!({ "onLogin": "remember", "receivePolicy": "always", "receiveFolder": folder })).await;
    std::fs::create_dir_all(&folder).unwrap();
    std::fs::write(folder.join("a.txt"), "old").unwrap();
    obex.incoming(PHONE, "a.txt", b"new", false).await.unwrap();
    let done = daemon.wait_message("the result", |message| message["name"] == "fileReceived").await;
    assert_eq!(done["data"]["path"], folder.join("a (1).txt").display().to_string());
    assert_eq!(std::fs::read(folder.join("a.txt")).unwrap(), b"old");

    obex.incoming(PHONE, "../../../outside.txt", b"x", false).await.unwrap();
    let done = daemon.wait_message("the result", |message| message["name"] == "fileReceived" && message["data"]["name"] == "outside.txt").await;
    assert_eq!(done["data"]["path"], folder.join("outside.txt").display().to_string());
    assert!(!home.path.join("outside.txt").exists());
}

#[tokio::test]
async fn a_failed_transfer_leaves_nothing_behind() {
    let (_bus, _bluez, obex, mut daemon, home) = setup_files("failed").await;
    let folder = home.path.join("Received");
    daemon.call("bluetooth.configure", json!({ "onLogin": "remember", "receivePolicy": "always", "receiveFolder": folder })).await;
    let temporary = obex.incoming(PHONE, "broken.txt", b"x", true).await.unwrap();
    let done = daemon.wait_message("the result", |message| message["name"] == "fileReceived").await;
    assert_eq!(done["data"]["ok"], false);
    assert!(!folder.join("broken.txt").exists());
    assert!(!std::path::Path::new(&temporary).exists());
}

#[tokio::test]
async fn files_go_out_one_by_one_and_the_session_closes() {
    let (_bus, _bluez, obex, mut daemon, home) = setup_files("send").await;
    let a = home.path.join("a.txt");
    let b = home.path.join("b.txt");
    std::fs::write(&a, "hello").unwrap();
    std::fs::write(&b, "hi").unwrap();
    let id = daemon.send("bluetooth.sendFiles", json!({ "address": PHONE, "files": [a, b] })).await;
    let started = daemon.wait_message("the start", |message| message["name"] == "transferStarted").await;
    assert_eq!(started["data"]["size"], 5);
    let reply = daemon.wait_response(id).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(obex.sent(), vec![(PHONE.to_string(), a.display().to_string()), (PHONE.to_string(), b.display().to_string())]);
    assert_eq!(obex.sessions_open(), 0);
}

#[tokio::test]
async fn a_refused_file_is_reported_and_the_session_still_closes() {
    let (_bus, _bluez, obex, mut daemon, home) = setup_files("refused").await;
    obex.set_refuse_sends(true);
    let file = home.path.join("a.txt");
    std::fs::write(&file, "x").unwrap();
    let reply = daemon.call("bluetooth.sendFiles", json!({ "address": PHONE, "files": [file] })).await;
    assert_eq!(reply["error"]["message"], "The device didn't take the file");
    assert_eq!(obex.sessions_open(), 0);
}

#[tokio::test]
async fn without_obexd_sending_says_its_not_there() {
    let (_bus, _bluez, mut daemon, home) = setup("noobex").await;
    let file = home.path.join("a.txt");
    std::fs::write(&file, "x").unwrap();
    let reply = daemon.call("bluetooth.sendFiles", json!({ "address": PHONE, "files": [file] })).await;
    assert_eq!(reply["error"]["code"], "unavailable");
}

// ---- state across logins ----

async fn start_with_mode(bus: &TestBus, home: &TempHome, mode: &str) -> Daemon {
    let mut daemon = Daemon::start_in(bus, &home.path, &["--agents"], None).await;
    daemon.wait_bluetooth("the adapter", |state| state["available"] == true).await;
    let reply = daemon.call("bluetooth.configure", json!({ "onLogin": mode, "receivePolicy": "ask", "receiveFolder": home.path })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    daemon
}

fn write_saved(home: &TempHome, state: Value) {
    let directory = home.path.join("state/velora");
    std::fs::create_dir_all(&directory).unwrap();
    std::fs::write(directory.join("bluetooth-state.json"), state.to_string()).unwrap();
}

#[tokio::test]
async fn remember_restores_power_and_reconnects() {
    let bus = TestBus::start().unwrap();
    let bluez = FakeBluez::start(&bus).await.unwrap();
    bluez.add_device(DeviceSpec { address: HEADSET, name: "Headset", paired: true, ..DeviceSpec::default() }).await.unwrap();
    let home = TempHome::new("remember");
    write_saved(&home, json!({ "powered": { "AA:AA:AA:AA:AA:AA": true }, "connected": [HEADSET] }));
    let mut daemon = start_with_mode(&bus, &home, "remember").await;
    daemon.wait_bluetooth("the reconnection", |state| saved(state, "Headset").is_some_and(|device| device["connected"] == true)).await;
}

#[tokio::test]
async fn off_at_login_turns_it_off_and_connects_nothing() {
    let bus = TestBus::start().unwrap();
    let bluez = FakeBluez::start(&bus).await.unwrap();
    bluez.add_device(DeviceSpec { address: HEADSET, name: "Headset", paired: true, ..DeviceSpec::default() }).await.unwrap();
    let home = TempHome::new("off");
    write_saved(&home, json!({ "powered": { "AA:AA:AA:AA:AA:AA": true }, "connected": [HEADSET] }));
    let mut daemon = start_with_mode(&bus, &home, "off").await;
    daemon.wait_bluetooth("it to be off", |state| state["powered"] == false && state["available"] == true).await;
    assert!(!bluez.calls().iter().any(|call| call.starts_with("Connect")));
}

#[tokio::test]
async fn on_at_login_turns_it_on_whatever_was_left() {
    let bus = TestBus::start().unwrap();
    let bluez = FakeBluez::start(&bus).await.unwrap();
    bluez.set_adapter_powered(false).await.unwrap();
    let home = TempHome::new("on");
    write_saved(&home, json!({ "powered": { "AA:AA:AA:AA:AA:AA": false }, "connected": [] }));
    let mut daemon = start_with_mode(&bus, &home, "on").await;
    daemon.wait_bluetooth("it to be on", |state| state["powered"] == true).await;
}

#[tokio::test]
async fn how_it_is_left_is_saved_for_next_time() {
    let bus = TestBus::start().unwrap();
    let bluez = FakeBluez::start(&bus).await.unwrap();
    bluez.add_device(DeviceSpec { address: HEADSET, name: "Headset", paired: true, connected: true, ..DeviceSpec::default() }).await.unwrap();
    let home = TempHome::new("saved");
    let _daemon = start_with_mode(&bus, &home, "remember").await;
    let file = home.path.join("state/velora/bluetooth-state.json");
    for _ in 0..200 {
        if std::fs::read_to_string(&file).is_ok_and(|text| text.contains(HEADSET)) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    let state: Value = serde_json::from_str(&std::fs::read_to_string(&file).unwrap()).unwrap();
    assert_eq!(state, json!({ "powered": { "AA:AA:AA:AA:AA:AA": true }, "connected": [HEADSET] }));
}

#[tokio::test]
async fn devices_connected_before_sleep_come_back_after() {
    let bus = TestBus::start().unwrap();
    let bluez = FakeBluez::start(&bus).await.unwrap();
    let logind = FakeLogind::start(&bus).await.unwrap();
    bluez.add_device(DeviceSpec { address: HEADSET, name: "Headset", paired: true, connected: true, ..DeviceSpec::default() }).await.unwrap();
    let home = TempHome::new("sleep");
    let mut daemon = start_with_mode(&bus, &home, "remember").await;
    let file = home.path.join("state/velora/bluetooth-state.json");
    for _ in 0..200 {
        if std::fs::read_to_string(&file).is_ok_and(|text| text.contains(HEADSET)) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    logind.sleep(true).await.unwrap();
    tokio::time::sleep(Duration::from_millis(100)).await;
    // The radio drops as the machine goes down; that isn't how it should be remembered
    bluez.disconnect_device(HEADSET).await.unwrap();
    daemon.wait_bluetooth("it to drop", |state| saved(state, "Headset").is_some_and(|device| device["connected"] == false)).await;
    logind.sleep(false).await.unwrap();
    daemon.wait_bluetooth("it to come back", |state| saved(state, "Headset").is_some_and(|device| device["connected"] == true)).await;
}

// ---- airplane mode ----

#[tokio::test]
async fn airplane_mode_turns_radios_off_and_brings_back_only_what_was_on() {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let bluez = FakeBluez::start(&bus).await.unwrap();
    let home = TempHome::new("airplane");
    let mut daemon = Daemon::start_in(&bus, &home.path, &[], None).await;
    daemon.wait_network("the service", |state| state["available"] == true).await;
    assert_eq!(daemon.last_network["airplaneMode"], false);

    assert_eq!(daemon.call("network.setAirplaneMode", json!({ "enabled": true })).await["ok"], true);
    assert!(nm.calls().contains(&"SetWirelessEnabled false".to_string()));
    assert!(nm.calls().contains(&"SetWwanEnabled false".to_string()));
    assert!(bluez.calls().contains(&"Powered false".to_string()));
    daemon.wait_network("the mode", |state| state["airplaneMode"] == true && state["wifiEnabled"] == false).await;

    // Asked again, it doesn't forget what was on
    assert_eq!(daemon.call("network.setAirplaneMode", json!({ "enabled": true })).await["ok"], true);

    assert_eq!(daemon.call("network.setAirplaneMode", json!({ "enabled": false })).await["ok"], true);
    assert!(nm.calls().contains(&"SetWirelessEnabled true".to_string()));
    assert!(!nm.calls().contains(&"SetWwanEnabled true".to_string()), "it was off before");
    assert!(bluez.calls().contains(&"Powered true".to_string()));
    daemon.wait_network("the mode to end", |state| state["airplaneMode"] == false && state["wifiEnabled"] == true).await;
}

#[tokio::test]
async fn airplane_mode_works_without_bluetooth() {
    let bus = TestBus::start().unwrap();
    let _nm = FakeNm::start(&bus).await.unwrap();
    let home = TempHome::new("airplane2");
    let mut daemon = Daemon::start_in(&bus, &home.path, &[], None).await;
    daemon.wait_network("the service", |state| state["available"] == true).await;
    assert_eq!(daemon.call("network.setAirplaneMode", json!({ "enabled": true })).await["ok"], true);
    assert_eq!(daemon.call("network.setAirplaneMode", json!({ "enabled": false })).await["ok"], true);
}

#[tokio::test]
async fn device_path_helper_matches_bluez_naming() {
    assert_eq!(device_path("AA:BB:CC:DD:EE:FF"), "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF");
}
