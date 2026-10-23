# Velora 0.1.0

A desktop shaped around you, built for Arch Linux with Hyprland and Quickshell.

Velora is an independently maintained fork of Illogical Impulse. This first release brings visual layout editors, complete appearance presets, expanded system controls, wallpaper services, an integrated Toolbox, and dedicated installation and update tooling.

## Highlights

- **Bar, sidebars and lock screen you arrange yourself.** Drag bar widgets into zones, reorder and hide the parts of the sidebars, and place everything on the lock screen in a live miniature or at full size.
- **Looks in one click.** Complete looks with their own wallpaper, colors, bar, widgets and lock screen, including six with moving wallpapers: videos or animations drawn by the shell that pause whenever you can't see them.
- **Everyday controls.** Wi-Fi, Bluetooth, sound with per-app volume and a microphone test, notification rules, keyboard and shortcuts, hot corners, timers, weather with a forecast, and energy saving on battery.
- **Toolbox.** Convert media and documents, download videos, read and make QR codes, extract text with OCR and pick colors.

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

Use Settings → About → GitHub updates to select branch updates or stable published releases and install a new version. Configuration backups can be listed and restored using `velora restore`.

Velora uses GPLv3. Upstream author credits and third-party notices are included in the repository and package.
