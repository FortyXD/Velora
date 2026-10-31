//! The stand-ins as a program, on the bus in `DBUS_SYSTEM_BUS_ADDRESS`, for tests that run the whole shell
//! against them. Says READY once they're up, and stops when its stdin closes.

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use velora_connectivity_fakes::bluez::{DeviceSpec, FakeBluez, Pairing};
use velora_connectivity_fakes::nm::{value, FakeNm, Props, Settings, RSN_PSK, RSN_SAE};
use zbus::Connection;

async fn neighbourhood(nm: &FakeNm) -> anyhow::Result<()> {
    nm.add_access_point(b"Home", "00:00:00:00:00:01", 82, RSN_PSK).await?;
    nm.add_access_point(b"Office", "00:00:00:00:00:02", 45, RSN_SAE).await?;
    nm.add_access_point(b"Neighbour", "00:00:00:00:00:03", 30, RSN_PSK).await?;
    nm.add_access_point(b"Cafe", "00:00:00:00:00:04", 60, 0).await?;
    nm.add_wifi_profile("home-uuid", b"Home", "wpa-psk", "home-password", 1_700_000_000).await?;
    nm.add_wifi_profile("office-uuid", b"Office", "sae", "office-password", 1_690_000_000).await?;
    nm.add_wifi_profile("far-uuid", b"Far away", "wpa-psk", "far-password", 1_680_000_000).await?;
    nm.add_wifi_profile("never-uuid", b"Never joined", "wpa-psk", "", 0).await?;

    let mut vpn = Settings::new();
    let mut connection = Props::new();
    connection.insert("id".to_string(), value("Work VPN"));
    connection.insert("uuid".to_string(), value("vpn-uuid"));
    connection.insert("type".to_string(), value("vpn"));
    vpn.insert("connection".to_string(), connection);
    let mut data = std::collections::HashMap::new();
    data.insert("remote".to_string(), "vpn.example.com".to_string());
    data.insert("connection-type".to_string(), "password".to_string());
    let mut section = Props::new();
    section.insert("service-type".to_string(), value("org.freedesktop.NetworkManager.openvpn"));
    section.insert("data".to_string(), value(data));
    vpn.insert("vpn".to_string(), section);
    nm.add_profile(vpn).await?;

    let mut wired = Settings::new();
    let mut connection = Props::new();
    connection.insert("id".to_string(), value("Cable"));
    connection.insert("uuid".to_string(), value("wired-uuid"));
    connection.insert("type".to_string(), value("802-3-ethernet"));
    wired.insert("connection".to_string(), connection);
    wired.insert("802-3-ethernet".to_string(), Props::new());
    nm.add_profile(wired).await?;
    Ok(())
}

async fn devices(bluez: &FakeBluez) -> anyhow::Result<()> {
    bluez.add_device(DeviceSpec { address: "11:11:11:11:11:11", name: "Headphones", icon: "audio-headphones", uuids: &["0000110b-0000-1000-8000-00805f9b34fb"], paired: true, connected: true, battery: Some(64) }).await?;
    bluez.add_device(DeviceSpec { address: "22:22:22:22:22:22", name: "Phone", icon: "phone", uuids: &["00001105-0000-1000-8000-00805f9b34fb"], paired: true, ..DeviceSpec::default() }).await?;
    bluez.add_device(DeviceSpec { address: "33:33:33:33:33:33", name: "Speaker", icon: "audio-card", ..DeviceSpec::default() }).await?;
    bluez.add_device(DeviceSpec { address: "44:44:44:44:44:44", name: "Keyboard", icon: "input-keyboard", ..DeviceSpec::default() }).await?;
    bluez.set_pairing("44:44:44:44:44:44", Pairing::Confirm(123_456));
    Ok(())
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let nm = FakeNm::start_on(Connection::system().await?).await?;
    neighbourhood(&nm).await?;
    let bluez = FakeBluez::start_on(Connection::system().await?).await?;
    devices(&bluez).await?;
    let mut stdout = tokio::io::stdout();
    stdout.write_all(b"READY\n").await?;
    stdout.flush().await?;
    let mut sink = Vec::new();
    tokio::io::stdin().read_to_end(&mut sink).await?;
    Ok(())
}
