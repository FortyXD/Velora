# Velora 0.1.5

> Rebuilt on 2026-11-01 with reviewed wallpaper assets. Unverified artwork, videos and previews were removed; the default and three layouts now use Andy Betts’s Mountain (CC BY-SA 4.0). See [wallpaper sources and licenses](https://github.com/FortyXD/Velora/blob/v0.1.5/licenses/wallpapers.md).

Optional graphical login setup, an offline first desktop, and fixes for desktop security, installation and screen recording.

Velora is an independently maintained fork of Illogical Impulse for Arch Linux, Hyprland and Quickshell.

## Highlights

- **Graphical login setup.** The installer detects existing login managers and offers to reuse them. If none exists and you opt in, GDM is the default; SDDM is also available. Services are enabled for the next boot without interrupting the current session. Unattended installation does not opt in automatically. Select Hyprland in the greeter's session menu.
- **Mountain from the first start.** The Mountain wallpaper and preset preview are bundled locally and work without an internet connection. Existing wallpaper choices are retained. Japanese and Korean greeting fonts are included.
- **Safer desktop operations.** Remote image URLs and names, AI LaTeX content, and preset keys are handled as data. Sensitive requests use private temporary storage and avoid credentials in process arguments. VPN exports are private, received Bluetooth files do not overwrite existing destinations, and installation rejects unsafe filesystem links.
- **Recording and layout fixes.** Recording stops on idle screens and waits for healthy encoders to finish. The cheatsheet fits smaller displays, including portrait layouts, and the default shadow configuration no longer produces a Hyprland error.
- **Reliable installation and maintenance.** Source packages retain Rust build inputs, omit Cargo caches, repair update timers and detect missing helpers. Native helper failures reach the caller. Affected Python dependency pins are updated.

## Validation

The audit recorded 255 unique Python test methods, 339 Rust tests including three real NetworkManager cases, and 12 dependency compatibility checks with passing evidence. One live BlueZ test remained blocked by missing Bluetooth hardware in the test guest.

A dedicated Arch VM passed clean and repeated installation, GDM authentication, first startup with internet routes removed, six desktop smoke checks, configuration rollback, logout/relogin and menu shutdown. Fifteen interface views were visually inspected. Physical suspend/resume, Bluetooth transfers and every external provider have not been certified by these tests.

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

For explicit graphical login setup, use `./velora install --login-manager gdm` or `--login-manager existing`. See the [installation guide](https://github.com/FortyXD/Velora/blob/v0.1.5/docs/installation.md).

After upgrading Qt, Quickshell, Hyprland or the graphics driver, restart the desktop session or reboot so running processes use the updated components. Quickshell 0.3.2 includes upstream session-lock fixes; this release does not claim to fix every suspend or driver failure.

The release provides an x86_64 Arch package with SHA-256 checksums. Install it with `sudo pacman -U ./velora-*.pkg.tar.zst`, then run `velora install` as your regular user. Configuration backups can be listed and restored with `velora restore`.

Velora uses GPLv3. Bundled Mountain artwork is by Andy Betts, licensed separately under CC BY-SA 4.0; see `licenses/wallpapers.md`.
