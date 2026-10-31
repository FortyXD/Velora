//! The daemon against a stand-in NetworkManager on a real, private message bus.

mod common;

use common::Daemon;
use serde_json::{json, Value};
use velora_connectivity_fakes::bus::TestBus;
use velora_connectivity_fakes::nm::{FakeNm, Outcome, RSN_PSK, RSN_SAE};

async fn setup() -> (TestBus, FakeNm, Daemon) {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let mut daemon = Daemon::start(&bus, &[]).await;
    let hello = daemon.wait_message("hello", |message| message["type"] == "hello").await;
    assert_eq!(hello, json!({ "type": "hello", "protocol": 1, "agents": false }));
    daemon.wait_network("the first snapshot", |state| state["available"] == true).await;
    (bus, nm, daemon)
}

fn network<'a>(state: &'a Value, ssid: &str) -> Option<&'a Value> {
    state["networks"].as_array()?.iter().find(|network| network["ssid"] == ssid)
}

fn profile<'a>(state: &'a Value, uuid: &str) -> Option<&'a Value> {
    state["profiles"].as_array()?.iter().find(|profile| profile["uuid"] == uuid)
}

#[tokio::test]
async fn it_reports_access_points_and_saved_profiles_with_their_protocols() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_access_point(b"Home", "00:00:00:00:00:01", 70, RSN_PSK).await.unwrap();
    nm.add_access_point(b"Home", "00:00:00:00:00:02", 40, RSN_PSK).await.unwrap();
    nm.add_access_point(b"Office", "00:00:00:00:00:03", 50, RSN_SAE).await.unwrap();
    nm.add_wifi_profile("home-uuid", b"Home", "wpa-psk", "hunter2hunter2", 1000).await.unwrap();
    nm.add_wifi_profile("far-uuid", b"Far", "sae", "elsewhere", 500).await.unwrap();
    let state = daemon
        .wait_network("two networks and two profiles", |state| {
            network(state, "Home").is_some_and(|home| home["savedUuid"] == "home-uuid") && network(state, "Office").is_some() && profile(state, "far-uuid").is_some()
        })
        .await;
    let home = network(&state, "Home").unwrap();
    assert_eq!(home["strength"], 70);
    assert_eq!(home["security"], "WPA2");
    assert_eq!(network(&state, "Office").unwrap()["security"], "WPA3");
    assert_eq!(profile(&state, "far-uuid").unwrap()["securityType"], "sae");
    assert_eq!(profile(&state, "far-uuid").unwrap()["inRange"], false);
    assert_eq!(profile(&state, "home-uuid").unwrap()["inRange"], true);
}

#[tokio::test]
async fn snapshots_never_carry_a_saved_password() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "marker-password-1", 1).await.unwrap();
    daemon.wait_network("the profile", |state| profile(state, "uuid").is_some()).await;
    assert!(!daemon.transcript.iter().any(|line| line.contains("marker-password-1")));
}

#[tokio::test]
async fn activation_waits_for_the_result() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "hunter2hunter2", 1).await.unwrap();
    let reply = daemon.call("network.activate", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert!(reply["result"]["active"].as_str().unwrap().contains("ActiveConnection"));
    let state = daemon.wait_network("the connected state", |state| state["wifiConnected"] == true).await;
    assert_eq!(state["wifiStatus"], "connected");
    assert_eq!(profile(&state, "uuid").unwrap()["activeState"], 2);
}

#[tokio::test]
async fn a_refused_password_comes_back_as_such() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "hunter2hunter2", 1).await.unwrap();
    nm.set_outcome(Outcome::Fail { device_reason: 8, active_reason: 3 });
    let reply = daemon.call("network.activate", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["ok"], false);
    assert_eq!(reply["error"]["code"], "wrong_secret");
}

#[tokio::test]
async fn a_missing_password_and_other_failures_keep_their_meaning() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "hunter2hunter2", 1).await.unwrap();
    nm.set_outcome(Outcome::Fail { device_reason: 7, active_reason: 9 });
    let reply = daemon.call("network.activate", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["error"]["code"], "secrets_required");
    nm.set_outcome(Outcome::Fail { device_reason: 17, active_reason: 3 });
    let reply = daemon.call("network.activate", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["error"]["code"], "failed");
    assert_eq!(reply["error"]["message"], "DHCP failed");
}

