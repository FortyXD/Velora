# Velora 0.2.0

Opt-in AI search, local indexing and desktop assistance, KDE file previews and dialogs, and fixes across panels, displays and installation.

## Highlights

- **Search stays optional.** AI results in the launcher and Lens indexing each have a separate switch, both off by default. Semantic/vector indexing and media analysis are also opt-in. Ordinary application and calculator search remain available.
- **Local desktop assistant.** Saved conversations, provider connections and explicit, reversible file actions are integrated into the launcher and sidebar. Existing provider and model choices are preserved.
- **Desktop files and previews.** Quick Look supports images, video, audio, PDF, text and archives. Native KDE file dialogs gain folder creation, and window previews retain their last ready frame during refresh. Dolphin selection marks are off in fresh configurations; existing explicit preferences are preserved.
- **Panel and display fixes.** Shared icons are centered, click-opened popups stay open, duplicate tray registrations are filtered, workspace previews gain visibility/dismissal options, and display arrangements support snapping and safer output changes.
- **Installation and updates.** The installer includes the new native services and Qt addon, optional Velora GDM styling, and a graphical updater that survives closing Settings. Advanced battery analytics and tmux mouse links remain opt-in.
- **First-run and reinstall repairs.** Setup opens once after wallpaper initialization. Moving the source checkout no longer leaves a stale CMake build configuration. Binary packages declare their required OpenSSL ABI.

## Validation

Checked in two Arch Linux QEMU guests: a clean installation and an existing desktop upgrade, using Hyprland 0.57.1, Quickshell 0.3.2 and Qt 6.12. The checks cover GDM login, first-run setup, repeated installation with preserved settings, configuration restoration, graphical updates, authorization cancellation, live window-preview lifecycle, Quick Look, native folder creation, panel layouts and disabled AI defaults.

The source-install scenarios use `--skip-aur --without assistant,appearance,live-wallpapers`; optional model weights are not downloaded. NetworkManager profile operations use synthetic local profiles. Physical Wi-Fi/Bluetooth, GPU-specific behavior and real model inference require separate hardware/model testing. Rust, Python/QML and native Qt checks run in CI and the guests; logs and screenshots are retained with the release validation evidence.

## Install or update

```bash
sudo pacman -Syu --needed git python
git clone --recurse-submodules https://github.com/FortyXD/Velora.git ~/Velora
cd ~/Velora
./velora install
```

Existing users can update through Settings → General → Software Update or run `velora update --interactive --channel release`.

For the Arch package, first update Arch with `sudo pacman -Syu`, install the downloaded `.pkg.tar.zst` with `sudo pacman -U`, then run `velora install` as your regular user. Run `sha256sum --check SHA256SUMS` beside the downloaded package to verify it. Log out and back in after updating native desktop components.

See the [installation guide](https://github.com/FortyXD/Velora/blob/v0.2.0/docs/installation.md), [search controls](https://github.com/FortyXD/Velora/blob/v0.2.0/docs/lens.md), and [assistant guide](https://github.com/FortyXD/Velora/blob/v0.2.0/docs/assistant.md).
