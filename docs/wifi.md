# Wi-Fi in Velora

Open Settings → Wi-Fi, or left-click **Details** in the sidebar's Wi-Fi dialog. Right-clicking **Details** opens the configured external network settings, KDE by default. Bluetooth follows the same mouse-button behavior.

The current connection starts collapsed, showing its name and signal. Expand it to see addresses, DNS, security and connection actions. Ethernet is shown whenever an Ethernet adapter exists, including when no cable is connected. Available saved Wi-Fi networks come before other nearby networks, which are ordered by signal strength. Saved passwords have their own section at the bottom.

## Connecting and passwords

New personal networks ask for a password inside their row. Saved networks try their existing credentials, and can request a replacement in the same form. Hidden networks offer WPA/WPA2, WPA3 or an open connection; the network name is used exactly as typed, including spaces.

**Stop waiting** closes Velora's wait and password prompt. It does not deactivate a connection: NetworkManager may finish an activation already in progress. Closing a page or dialog also drops its pending prompt. Password fields clear on submission, cancellation, hiding and while waiting; revealing a password resets when the field clears.

A new profile starts in memory with autoconnect disabled. Velora writes it to disk and enables autoconnect after a successful activation. Replacing a saved password preserves the profile's UUID and on-disk credentials until activation succeeds. Failed or canceled replacements restore the temporary in-memory edit when the profile has not changed concurrently. Velora never deletes a saved profile to retry a password.

A connection that succeeds but cannot save its password stays connected and shows a warning. Profile version checks prevent saving over concurrent edits. Existing secret ownership flags are retained; Velora does not take passwords away from an external keyring. Enterprise networks use the connection editor and the existing NetworkManager secret-agent integration.

## Backend and troubleshooting

The shell and settings use `velora-connectivityd`, a Rust D-Bus client for NetworkManager and BlueZ. This release requires JSON protocol version 2. Installation synchronizes both native executables before linking the configuration, including with `--skip-packages`. Package installations copy the packaged executables without requiring Rust. The launchers prefer this managed pair over older copies in `PATH`.

If source files are already current but the native executables are missing or stale, `velora update` repairs them. It compares fingerprints of the build inputs and installed executables; background update checks never build or repair anything. The shell retries automatically after a repair. Passwords travel through the daemon's stdin and D-Bus, never command arguments or network snapshots.

Each Wi-Fi operation registers a short-lived secret agent on its own D-Bus connection. It accepts requests only from NetworkManager's current unique bus owner and for its own connection UUID and profile path. Operation and request tokens reject stale password replies. A runtime lock serializes operations between the shell and settings app.

The automated checks use a private message bus and a stand-in NetworkManager. They do not connect to, disconnect or modify the machine's real networks:

```bash
cargo test --locked --manifest-path tools/Cargo.toml -p velora-connectivityd --test wifi
python3 -m unittest discover -s tests -p 'test_connectivity_qml.py' -v
python3 -m unittest discover -s tests -p 'test_connectivity_pages.py' -v
```

The Qt tests need Qt Quick Test and Quickshell. Set `VELORA_REQUIRE_CONNECTIVITY_TESTS=1` to make missing test dependencies an error.
