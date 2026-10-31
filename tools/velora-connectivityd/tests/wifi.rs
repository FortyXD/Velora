//! Owned Wi-Fi operations on a private bus: no test changes the machine's network.
mod common;

use common::Daemon;
use serde_json::{json, Value};
use velora_connectivity_fakes::bus::TestBus;
use velora_connectivity_fakes::nm::{value, FakeNm, Outcome, Props, RSN_PSK};

const SECURITY: &str = "802-11-wireless-security";

async fn setup() -> (TestBus, FakeNm, Daemon) {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    nm.add_access_point(b"Home", "00:00:00:00:00:01", 70, RSN_PSK).await.unwrap();
    let mut daemon = Daemon::start(&bus, &[]).await;
    daemon.wait_network("Home", |state| state["networks"].as_array().is_some_and(|rows| rows.iter().any(|row| row["ssid"] == "Home"))).await;
    (bus, nm, daemon)
}

async fn prompt(daemon: &mut Daemon) -> Value {
    daemon.wait_message("a scoped password prompt", |message| message["type"] == "event" && message["name"] == "wifiPassword").await["data"].clone()
}

fn no_disruption(nm: &FakeNm) {
    assert!(!nm.calls().iter().any(|call| call == "DeactivateConnection" || call.starts_with("Delete ")), "{:?}", nm.calls());
}

#[tokio::test]
async fn a_new_profile_is_persisted_only_after_success() {
    let (_bus, nm, mut daemon) = setup().await;
    let reply = daemon.call("network.connectWifi", json!({"operation":"new", "ssid":"Home", "password":"marker-password"})).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(reply["result"]["saved"], true);
    assert_eq!(nm.saved_profile_count(), 1);
    assert!(nm.calls().contains(&"AddAndActivateConnection2 persist=memory".into()));
    assert!(nm.calls().contains(&"Update2 flags=1".into()));
    assert!(!daemon.transcript.iter().any(|line| line.contains("marker-password")));
    no_disruption(&nm);
    assert_eq!(daemon.call("network.cancelWifi", json!({"operation":"new"})).await["result"]["canceled"], false);
}

#[tokio::test]
async fn failure_leaves_a_new_profile_unsaved_and_autoconnect_off() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.set_outcome(Outcome::Fail { device_reason: 8, active_reason: 3 });
    let reply = daemon.call("network.connectWifi", json!({"operation":"failure", "ssid":"Home", "password":"bad-password"})).await;
    assert_eq!(reply["error"]["code"], "wrong_secret", "{reply}");
    assert_eq!(nm.saved_profile_count(), 0);
    let state = daemon.wait_network("the temporary profile", |state| state["profiles"].as_array().is_some_and(|rows| !rows.is_empty())).await;
    let uuid = state["profiles"][0]["uuid"].as_str().unwrap();
    assert!(!nm.setting(uuid, "connection", "autoconnect").unwrap().downcast_ref::<bool>().unwrap());
    no_disruption(&nm);
}

#[tokio::test]
async fn a_failed_replacement_restores_the_existing_profile_and_password() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("saved", b"Home", "wpa-psk", "old-password", 100).await.unwrap();
    nm.set_outcome(Outcome::Fail { device_reason: 8, active_reason: 3 });
    let reply = daemon.call("network.connectWifi", json!({"operation":"replace", "ssid":"Home", "uuid":"saved", "password":"new-password"})).await;
    assert_eq!(reply["error"]["code"], "wrong_secret", "{reply}");
    assert_eq!(nm.profile_count(), 1);
    assert_eq!(nm.saved_secret("saved", SECURITY, "psk").as_deref(), Some("old-password"));
    assert_eq!(nm.secret("saved", SECURITY, "psk").as_deref(), Some("old-password"));
    no_disruption(&nm);
}

#[tokio::test]
async fn a_successful_replacement_keeps_the_uuid() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("saved", b"Home", "wpa-psk", "old-password", 100).await.unwrap();
    let reply = daemon.call("network.connectWifi", json!({"operation":"replace", "ssid":"Home", "uuid":"saved", "password":"new-password"})).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(nm.profile_count(), 1);
    assert_eq!(nm.saved_secret("saved", SECURITY, "psk").as_deref(), Some("new-password"));
    no_disruption(&nm);
}

