# Velora 0.1.2

Better touchpad defaults, Bluetooth setup, clearer network activity, and fixes for laptop brightness and moving wallpapers.

Velora is an independently maintained fork of Illogical Impulse, built for Arch Linux with Hyprland and Quickshell.

## Highlights

- **Touchpad right-click choices.** Tap-to-click is enabled by default, including two-finger taps for right click. Open Settings with Super+I, then Mouse & Touchpad → Touchpad to choose a bottom-right corner press or a two-finger physical click. Existing custom overrides are preserved; systems without overrides adopt the new defaults.
- **Bluetooth ready during setup.** The installer includes BlueZ and starts its service when an adapter is detected. `--skip-packages` preserves package, Python environment and service state for both installation and `velora deps`.
- **Upright Wi-Fi symbols.** A separate ring shows connection or scan activity without spinning Wi-Fi and lock symbols. Hidden indicators stop animating, and background scans do not animate the bar's connection indicator.
- **Brightness on hybrid GPU laptops.** Controls select the backlight belonging to the connected screen, avoiding an unused GPU's backlight.
- **Sharper moving wallpapers.** Video loops retain source resolution up to 4K with higher encoding quality. Older loops are rebuilt in the background when their look is applied. Playback uses sharper scaling, and lock-screen still frames use higher JPEG quality.

## Install

```bash
sudo pacman -Syu --needed git python
git clone --recurse-submodules https://github.com/FortyXD/Velora.git ~/Velora
cd ~/Velora
./velora install
```

The installer offers automatic source builds for dependencies and an option to build and install Velora itself as an Arch package. Both can be enabled with:

```bash
./velora install --build-package --build-from-source
```

Review monitors, keyboard layout, and wallpaper paths for your machine after installation. This release targets Arch Linux and Hyprland's Lua configuration format.

If you downloaded the Arch package, install it with `sudo pacman -U ./velora-*.pkg.tar.zst`, then run `velora install` as your regular user.

## Updates and recovery

Use Settings → About → GitHub updates to select stable releases and install a new version, or run:

```bash
velora update --interactive --channel release
```

Configuration backups can be listed and restored using `velora restore`.

Velora uses GPLv3. Upstream author credits and third-party notices are included in the repository and package.