#[tokio::test]
async fn a_permission_refusal_is_reported() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "hunter2hunter2", 1).await.unwrap();
    nm.set_outcome(Outcome::Deny);
    let reply = daemon.call("network.activate", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["error"]["code"], "permission_denied");
}

#[tokio::test]
async fn an_unknown_profile_is_reported() {
    let (_bus, _nm, mut daemon) = setup().await;
    let reply = daemon.call("network.activate", json!({ "uuid": "nope" })).await;
    assert_eq!(reply["ok"], false);
    assert_eq!(reply["error"]["code"], "invalid");
}

#[tokio::test]
async fn joining_a_new_network_saves_a_profile_with_the_right_security() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_access_point(b"Home", "00:00:00:00:00:01", 70, RSN_SAE).await.unwrap();
    daemon.wait_network("the network", |state| network(state, "Home").is_some()).await;
    let reply = daemon.call("network.join", json!({ "ssid": "Home", "password": "typed-password" })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert!(nm.calls().contains(&"AddAndActivateConnection2 persist=disk".to_string()));
    let state = daemon.wait_network("the saved profile", |state| state["profiles"].as_array().is_some_and(|rows| !rows.is_empty())).await;
    assert_eq!(state["profiles"][0]["securityType"], "sae");
}

#[tokio::test]
async fn joining_refuses_a_short_password_before_asking_the_service() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_access_point(b"Home", "00:00:00:00:00:01", 70, RSN_PSK).await.unwrap();
    daemon.wait_network("the network", |state| network(state, "Home").is_some()).await;
    let reply = daemon.call("network.join", json!({ "ssid": "Home", "password": "short" })).await;
    assert_eq!(reply["error"]["code"], "wrong_secret");
    assert_eq!(nm.profile_count(), 0);
}

#[tokio::test]
async fn joining_an_absent_network_is_an_error_but_a_hidden_one_goes_through() {
    let (_bus, nm, mut daemon) = setup().await;
    let reply = daemon.call("network.join", json!({ "ssid": "Ghost", "password": "12345678" })).await;
    assert_eq!(reply["error"]["code"], "not_found");
    let reply = daemon.call("network.join", json!({ "ssid": "Ghost", "password": "12345678", "hidden": true })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(nm.profile_count(), 1);
}

#[tokio::test]
async fn changing_a_password_keeps_the_profile_and_connects() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "old-password", 1).await.unwrap();
    let reply = daemon.call("network.changePassword", json!({ "uuid": "uuid", "password": "new-password" })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(nm.secret("uuid", "802-11-wireless-security", "psk").as_deref(), Some("new-password"));
    assert_eq!(nm.profile_count(), 1);
    assert!(nm.calls().contains(&"ActivateConnection".to_string()));
}

#[tokio::test]
async fn forgetting_removes_the_profile() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "x", 1).await.unwrap();
    daemon.wait_network("the profile", |state| profile(state, "uuid").is_some()).await;
    let reply = daemon.call("network.forget", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    daemon.wait_network("the profile to go", |state| profile(state, "uuid").is_none()).await;
    assert_eq!(nm.profile_count(), 0);
}

#[tokio::test]
async fn deactivating_stops_the_connection_and_is_fine_when_it_isnt_up() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "x", 1).await.unwrap();
    assert_eq!(daemon.call("network.deactivate", json!({ "uuid": "uuid" })).await["ok"], true);
    assert!(!nm.calls().contains(&"DeactivateConnection".to_string()));
    daemon.call("network.activate", json!({ "uuid": "uuid" })).await;
    daemon.wait_network("it to be up", |state| profile(state, "uuid").is_some_and(|row| row["activeState"] == 2)).await;
    let reply = daemon.call("network.deactivate", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert!(nm.calls().contains(&"DeactivateConnection".to_string()));
    daemon.wait_network("it to be down", |state| profile(state, "uuid").is_some_and(|row| row["activeState"] == 0)).await;
}