#[tokio::test]
async fn retries_have_distinct_tokens_and_only_the_last_password_is_saved() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.set_outcome(Outcome::AskPassword { requests: 2 });
    let id = daemon.send("network.connectWifi", json!({"operation":"retry", "ssid":"Home"})).await;
    let first = prompt(&mut daemon).await;
    assert_eq!(first["operation"], "retry");
    assert_eq!(first["retry"], false);
    let invalid = daemon.call("network.submitWifiPassword", json!({"operation":"retry", "request": first["request"], "password":"short"})).await;
    assert_eq!(invalid["error"]["code"], "wrong_secret");
    let accepted = daemon.call("network.submitWifiPassword", json!({"operation":"retry", "request": first["request"], "password":"first-password"})).await;
    assert_eq!(accepted["result"]["accepted"], true);
    let second = prompt(&mut daemon).await;
    assert_eq!(second["retry"], true);
    assert_ne!(first["request"], second["request"]);
    assert_eq!(daemon.call("network.submitWifiPassword", json!({"operation":"retry", "request": first["request"], "password":"stale-password"})).await["result"]["accepted"], false);
    assert_eq!(daemon.call("network.submitWifiPassword", json!({"operation":"other", "request": second["request"], "password":"wrong-operation"})).await["result"]["accepted"], false);
    assert_eq!(daemon.call("network.submitWifiPassword", json!({"operation":"retry", "request": second["request"], "password":"final-password"})).await["result"]["accepted"], true);
    assert_eq!(daemon.wait_response(id).await["ok"], true);
    let state = daemon.wait_network("the connected profile", |state| state["wifiConnected"] == true && state["profiles"].as_array().is_some_and(|rows| !rows.is_empty())).await;
    let uuid = state["profiles"][0]["uuid"].as_str().unwrap();
    assert_eq!(nm.saved_secret(uuid, SECURITY, "psk").as_deref(), Some("final-password"));
    assert!(!daemon.transcript.iter().any(|line| line.contains("-password")));
}

#[tokio::test]
async fn canceling_a_prompt_does_not_disconnect_or_accept_a_late_password() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.set_outcome(Outcome::AskPassword { requests: 1 });
    let id = daemon.send("network.connectWifi", json!({"operation":"cancel", "ssid":"Home"})).await;
    let request = prompt(&mut daemon).await;
    assert_eq!(daemon.call("network.cancelWifi", json!({"operation":"cancel"})).await["result"]["canceled"], true);
    assert_eq!(daemon.wait_response(id).await["error"]["code"], "canceled");
    assert_eq!(daemon.call("network.submitWifiPassword", json!({"operation":"cancel", "request":request["request"], "password":"late-password"})).await["result"]["accepted"], false);
    assert_eq!(nm.saved_profile_count(), 0);
    no_disruption(&nm);
}

#[tokio::test]
async fn rejecting_a_password_already_tried_by_networkmanager_prompts_immediately() {
    for saved in [false, true] {
        let (_bus, nm, mut daemon) = setup().await;
        if saved { nm.add_wifi_profile("saved", b"Home", "wpa-psk", "old-password", 1).await.unwrap(); }
        nm.set_outcome(Outcome::AskPassword { requests: 1 });
        let id = daemon.send("network.connectWifi", json!({"operation":"seed", "ssid":"Home", "uuid":if saved {"saved"} else {""}, "password":"bad-password"})).await;
        let request = prompt(&mut daemon).await;
        assert_eq!(request["retry"], true);
        assert_eq!(daemon.call("network.submitWifiPassword", json!({"operation":"seed", "request":request["request"], "password":"good-password"})).await["result"]["accepted"], true);
        assert_eq!(daemon.wait_response(id).await["result"]["saved"], true);
        no_disruption(&nm);
    }
}

