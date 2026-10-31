# Velora 0.1.3

Guided setup, more ways to manage windows, smooth appearance changes, and configurable screen recording.

Velora is an independently maintained fork of Illogical Impulse, built for Arch Linux with Hyprland and Quickshell.

## Highlights

- **Wi-Fi, VPN and Bluetooth settings without leaving Velora.** See every saved network with its password and protocol, edit any connection, add OpenVPN and WireGuard VPNs, and manage Bluetooth devices, including PIN pairing and file transfer. This needs the new `velora-connectivityd` service, built by the installer with Rust.
- **Guided first run.** Set language and keyboard layouts, networking, displays, window behavior, appearance and optional apps in the new assistant. A desktop tour introduces the shell. Reopen setup with Shift+Super+Alt+/.
- **Windows and apps.** Choose tiled or free windows, with snapping, minimizing, restoring, snap layouts and a window menu. Use Alt+Tab for window previews, add a taskbar to the bar, or open the application library with Super+Shift+Space. Configure touchpad gestures with visual hints.
- **Smooth wallpapers and themes.** Each wallpaper keeps its own geometry during crossfades. Presets prepare wallpapers and colors before transitioning. A native helper handles palettes, theme staging and desktop widget placement. Wallpaper scaling stays correct when displays or fractional scaling change.
- **Screen recording controls.** Choose region or screen capture, audio sources and devices, frame rate, quality, MP4/MKV, delay and destination. Microphone capture requires an explicit choice. Recording survives shell reloads and verifies the video before reporting it saved. Right-click the bar's recording button to open its settings. See [the recording guide](https://github.com/FortyXD/Velora/blob/v0.1.3/docs/screen-recording.md).
- **Settings and desktop polish.** General settings now open dedicated Software Update, Storage, Language & Region, and Date & Time pages. The session screen, tooltips and tray menus have been refreshed, with expanded Russian translations.
- **More complete installation checks.** Setup verifies fonts, commands, QML modules and Python/GTK imports before linking configuration, and configures audio, the virtual keyboard and NetworkManager when appropriate. `velora doctor` reports missing dependencies and service problems. Existing alternative network managers are preserved.

Thanks to Nikita (@impala-tape) for [screen recording improvements (#4)](https://github.com/FortyXD/Velora/pull/4) and [reactive wallpaper scaling (#5)](https://github.com/FortyXD/Velora/pull/5).

## Install

```bash
sudo pacman -Syu --needed git python
git clone --recurse-submodules https://github.com/FortyXD/Velora.git ~/Velora
cd ~/Velora
./velora install
```

To build Velora and its core dependencies from source:

```bash
./velora install --build-package --build-from-source
```

Review monitors, keyboard layout and wallpaper paths for your machine after installation. This release targets Arch Linux and Hyprland's Lua configuration API. The Arch package includes native code; use the artifact for your architecture. The release workflow supplies an x86_64 package; aarch64 users can build from source.

Install a downloaded package with `sudo pacman -U ./velora-*.pkg.tar.zst`, then run `velora install` as your regular user. Audio and virtual-keyboard repairs on existing installations may require logging out and back in.

## Updates and recovery

Open Settings → General → Software Update, select published releases and install the update, or run:

```bash
velora update --interactive --channel release
```

Configuration backups can be listed and restored using `velora restore`.

Velora uses GPLv3. Upstream author credits and third-party notices are included in the repository and package.