#[tokio::test]
async fn the_wifi_switch_reaches_the_service() {
    let (_bus, nm, mut daemon) = setup().await;
    let reply = daemon.call("network.setWifiEnabled", json!({ "enabled": false })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert!(nm.calls().contains(&"SetWirelessEnabled false".to_string()));
    daemon.wait_network("wifi off", |state| state["wifiEnabled"] == false).await;
}

#[tokio::test]
async fn a_scan_is_asked_for_once_and_finishes_when_results_arrive() {
    let (_bus, nm, mut daemon) = setup().await;
    let reply = daemon.call("network.scan", json!({})).await;
    assert_eq!(reply["result"]["requested"], true);
    let reply = daemon.call("network.scan", json!({})).await;
    assert_eq!(reply["result"]["requested"], false, "the second one comes too soon");
    assert_eq!(nm.calls().iter().filter(|call| *call == "RequestScan").count(), 1);
    let reply = daemon.call("network.scan", json!({ "force": true })).await;
    assert_eq!(reply["result"]["requested"], true);
    daemon.wait_network("the scan to finish", |state| state["wifiScanning"] == false && state["devices"][1]["lastScan"] != 100).await;
}

#[tokio::test]
async fn a_refused_scan_isnt_an_error() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.set_scan_refused(true);
    let reply = daemon.call("network.scan", json!({ "force": true })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(reply["result"]["requested"], false);
}

#[tokio::test]
async fn it_notices_the_service_going_and_coming_back() {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let mut daemon = Daemon::start(&bus, &[]).await;
    daemon.wait_network("the service", |state| state["available"] == true).await;
    nm.stop().await.unwrap();
    daemon.wait_network("it to go", |state| state["available"] == false).await;
    let nm = FakeNm::start(&bus).await.unwrap();
    nm.add_wifi_profile("again", b"Home", "wpa-psk", "x", 1).await.unwrap();
    daemon.wait_network("it to return with its profile", |state| state["available"] == true && profile(state, "again").is_some()).await;
}

#[tokio::test]
async fn it_starts_without_the_service_and_picks_it_up_later() {
    let bus = TestBus::start().unwrap();
    let mut daemon = Daemon::start(&bus, &[]).await;
    let state = daemon.wait_message("a snapshot", |message| message["type"] == "snapshot").await;
    assert_eq!(state["data"]["available"], false);
    let _nm = FakeNm::start(&bus).await.unwrap();
    daemon.wait_network("the service", |state| state["available"] == true).await;
}

#[tokio::test]
async fn saved_passwords_are_given_only_when_asked() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "the-saved-password", 1).await.unwrap();
    daemon.wait_network("the profile", |state| profile(state, "uuid").is_some()).await;
    assert!(!daemon.transcript.iter().any(|line| line.contains("the-saved-password")));
    let reply = daemon.call("network.secrets", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["result"]["secrets"], json!([{ "section": "802-11-wireless-security", "key": "psk", "value": "the-saved-password" }]));
    assert!(nm.calls().contains(&"GetSecrets 802-11-wireless-security".to_string()));
}

#[tokio::test]
async fn an_open_network_has_no_secrets_to_read() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Cafe", "", "", 1).await.unwrap();
    let reply = daemon.call("network.secrets", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["result"]["secrets"], json!([]));
    assert!(!nm.calls().iter().any(|call| call.starts_with("GetSecrets")));
}

#[tokio::test]
async fn nothing_stored_isnt_an_error_but_a_refusal_is() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "x", 1).await.unwrap();
    nm.set_secrets_unavailable(true);
    let reply = daemon.call("network.secrets", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["result"]["secrets"], json!([]));
    nm.set_secrets_unavailable(false);
    nm.set_secrets_denied(true);
    let reply = daemon.call("network.secrets", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["error"]["code"], "permission_denied");
}