#[tokio::test]
async fn stopping_a_wait_rolls_back_a_replacement_without_deactivation() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("saved", b"Home", "wpa-psk", "old-password", 1).await.unwrap();
    nm.set_outcome(Outcome::Wait);
    let id = daemon.send("network.connectWifi", json!({"operation":"wait", "ssid":"Home", "uuid":"saved", "password":"new-password"})).await;
    daemon.wait_network("the activation", |state| state["profiles"].as_array().is_some_and(|rows| rows.iter().any(|row| row["activeState"] == 1))).await;
    assert_eq!(daemon.call("network.cancelWifi", json!({"operation":"wrong"})).await["result"]["canceled"], false);
    let conflict = daemon.call("network.connectWifi", json!({"operation":"parallel", "ssid":"Home"})).await;
    assert_eq!(conflict["error"]["code"], "conflict", "{conflict}");
    assert_eq!(daemon.call("network.cancelWifi", json!({"operation":"wait"})).await["result"]["canceled"], true);
    assert_eq!(daemon.wait_response(id).await["error"]["code"], "canceled");
    assert_eq!(nm.secret("saved", SECURITY, "psk").as_deref(), Some("old-password"));
    no_disruption(&nm);
}

#[tokio::test]
async fn save_refusal_and_concurrent_edits_keep_a_successful_connection() {
    for concurrent in [false, true] {
        let (_bus, nm, mut daemon) = setup().await;
        nm.set_updates_denied(!concurrent);
        nm.set_change_during_secrets(concurrent);
        let reply = daemon.call("network.connectWifi", json!({"operation":"save-warning", "ssid":"Home", "password":"new-password"})).await;
        assert_eq!(reply["ok"], true, "{reply}");
        assert_eq!(reply["result"]["saved"], false, "{reply}");
        assert_eq!(reply["result"]["warning"], "Connected, but the password could not be saved");
        assert_eq!(nm.saved_profile_count(), 0);
        no_disruption(&nm);
    }
}

#[tokio::test]
async fn an_incomplete_saved_profile_is_repaired_without_deletion() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("incomplete", b"Home", "", "", 0).await.unwrap();
    let reply = daemon.call("network.connectWifi", json!({"operation":"repair", "ssid":"Home", "uuid":"incomplete", "password":"new-password"})).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(nm.saved_secret("incomplete", SECURITY, "psk").as_deref(), Some("new-password"));
    assert_eq!(nm.setting("incomplete", SECURITY, "key-mgmt").unwrap().downcast_ref::<&str>().unwrap(), "wpa-psk");
    assert_eq!(nm.profile_count(), 1);
    no_disruption(&nm);
}

#[tokio::test]
async fn hidden_networks_keep_their_exact_name_and_selected_security() {
    for (security, password) in [("none", None), ("sae", Some("x")), ("wpa-psk", Some("new-password"))] {
        let (_bus, nm, mut daemon) = setup().await;
        let mut params = json!({"operation":"hidden", "ssid":"  Hidden  ", "hidden":true, "security":security});
        if let Some(password) = password { params["password"] = json!(password); }
        let reply = daemon.call("network.connectWifi", params).await;
        assert_eq!(reply["ok"], true, "{reply}");
        let state = daemon.wait_network("the hidden profile", |state| state["profiles"].as_array().is_some_and(|rows| !rows.is_empty())).await;
        let uuid = state["profiles"][0]["uuid"].as_str().unwrap();
        assert_eq!(Vec::<u8>::try_from(nm.setting(uuid, "802-11-wireless", "ssid").unwrap()).unwrap(), b"  Hidden  ");
        assert!(nm.setting(uuid, "connection", "autoconnect").unwrap().downcast_ref::<bool>().unwrap());
        assert_eq!(nm.saved_profile_count(), 1);
    }
}

#[tokio::test]
async fn owned_secret_flags_are_preserved_for_psk_and_wep() {
    for (key_mgmt, key, flags) in [("wpa-psk", "psk", "psk-flags"), ("none", "wep-key0", "wep-key-flags")] {
        let (_bus, nm, mut daemon) = setup().await;
        let security = Props::from([("key-mgmt".into(), value(key_mgmt)), (key.into(), value("1234567890")), (flags.into(), value(1u32))]);
        nm.add_secret_profile("owned", b"Home", security).await.unwrap();
        let reply = daemon.call("network.connectWifi", json!({"operation":"owned", "ssid":"Home", "uuid":"owned", "password":"1234567890"})).await;
        assert_eq!(reply["ok"], true, "{reply}");
        assert_eq!(reply["result"]["saved"], false);
        assert_eq!(nm.setting("owned", SECURITY, flags).unwrap().downcast_ref::<u32>().unwrap(), 1);
        assert!(!nm.calls().iter().any(|call| call.starts_with("Update2")));
        no_disruption(&nm);
    }
}

