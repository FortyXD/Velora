//! The JSON-lines contract with the shell, and how the daemon treats what it holds in secret.

mod common;

use common::Daemon;
use serde_json::{json, Value};
use velora_connectivity_fakes::bus::TestBus;
use velora_connectivity_fakes::nm::{FakeNm, Outcome};

const MARKER: &str = "marker-password-do-not-leak";

async fn setup() -> (TestBus, FakeNm, Daemon) {
    let bus = TestBus::start().unwrap();
    let nm = FakeNm::start(&bus).await.unwrap();
    let mut daemon = Daemon::start(&bus, &[]).await;
    daemon.wait_network("the first snapshot", |state| state["available"] == true).await;
    (bus, nm, daemon)
}

#[tokio::test]
async fn it_says_hello_with_its_version_first() {
    let bus = TestBus::start().unwrap();
    let mut daemon = Daemon::start(&bus, &["--agents"]).await;
    let first = daemon.wait_message("anything", |_| true).await;
    assert_eq!(first, json!({ "type": "hello", "protocol": 1, "agents": true }));
}

#[tokio::test]
async fn it_answers_a_known_method_and_refuses_an_unknown_one() {
    let (_bus, _nm, mut daemon) = setup().await;
    let reply = daemon.call("ping", Value::Null).await;
    assert_eq!(reply["result"], "pong");
    let reply = daemon.call("does.not.exist", Value::Null).await;
    assert_eq!(reply["ok"], false);
    assert_eq!(reply["error"]["code"], "unknown_method");
}

#[tokio::test]
async fn bad_parameters_are_refused_without_being_repeated() {
    let (_bus, _nm, mut daemon) = setup().await;
    let reply = daemon.call("network.changePassword", json!({ "uuid": 5, "password": MARKER })).await;
    assert_eq!(reply["error"]["code"], "invalid");
    assert!(!reply.to_string().contains(MARKER));
    let reply = daemon.call("network.activate", json!({})).await;
    assert_eq!(reply["error"]["code"], "invalid");
    assert!(reply["error"]["message"].as_str().unwrap().contains("uuid"));
}

#[tokio::test]
async fn a_line_that_isnt_json_is_reported_and_it_keeps_going() {
    let (_bus, _nm, mut daemon) = setup().await;
    daemon.write_raw(&format!("{{not json {MARKER}\n")).await;
    let event = daemon.wait_message("the complaint", |message| message["name"] == "protocolError").await;
    assert_eq!(event["data"]["code"], "invalid");
    assert!(!event.to_string().contains(MARKER));
    assert_eq!(daemon.call("ping", Value::Null).await["result"], "pong");
}

#[tokio::test]
async fn requests_run_side_by_side() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "x", 1).await.unwrap();
    let slow = daemon.send("network.activate", json!({ "uuid": "uuid" })).await;
    let quick = daemon.send("ping", Value::Null).await;
    let answer = daemon.wait_response(quick).await;
    assert_eq!(answer["result"], "pong");
    assert_eq!(daemon.wait_response(slow).await["ok"], true);
}

#[tokio::test]
async fn it_exits_cleanly_when_stdin_closes() {
    let (_bus, _nm, daemon) = setup().await;
    let (status, _) = daemon.close_stdin().await;
    assert!(status.success());
}

#[tokio::test]
async fn an_unknown_option_is_refused() {
    let status = tokio::process::Command::new(env!("CARGO_BIN_EXE_velora-connectivityd")).arg("--nope").stderr(std::process::Stdio::null()).status().await.unwrap();
    assert_eq!(status.code(), Some(2));
}

/// A password sent to the daemon goes nowhere but to the service: not to arguments, stdout or stderr.
#[tokio::test]
async fn a_password_stays_out_of_arguments_output_and_logs() {
    let (_bus, nm, mut daemon) = setup().await;
    nm.add_wifi_profile("uuid", b"Home", "wpa-psk", "old", 1).await.unwrap();
    nm.set_outcome(Outcome::Fail { device_reason: 8, active_reason: 3 });
    let id = daemon.send("network.changePassword", json!({ "uuid": "uuid", "password": MARKER })).await;
    let reply = daemon.wait_response(id).await;
    assert_eq!(reply["error"]["code"], "wrong_secret");
    assert_eq!(nm.secret("uuid", "802-11-wireless-security", "psk").as_deref(), Some(MARKER));

    let pid = daemon.child.id().unwrap();
    let cmdline = std::fs::read(format!("/proc/{pid}/cmdline")).unwrap();
    assert!(!String::from_utf8_lossy(&cmdline).contains(MARKER));
    assert!(!daemon.transcript.iter().any(|line| line.contains(MARKER)));

    let mut stderr = daemon.child.stderr.take().unwrap();
    let (status, transcript) = daemon.close_stdin().await;
    assert!(status.success());
    assert!(!transcript.iter().any(|line| line.contains(MARKER)));
    let mut logged = String::new();
    tokio::io::AsyncReadExt::read_to_string(&mut stderr, &mut logged).await.unwrap();
    assert!(!logged.contains(MARKER), "stderr: {logged}");
}