#[tokio::test]
async fn the_qr_code_and_clipboard_get_the_password_through_stdin_only() {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let tools = common::FakeTools::new(&["qrencode", "wl-copy"]);
    let mut daemon = Daemon::start_with_tools(&bus, &tools).await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "the-saved-password", 1).await.unwrap();

    let reply = daemon.call("network.qrCode", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["result"]["image"], "data:image/png;base64,UE5HREFUQQ==");
    assert_eq!(tools.stdin("qrencode"), "WIFI:T:WPA;S:Home;P:the-saved-password;;");
    assert!(!tools.args("qrencode").contains("the-saved-password"));

    let reply = daemon.call("network.copyPassword", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(tools.stdin("wl-copy"), "the-saved-password");
    assert_eq!(tools.args("wl-copy").trim(), "--sensitive");
    // The reply to these says nothing of the password
    assert!(!daemon.transcript.iter().any(|line| line.contains("the-saved-password")));
}

#[tokio::test]
async fn a_saved_network_without_its_password_cant_be_shared() {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let tools = common::FakeTools::new(&["qrencode", "wl-copy"]);
    let mut daemon = Daemon::start_with_tools(&bus, &tools).await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "x", 1).await.unwrap();
    nm.set_secrets_unavailable(true);
    assert_eq!(daemon.call("network.qrCode", json!({ "uuid": "uuid" })).await["error"]["code"], "secrets_required");
    assert_eq!(daemon.call("network.copyPassword", json!({ "uuid": "uuid" })).await["error"]["code"], "secrets_required");
}

#[tokio::test]
async fn sharing_a_connection_is_a_temporary_access_point() {
    let (_bus, nm, mut daemon) = setup().await;
    let reply = daemon.call("network.startHotspot", json!({ "ssid": "Laptop", "password": "12345678" })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert!(nm.calls().contains(&"AddAndActivateConnection2 persist=volatile".to_string()));
    daemon.wait_network("the hotspot", |state| state["hotspotActive"] == true).await;
    let reply = daemon.call("network.stopHotspot", json!({})).await;
    assert_eq!(reply["ok"], true, "{reply}");
    daemon.wait_network("it to stop", |state| state["hotspotActive"] == false).await;
}

#[tokio::test]
async fn the_editor_reads_a_profile_without_its_secrets() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "the-saved-password", 1).await.unwrap();
    let reply = daemon.call("network.profile", json!({ "uuid": "uuid" })).await;
    let fields = &reply["result"]["fields"];
    assert_eq!(fields["802-11-wireless.ssid"], "Home");
    assert_eq!(fields["802-11-wireless-security.key-mgmt"], "wpa-psk");
    assert!(reply["result"]["revision"].as_str().is_some());
    assert!(!reply.to_string().contains("the-saved-password"));
}

#[tokio::test]
async fn an_edit_keeps_the_saved_password() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "the-saved-password", 1).await.unwrap();
    let reply = daemon.call("network.saveProfile", json!({ "uuid": "uuid", "changes": { "connection.autoconnect": false } })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(nm.secret("uuid", "802-11-wireless-security", "psk").as_deref(), Some("the-saved-password"), "the service clears what an update leaves out");
    assert!(nm.calls().contains(&"Update2 flags=1".to_string()));
    let reply = daemon.call("network.profile", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["result"]["fields"]["connection.autoconnect"], false);
}

#[tokio::test]
async fn an_edit_reaches_the_form_again_after_the_cache_is_refreshed() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "x-password", 1).await.unwrap();
    daemon.wait_network("the profile", |state| profile(state, "uuid").is_some()).await;
    daemon.call("network.saveProfile", json!({ "uuid": "uuid", "changes": { "connection.id": "Renamed" } })).await;
    daemon.wait_network("the new name", |state| profile(state, "uuid").is_some_and(|row| row["id"] == "Renamed")).await;
}

