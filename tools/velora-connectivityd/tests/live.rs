//! Against the real NetworkManager on this computer, on request only:
//!
//!     cargo test -p velora-connectivityd --test live -- --ignored --test-threads=1
//!
//! Existing profiles are only read, and their secrets are never printed. The one thing written is a temporary
//! profile that can't connect by itself, removed again at the end.

use serde_json::{json, Value};
use std::process::Stdio;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;

struct Live {
    child: tokio::process::Child,
    stdin: tokio::process::ChildStdin,
    lines: tokio::io::Lines<BufReader<tokio::process::ChildStdout>>,
    next_id: u64,
    network: Value,
    bluetooth: Value,
}

impl Live {
    async fn start() -> Self {
        let mut child = Command::new(env!("CARGO_BIN_EXE_velora-connectivityd"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .kill_on_drop(true)
            .spawn()
            .unwrap();
        let stdin = child.stdin.take().unwrap();
        let lines = BufReader::new(child.stdout.take().unwrap()).lines();
        let mut live = Self { child, stdin, lines, next_id: 0, network: Value::Null, bluetooth: Value::Null };
        while live.network["available"] != true || live.bluetooth.is_null() {
            live.read().await;
        }
        live
    }

    async fn read(&mut self) -> Value {
        let line = tokio::time::timeout(Duration::from_secs(15), self.lines.next_line()).await.expect("an answer in time").unwrap().expect("still running");
        let message: Value = serde_json::from_str(&line).unwrap();
        if message["type"] == "snapshot" && message["domain"] == "network" {
            self.network = message["data"].clone();
        }
        if message["type"] == "snapshot" && message["domain"] == "bluetooth" {
            self.bluetooth = message["data"].clone();
        }
        message
    }

    async fn call(&mut self, method: &str, params: Value) -> Value {
        self.next_id += 1;
        let id = self.next_id;
        self.stdin.write_all(format!("{}\n", json!({ "id": id, "method": method, "params": params })).as_bytes()).await.unwrap();
        loop {
            let message = self.read().await;
            if message["type"] == "response" && message["id"] == id {
                return message;
            }
        }
    }
}

fn nmcli(arguments: &[&str]) -> String {
    let output = std::process::Command::new("nmcli").args(arguments).env("LC_ALL", "C").output().unwrap();
    String::from_utf8_lossy(&output.stdout).into_owned()
}

#[tokio::test]
#[ignore = "needs the real NetworkManager"]
async fn live_the_list_matches_nmcli() {
    let live = Live::start().await;
    let expected: Vec<String> = nmcli(&["-t", "-f", "UUID,TYPE", "connection", "show"]).lines().filter(|line| !line.ends_with(":loopback")).map(|line| line.split(':').next().unwrap().to_string()).collect();
    let rows = live.network["profiles"].as_array().unwrap();
    let mut listed: Vec<String> = rows.iter().map(|row| row["uuid"].as_str().unwrap().to_string()).collect();
    let mut wanted = expected;
    listed.sort();
    wanted.sort();
    assert_eq!(listed, wanted);
    let wifi_state = nmcli(&["-t", "radio", "wifi"]).trim() == "enabled";
    assert_eq!(live.network["wifiEnabled"], wifi_state);
    drop(live.child);
}

#[tokio::test]
#[ignore = "needs the real BlueZ"]
async fn live_bluetooth_matches_what_bluez_reports() {
    let live = Live::start().await;
    let state = live.bluetooth.clone();
    let output = std::process::Command::new("busctl").args(["--system", "--json=short", "call", "org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"]).output().unwrap();
    let objects: Value = serde_json::from_slice(&output.stdout).unwrap();
    let objects = objects["data"][0].as_object().unwrap();
    let adapters = objects.values().filter(|interfaces| interfaces.get("org.bluez.Adapter1").is_some()).count();
    let devices = objects.values().filter(|interfaces| interfaces.get("org.bluez.Device1").is_some()).count();
    assert_eq!(state["adapters"].as_array().unwrap().len(), adapters);
    assert!(state["saved"].as_array().unwrap().len() + state["nearby"].as_array().unwrap().len() <= devices + 5, "devices come and go while this runs");
    let paired = objects.values().filter(|interfaces| interfaces["org.bluez.Device1"]["Paired"]["data"] == true).count();
    assert_eq!(state["saved"].as_array().unwrap().iter().filter(|device| device["paired"] == true).count(), paired);
    println!("{adapters} adapter(s), {paired} paired, {devices} known");
}

#[tokio::test]
#[ignore = "needs the real NetworkManager"]
async fn live_saved_passwords_can_be_read() {
    let mut live = Live::start().await;
    let rows = live.network["profiles"].as_array().unwrap().clone();
    let mut readable = 0;
    let mut with_password = 0;
    for row in rows.iter().filter(|row| matches!(row["securityType"].as_str(), Some("wpa-psk" | "sae"))) {
        with_password += 1;
        let reply = live.call("network.secrets", json!({ "uuid": row["uuid"] })).await;
        assert_eq!(reply["ok"], true, "reading {}: {}", row["id"], reply["error"]);
        if reply["result"]["secrets"].as_array().unwrap().iter().any(|secret| secret["key"] == "psk" && secret["value"].as_str().is_some_and(|value| !value.is_empty())) {
            readable += 1;
        }
    }
    println!("{readable} of {with_password} password networks gave their password");
    assert!(readable > 0);
}

#[tokio::test]
#[ignore = "needs the real NetworkManager"]
async fn live_a_temporary_profile_goes_through_its_whole_life() {
    let mut live = Live::start().await;
    let before = nmcli(&["-t", "-f", "UUID", "connection", "show"]);
    let active_before = nmcli(&["-t", "-f", "UUID", "connection", "show", "--active"]);
    let name = format!("velora-e2e-{}", std::process::id());

    let reply = live.call("network.addProfile", json!({ "connectionType": "802-11-wireless", "changes": {
        "connection.id": name,
        "connection.autoconnect": false,
        "802-11-wireless.ssid": name,
        "802-11-wireless-security.key-mgmt": "wpa-psk",
        "802-11-wireless-security.psk": "velora-e2e-password",
        "ipv4.method": "manual",
        "ipv4.address-data": ["10.123.45.6/24"],
        "ipv4.gateway": "10.123.45.1",
        "ipv4.dns": ["10.123.45.1"],
        "ipv4.route-data": [{ "dest": "10.200.0.0", "prefix": 16, "next-hop": "10.123.45.1", "metric": 50 }],
    } })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    let uuid = reply["result"]["uuid"].as_str().unwrap().to_string();

    let result = async {
        let form = live.call("network.profile", json!({ "uuid": uuid })).await;
        let fields = form["result"]["fields"].clone();
        assert_eq!(fields["802-11-wireless.ssid"], name.as_str());
        assert_eq!(fields["connection.autoconnect"], false);
        assert_eq!(fields["ipv4.address-data"], json!(["10.123.45.6/24"]));
        assert_eq!(fields["ipv4.gateway"], "10.123.45.1");
        assert_eq!(fields["ipv4.dns"], json!(["10.123.45.1"]));
        assert_eq!(fields["ipv4.route-data"][0]["dest"], "10.200.0.0");
        assert_eq!(fields["ipv4.route-data"][0]["prefix"], 16);

        // What nmcli sees is the same
        assert_eq!(nmcli(&["-g", "ipv4.addresses", "connection", "show", "uuid", &uuid]).trim(), "10.123.45.6/24");
        assert_eq!(nmcli(&["-g", "ipv4.dns", "connection", "show", "uuid", &uuid]).trim(), "10.123.45.1");

        let secrets = live.call("network.secrets", json!({ "uuid": uuid })).await;
        assert_eq!(secrets["result"]["secrets"][0]["value"], "velora-e2e-password");

        // An edit leaves the password alone, and clearing the fixed address goes through
        let reply = live.call("network.saveProfile", json!({ "uuid": uuid, "revision": form["result"]["revision"], "changes": {
            "connection.autoconnect-priority": 5,
            "ipv4.method": "auto",
            "ipv4.address-data": [],
            "ipv4.gateway": "",
            "ipv4.route-data": [],
            "ipv4.dns": ["9.9.9.9"],
            "802-11-wireless.mtu": 1400,
            "802-11-wireless.assigned-mac-address": "stable",
        } })).await;
        assert_eq!(reply["ok"], true, "{reply}");
        let secrets = live.call("network.secrets", json!({ "uuid": uuid })).await;
        assert_eq!(secrets["result"]["secrets"][0]["value"], "velora-e2e-password");
        let form = live.call("network.profile", json!({ "uuid": uuid })).await;
        let fields = &form["result"]["fields"];
        assert_eq!(fields["connection.autoconnect-priority"], 5);
        assert_eq!(fields["ipv4.method"], "auto");
        assert_eq!(fields["ipv4.dns"], json!(["9.9.9.9"]));
        assert_eq!(fields["802-11-wireless.mtu"], 1400);
        assert_eq!(fields["802-11-wireless.assigned-mac-address"], "stable");
        assert_eq!(fields["ipv4.address-data"], json!([]));

        // A stale editor is told so
        let stale = live.call("network.saveProfile", json!({ "uuid": uuid, "revision": "0000", "changes": { "connection.zone": "x" } })).await;
        assert_eq!(stale["error"]["code"], "conflict");

        // Bad values come back from us or from the service as refusals, never half-applied
        let refused = live.call("network.saveProfile", json!({ "uuid": uuid, "changes": { "802-11-wireless.mode": "nonsense" } })).await;
        assert_eq!(refused["ok"], false, "{refused}");
        let form = live.call("network.profile", json!({ "uuid": uuid })).await;
        assert_eq!(form["result"]["fields"]["802-11-wireless.mode"], "infrastructure");
    }
    .await;
    let _: () = result;

    let reply = live.call("network.forget", json!({ "uuid": uuid })).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(nmcli(&["-t", "-f", "UUID", "connection", "show"]), before, "only the temporary profile came and went");
    assert_eq!(nmcli(&["-t", "-f", "UUID", "connection", "show", "--active"]), active_before, "the active connections didn't change");
}
