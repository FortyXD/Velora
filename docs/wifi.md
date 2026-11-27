# Wi-Fi in Velora

Open Settings → Wi-Fi, or left-click **Details** in the sidebar's Wi-Fi dialog. Right-clicking **Details** opens the configured external network settings, KDE by default. Bluetooth follows the same mouse-button behavior.

The current connection starts collapsed, showing its name and signal. Expand it to see addresses, DNS, security and connection actions. Ethernet is shown whenever an Ethernet adapter exists, including when no cable is connected. Available saved Wi-Fi networks come before other nearby networks, which are ordered by signal strength. Saved passwords have their own section at the bottom.

## Connecting and passwords

New personal networks ask for a password inside their row. Saved networks try their existing credentials, and can request a replacement in the same form. “Joined before” describes history, not proof that a password is available. Hidden networks offer WPA/WPA2, WPA3 or an open connection; the network name is used exactly as typed, including spaces.

Nearby rows and pending prompts are identified by SSID bytes **and security**, not just the displayed name. An open lookalike never borrows a secured profile. WPA2 profiles remain usable on WPA2/WPA3 transition access points, but not SAE-only lookalikes. A pending row survives temporary disappearance from a scan so its scoped password request stays usable.

**Stop waiting** closes Velora's wait and password prompt. It does not deactivate a connection: NetworkManager may finish an activation already in progress. Closing a page or dialog also drops its pending prompt. Password fields clear on submission, cancellation, hiding and while waiting; revealing a password resets when the field clears.

A new profile starts in memory with autoconnect disabled. Velora writes it to disk and enables autoconnect after a successful activation. Replacing a saved password preserves the profile's UUID and on-disk credentials until activation succeeds. Failed or canceled replacements restore the temporary in-memory edit when the profile has not changed concurrently. Velora never deletes a saved profile to retry a password.

A connection that succeeds but cannot save its password stays connected and shows a warning. Profile version checks prevent saving or rolling back over concurrent edits; missing/zero version IDs fail closed. Velora retrieves the profile's other NM-owned secrets before writing it back, so omitted secrets and permissions are preserved. A failed pre-activation secret read refuses the replacement rather than erase existing secrets. A failed post-success read/save instead shows the connected-but-not-saved warning.

Existing `AGENT_OWNED` / `NOT_SAVED` flags are retained; Velora neither retrieves nor takes ownership of an external keyring's replacement password. Such a replacement can connect but shows the not-saved warning. Ordinary activation with an external agent's existing credentials needs no rewrite and no warning. Enterprise, WEP, the connection editor and the newer Bluetooth/Ethernet/hotspot/airplane/QR APIs remain available; the former Python credential helper is not started alongside the daemon.

Wi-Fi attempts allow 60 seconds of backend work across preparation and activation, paused while a scoped password request awaits input. Saving after success and best-effort rollback each have a separate 60-second bound. EOF cancels pending Wi-Fi work and waits up to 65 seconds for cleanup; a successful connection is never deactivated. Cancellation and timeout cannot atomically stop NM activation, so a late activation or timed-out D-Bus write may still finish; canceled attempts are never deliberately persisted. Unsuccessful new profiles can remain in NM memory until restart, with autoconnect off.

## Backend and troubleshooting

The shell and settings use `velora-connectivityd`, a Rust D-Bus client for NetworkManager and BlueZ. This release requires JSON protocol version 3. Installation synchronizes both native executables before linking the configuration, including with `--skip-packages`. Package installations copy the packaged executables without requiring Rust. The launchers prefer this managed pair over older copies in `PATH`.

If source files are already current but the native executables are missing or stale, `velora update` repairs them. It compares fingerprints of the build inputs and installed executables; background update checks never build or repair anything. The shell retries automatically after a repair. Passwords travel through the daemon's stdin and D-Bus, never command arguments, environment, temporary files, logs or network snapshots. Fields clear on submit/cancel; retries do not reuse rejected passwords. Whitespace is preserved. WPA2 accepts 8–63 UTF-8 bytes or a 64-digit hexadecimal PSK; SAE accepts 1–63 UTF-8 bytes. Qt/JSON/D-Bus cannot guarantee erasure of every secret copy in memory.

Each Wi-Fi operation registers a short-lived secret agent on its own D-Bus connection. It accepts requests only from NetworkManager's current unique bus owner and for its own connection UUID and profile path. Operation and request tokens reject stale password replies. A runtime lock serializes operations between the shell and settings app.

The automated checks use a private message bus and a stand-in NetworkManager. They do not connect to, disconnect or modify the machine's real networks:

```bash
cargo test --locked --manifest-path tools/Cargo.toml -p velora-connectivityd --lib
cargo test --locked --manifest-path tools/Cargo.toml -p velora-connectivityd --test wifi
python3 -m unittest discover -s tests -p 'test_connectivity_qml.py' -v
python3 -m unittest discover -s tests -p 'test_connectivity_pages.py' -v
```

The Qt tests need Qt Quick Test and Quickshell. Set `VELORA_REQUIRE_CONNECTIVITY_TESTS=1` to make missing test dependencies an error. The native Wi-Fi suite includes a real 61-second prompt wait and a deliberately stalled save.

The old Python fake-NM/libnm-agent tests are replaced by native model/work-budget unit tests and private-bus tests of the actual Rust daemon, scoped agent, transient creation, ownership/secret preservation, version conflicts, EOF, retries and cancellation. Production QML service/form tests cover inline clearing/tokens and per-security row identity; deep-link checks retain stable section IDs and bounded reveal retries. These do not prove real NetworkManager disk persistence, physical Wi-Fi authentication, external-keyring interoperability or visual navigation on hardware. No automated check activates or disconnects the user's real network.

## VPNs

Open **Settings → Network & VPN** or press **Super+H**. The optional **VPN protocols** component installs WireGuard tools, NetworkManager VPN plugins and the sing-box engine.

- Import OpenVPN, WireGuard or Cisco PCF files using automatic detection. Choose the plugin explicitly for another configuration format. Saved connections provide Connect, Disconnect and Edit. File import and export depend on the plugin.
- Under **Proxy and subscription VPNs**, paste a VLESS, VMess, Shadowsocks, Trojan, Hysteria, Hysteria2 or TUIC share link, enter a subscription URL, or choose a provider file. Velora reads plain and Base64-encoded share lists and compatible proxy outbounds from sing-box JSON. Choose a server and click **Connect**. **Refresh** fetches a subscription again. An unsuccessful refresh preserves the previous list.
- **Install VPN engine** installs sing-box from the Arch repository when needed. Connecting requests system authorization for a desktop-wide IPv4 and IPv6 tunnel. The settings window can then close. **Disconnect** stops the tunnel. Application DNS uses DNS over HTTPS to Cloudflare through the tunnel. The system resolver locates the VPN server.
- **Ping a VPN server** accepts a hostname, IPv4 address or IPv6 address. A reply shows round-trip time in milliseconds. Some VPN servers decline ICMP requests even when their tunnel is available.