#[tokio::test]
async fn a_profile_changed_elsewhere_isnt_overwritten() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "x-password", 1).await.unwrap();
    let reply = daemon.call("network.profile", json!({ "uuid": "uuid" })).await;
    let revision = reply["result"]["revision"].clone();
    daemon.call("network.saveProfile", json!({ "uuid": "uuid", "changes": { "connection.zone": "home" } })).await;
    let reply = daemon.call("network.saveProfile", json!({ "uuid": "uuid", "revision": revision, "changes": { "connection.zone": "work" } })).await;
    assert_eq!(reply["error"]["code"], "conflict");
    let reply = daemon.call("network.profile", json!({ "uuid": "uuid" })).await;
    assert_eq!(reply["result"]["fields"]["connection.zone"], "home");
    let revision = reply["result"]["revision"].clone();
    let reply = daemon.call("network.saveProfile", json!({ "uuid": "uuid", "revision": revision, "changes": { "connection.zone": "work" } })).await;
    assert_eq!(reply["ok"], true, "{reply}");
}

#[tokio::test]
async fn bad_edits_are_refused_and_change_nothing() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "x-password", 1).await.unwrap();
    let reply = daemon.call("network.saveProfile", json!({ "uuid": "uuid", "changes": { "ipv4.gateway": "not an address" } })).await;
    assert_eq!(reply["error"]["code"], "invalid");
    assert!(reply["error"]["message"].as_str().unwrap().starts_with("ipv4.gateway"));
    assert!(!nm.calls().iter().any(|call| call.starts_with("Update2")));
}

