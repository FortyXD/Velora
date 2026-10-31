# Velora 0.1.4

Wi-Fi, VPN and Bluetooth settings inside Velora, safer password retries, and cursor controls for screenshots.

Velora is an independently maintained fork of Illogical Impulse for Arch Linux, Hyprland and Quickshell.

## Highlights

- **Reliable upgrades from 0.1.3.** Installation updates both native executables before linking the shell, including with `--skip-packages`. Package installs synchronize old user copies as well. If sources are already current, `velora update` detects and repairs missing or stale native binaries automatically. Background checks do not build anything.
- **Connectivity settings.** Manage Wi-Fi, saved passwords, connection profiles, OpenVPN and WireGuard, or pair and manage Bluetooth devices without leaving Velora. Bluetooth includes PIN and confirmation prompts, battery information and file transfer.
- **A clearer network list.** Expand the current Wi-Fi connection for its details. Ethernet appears whenever an adapter exists. Available saved networks come first, followed by nearby networks ordered by signal. Saved passwords have a separate section, and open networks keep their GHz labels aligned.
- **Safer Wi-Fi passwords.** Retry a rejected password inside the row. New profiles are saved after activation succeeds; failed replacements preserve existing credentials and UUIDs. Stop waiting closes the prompt without disconnecting the network. Hidden networks offer WPA/WPA2, WPA3 and open security. An unsuccessful save leaves the connection active and shows a warning.
- **Details goes to the right page.** Left-click opens Velora's corresponding Wi-Fi or Bluetooth settings; right-click opens the configured external settings, KDE by default. Background Bluetooth loading no longer changes the Wi-Fi page.
- **Screenshot cursor controls.** Choose whether screenshots include the pointer. Capture failures preserve the clipboard, and region selection no longer accidentally activates hot corners. See [the capture guide](https://github.com/FortyXD/Velora/blob/v0.1.4/docs/screen-capture.md).
- **Native shell helpers.** The installer builds the Rust connectivity daemon and helper. Passwords travel through stdin and D-Bus, rather than process arguments. App, file, clipboard and system operations also use the native helper.

Thanks to Nikita (@impala-tape) for [Wi-Fi password handling (#6)](https://github.com/FortyXD/Velora/pull/6), adapted to Velora's native backend, and [screenshot and hot-corner improvements (#7)](https://github.com/FortyXD/Velora/pull/7).

## Install or update

```bash
sudo pacman -Syu --needed git python
git clone --recurse-submodules https://github.com/FortyXD/Velora.git ~/Velora
cd ~/Velora
./velora install
```

Existing users can update through Settings → General → Software Update, or run:

```bash
velora update --interactive --channel release
```

Update the shell and `velora-connectivityd` together: this release requires connectivity protocol version 2. See [the Wi-Fi guide](https://github.com/FortyXD/Velora/blob/v0.1.4/docs/wifi.md) for password handling and troubleshooting.

The release includes an x86_64 Arch package and SHA-256 checksums. Install it with `sudo pacman -U ./velora-*.pkg.tar.zst`, then run `velora install` as your regular user. Other supported architectures can build with `./velora install --build-package --build-from-source`.

Configuration backups can be listed and restored with `velora restore`. Velora uses GPLv3; upstream credits and third-party notices are included.