#[tokio::test]
async fn saved_enterprise_profiles_still_activate_without_a_personal_password() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("enterprise", b"Home", "wpa-eap", "", 1).await.unwrap();
    let reply = daemon.call("network.connectWifi", json!({"operation":"enterprise", "ssid":"Home", "uuid":"enterprise"})).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert!(!nm.calls().iter().any(|call| call.starts_with("Update2")));
}

#[tokio::test]
async fn invalid_requests_do_not_create_profiles() {
    let (_bus, nm, mut daemon) = setup().await;
    for (params, code) in [
        (json!({"operation":"", "ssid":"Home"}), "invalid"),
        (json!({"operation":"bad id", "ssid":"Home"}), "invalid"),
        (json!({"operation":"absent", "ssid":"Absent"}), "not_found"),
        (json!({"operation":"bad", "ssid":"Home", "password":"short"}), "wrong_secret"),
        (json!({"operation":"bad", "ssid":"Home", "password":"12345678\u{0000}"}), "wrong_secret"),
        (json!({"operation":"bad", "ssid":"Hidden", "hidden":true, "security":"bad"}), "invalid"),
        (json!({"operation":"bad", "ssid":"Home", "uuid":"missing"}), "invalid"),
    ] {
        let reply = daemon.call("network.connectWifi", params).await;
        assert_eq!(reply["error"]["code"], code, "{reply}");
    }
    assert_eq!(nm.profile_count(), 0);
}

#[tokio::test]
async fn the_scoped_agent_rejects_other_callers_and_never_saves_or_deletes_secrets() {
    let (bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("saved", b"Home", "wpa-psk", "old-password", 1).await.unwrap();
    nm.set_outcome(Outcome::Wait);
    let id = daemon.send("network.connectWifi", json!({"operation":"scoped", "ssid":"Home", "uuid":"saved"})).await;
    daemon.wait_network("the activation", |state| state["profiles"].as_array().is_some_and(|rows| rows.iter().any(|row| row["activeState"] == 1))).await;
    let settings = std::collections::HashMap::from([("connection".into(), Props::from([("uuid".into(), value("saved"))]))]);
    let other = std::collections::HashMap::from([("connection".into(), Props::from([("uuid".into(), value("other"))]))]);
    assert!(nm.ask_agent(&other, SECURITY, vec![], 1).await.is_err());
    assert!(nm.ask_agent(&settings, "802-1x", vec![], 1).await.is_err());
    assert!(nm.ask_agent(&settings, SECURITY, vec![], 0).await.is_err());
    assert!(nm.agent_save(&settings).await.is_err());
    assert!(nm.agent_delete(&settings).await.is_err());
    let attacker = bus.connect().await.unwrap();
    let path = zbus::ObjectPath::try_from("/org/freedesktop/NetworkManager/Settings/1").unwrap();
    let reply = attacker.call_method(nm.agent_destination().as_deref(), "/org/freedesktop/NetworkManager/SecretAgent", Some("org.freedesktop.NetworkManager.SecretAgent"), "GetSecrets", &(&settings, &path, SECURITY, Vec::<String>::new(), 1u32)).await;
    assert!(reply.is_err());
    // A legitimate canceled request closes only the agent's pending reply.
    let (reply, ()) = tokio::join!(
        nm.ask_agent(&settings, SECURITY, vec![], 1),
        async {
            prompt(&mut daemon).await;
            nm.cancel_agent_request(SECURITY).await.unwrap();
        }
    );
    assert!(reply.is_err());
    assert_eq!(daemon.call("network.cancelWifi", json!({"operation":"scoped"})).await["result"]["canceled"], true);
    assert_eq!(daemon.wait_response(id).await["error"]["code"], "canceled");
    no_disruption(&nm);
}
