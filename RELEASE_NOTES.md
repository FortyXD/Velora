# Velora 0.1.1

Build either sidebar from the parts you use, arrange them in a live preview, and keep your desktop settings through updates.

Velora is an independently maintained fork of Illogical Impulse, built for Arch Linux with Hyprland and Quickshell.

## Highlights

- **Sidebars made from parts.** Place media, weather, clipboard history, notes, system graphs, quick tools, notifications, sliders and other parts in either sidebar. Move parts between sidebars, group them into tabs, and undo layout changes. Existing sidebar layouts are preserved.
- **Editors that keep the layout in view.** The Sidebars page shows a preview beside the selected part's settings. The Bar and Lock Screen pages keep their previews visible while their settings scroll.
- **Nine new moving wallpaper looks.** Illustrated and anime scenes replace the three nature videos. Downloaded videos play in preset previews, and applying another look cancels an older download's pending wallpaper change.
- **Updates preserve generated settings.** Wallpaper colors and files written by Settings are no longer tracked by Git. New installations use default templates, and updates preserve local copies.
- **Repair a moved checkout.** Run `./velora relink` after moving or renaming the checkout. `velora doctor` reports missing or stale links, and the update timer follows the new location.
- **Playback and saving fixes.** Qt video playback uses VA-API to avoid waking a hybrid laptop's NVIDIA GPU. Failed settings saves show a notification, and Hyprland reloads are skipped when its configuration is unavailable.

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