#[tokio::test]
async fn adding_a_profile_gives_it_an_id_and_saves_it() {
    let (_bus, nm, mut daemon) = setup().await;
    let reply = daemon.call("network.addProfile", json!({ "connectionType": "802-3-ethernet", "changes": { "connection.id": "Office cable", "ipv4.method": "manual", "ipv4.address-data": ["10.0.0.5/24"], "ipv4.gateway": "10.0.0.1", "ipv4.dns": ["1.1.1.1"] } })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    let uuid = reply["result"]["uuid"].as_str().unwrap().to_string();
    assert_eq!(uuid.len(), 36);
    assert!(nm.calls().contains(&"AddConnection2 flags=1".to_string()));
    let state = daemon.wait_network("the new profile", |state| profile(state, &uuid).is_some()).await;
    assert_eq!(profile(&state, &uuid).unwrap()["id"], "Office cable");
    let fields = daemon.call("network.profile", json!({ "uuid": uuid })).await;
    assert_eq!(fields["result"]["fields"]["ipv4.address-data"], json!(["10.0.0.5/24"]));
    assert_eq!(fields["result"]["fields"]["ipv4.dns"], json!(["1.1.1.1"]));
}

#[tokio::test]
async fn a_new_profile_needs_a_name_and_a_known_kind() {
    let (_bus, nm, mut daemon) = setup().await;
    let reply = daemon.call("network.addProfile", json!({ "connectionType": "802-3-ethernet", "changes": {} })).await;
    assert!(reply["error"]["message"].as_str().unwrap().contains("connection.id"));
    let reply = daemon.call("network.addProfile", json!({ "connectionType": "nonsense", "changes": { "connection.id": "x" } })).await;
    assert_eq!(reply["error"]["code"], "invalid");
    assert_eq!(nm.profile_count(), 0);
}

#[tokio::test]
async fn a_vpn_profile_keeps_its_data_and_secrets() {
    let (_bus, _nm, mut daemon) = setup().await;
    let reply = daemon.call("network.addProfile", json!({
        "connectionType": "vpn",
        "vpnService": "org.freedesktop.NetworkManager.openvpn",
        "changes": { "connection.id": "Work", "vpn.data": { "remote": "vpn.example.com", "connection-type": "password", "username": "me", "password-flags": "0" }, "vpn.secrets": { "password": "vpn-secret" } },
    })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    let uuid = reply["result"]["uuid"].as_str().unwrap().to_string();
    let state = daemon.wait_network("the VPN", |state| profile(state, &uuid).is_some()).await;
    assert_eq!(profile(&state, &uuid).unwrap()["vpnType"], "openvpn");
    assert_eq!(profile(&state, &uuid).unwrap()["available"], true);
    let form = daemon.call("network.profile", json!({ "uuid": uuid })).await;
    assert_eq!(form["result"]["fields"]["vpn.data"]["remote"], "vpn.example.com");
    assert!(!form.to_string().contains("vpn-secret"));
    let reply = daemon.call("network.secrets", json!({ "uuid": uuid })).await;
    assert_eq!(reply["result"]["secrets"], json!([{ "section": "vpn", "key": "password", "value": "vpn-secret" }]));
    // An edit of its data doesn't lose the password
    daemon.call("network.saveProfile", json!({ "uuid": uuid, "changes": { "vpn.data": { "remote": "other.example.com" } } })).await;
    let reply = daemon.call("network.secrets", json!({ "uuid": uuid })).await;
    assert_eq!(reply["result"]["secrets"], json!([{ "section": "vpn", "key": "password", "value": "vpn-secret" }]));
}

#[tokio::test]
async fn importing_hands_only_the_path_to_the_tool() {
    let bus = TestBus::start().unwrap();
    let _nm = FakeNm::start(&bus).await.unwrap();
    let tools = common::FakeTools::new(&[]).with_output("nmcli", "Connection 'home' (0a1b2c3d-1111-2222-3333-444455556666) successfully added.", 0);
    let mut daemon = Daemon::start_with_tools(&bus, &tools).await;
    let file = tools.directory.join("home.ovpn");
    std::fs::write(&file, "client\nremote example.com\n").unwrap();
    let reply = daemon.call("network.importVpn", json!({ "path": file })).await;
    assert_eq!(reply["result"]["uuid"], "0a1b2c3d-1111-2222-3333-444455556666");
    let args = tools.args("nmcli");
    assert_eq!(args.lines().take(4).collect::<Vec<_>>(), ["connection", "import", "type", "openvpn"]);
    assert!(args.contains("home.ovpn"));

    let wireguard = tools.directory.join("wg0.conf");
    std::fs::write(&wireguard, "[Interface]\nPrivateKey = x\n").unwrap();
    daemon.call("network.importVpn", json!({ "path": wireguard })).await;
    assert!(tools.args("nmcli").contains("wireguard"));
}

#[tokio::test]
async fn a_failed_import_says_why() {
    let bus = TestBus::start().unwrap();
    let _nm = FakeNm::start(&bus).await.unwrap();
    let tools = common::FakeTools::new(&[]).with_output("nmcli", "Error: failed to find VPN plugin for openvpn.", 1);
    let mut daemon = Daemon::start_with_tools(&bus, &tools).await;
    let file = tools.directory.join("home.ovpn");
    std::fs::write(&file, "client\n").unwrap();
    let reply = daemon.call("network.importVpn", json!({ "path": file })).await;
    assert_eq!(reply["error"]["message"], "failed to find VPN plugin for openvpn.");
    let reply = daemon.call("network.importVpn", json!({ "path": "/nonexistent/file.ovpn" })).await;
    assert_eq!(reply["error"]["code"], "not_found");
}

#[tokio::test]
async fn exporting_wireguard_writes_a_private_file() {
    use std::os::unix::fs::PermissionsExt;
    let (_bus, _nm, mut daemon) = setup().await;
    let key = "YAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=";
    let peer = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";
    let reply = daemon.call("network.addProfile", json!({ "connectionType": "wireguard", "changes": {
        "connection.id": "wg", "connection.interface-name": "wg0", "wireguard.private-key": key,
        "wireguard.peers": [{ "public-key": peer, "allowed-ips": ["0.0.0.0/0"] }],
    } })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    let uuid = reply["result"]["uuid"].as_str().unwrap().to_string();
    let target = std::env::temp_dir().join(format!("velora-export-{}.conf", std::process::id()));
    let reply = daemon.call("network.exportVpn", json!({ "uuid": uuid, "path": target })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    let text = std::fs::read_to_string(&target).unwrap();
    assert!(text.contains(&format!("PrivateKey = {key}")));
    assert!(text.contains(&format!("PublicKey = {peer}")));
    assert_eq!(std::fs::metadata(&target).unwrap().permissions().mode() & 0o777, 0o600);
    std::fs::remove_file(&target).unwrap();
}
