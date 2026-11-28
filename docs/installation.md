# Installing Velora on Arch Linux

## Before installation

Use a working Arch Linux system with graphics drivers, a regular user account, sudo access, and an internet connection. Install Git and Python 3.11 or newer with `sudo pacman -Syu --needed git python`. Hyprland must support the Lua configuration API used by the repository.

Run the installer as your normal user. It requests sudo for package installation and system services, including networking. Review the network choice in the plan before proceeding.

Installer diagnostics and package-manager subprocesses use an English locale so error reports remain consistent.

```bash
git clone --recurse-submodules https://github.com/FortyXD/Velora.git ~/Velora
cd ~/Velora
./velora install --dry-run
./velora install
```

Running `./velora` in a terminal opens the same guided installer. `./install.sh` and `./setup install` also use this installer for compatibility.

Before asking for confirmation, the plan lists the existing paths Velora will back up and replace. A listed directory such as `~/.config/hypr` or `~/.config/kitty` is replaced as a whole, including custom files inside. A foreign symlink is backed up as a link. Review this list with `--dry-run` or decline at the final prompt to keep the current configuration. An unattended `--yes` run prints and accepts the same plan.

## Choosing components

The desktop and shell components are required. The default Kitty/tmux shell and its prompt dependencies are included in the required components. The installer offers optional applications, Toolbox dependencies, additional fonts and themes, and video wallpaper support. Press Enter to keep the displayed selection, enter component numbers to choose optional components, or enter `none` for the required components only.

```bash
./velora components
./velora install --without toolbox,live-wallpapers
```

Choices are saved in `$XDG_STATE_HOME/velora/installation.json` and reused by updates. Excluding a component omits its dependency installation; shared shell code and configuration templates remain available. It does not uninstall packages you already have.

## Optional graphical login

On a new install with GDM already configured, the installer applies Velora's GDM appearance automatically on supported GNOME Shell versions. When the installed GNOME Shell or the version available in Arch's package database supports the theme, a new installation proposes GDM for the next boot on systems using stock SDDM or without an enabled login manager. Review the plan before accepting. The current login session stays running. Other active login managers can be retained.

```bash
./velora install --dry-run
./velora install --login-manager existing     # Retain the configured manager
./velora install --login-manager skip         # Skip graphical login setup
./velora install --login-manager gdm --login-theme keep
./velora install --login-theme velora         # Select GDM and its Velora theme
```

A themed migration installs GDM, validates Hyprland's Wayland session entry and applies the greeter before switching the display-manager alias. A failure to prepare the theme leaves SDDM enabled. If the account has no saved session, GDM defaults to Hyprland. Users with an existing selection can choose Hyprland from the login screen. Other configured managers retain the existing conflict checks; greetd and other managers with separate greeters must already be configured.

The installer remembers login preferences for updates. Explicit choices override saved preferences. `--skip-packages` skips login packages, theming and system service changes. Restoring an installation backup also restores the previous login manager and boot target when the installer changed them. If this installation first applied the Velora GDM theme, the same restore command recovers the original greeter settings. The [greeter guide](desktop-extras.md) covers version support, wallpaper sharing and independent theme recovery.

When adopting a running Hyprland desktop, the installer carries over an existing multi-layout XKB configuration. Later changes in Settings take precedence. A successful reload activates Velora's shortcuts and shell in the current session. Use `--no-reload` to wait until the next login.

## What the installer does

1. Validate tools, repository files, and the component selection.
2. Display configuration paths and the planned package, backup, and update behavior.
3. Install missing official packages with `pacman -Syu`, including `bluez` and `bluez-utils` for the shell's Bluetooth controls. Using `-Syu` avoids refreshing Arch's databases without a full system upgrade. A package counts as installed when another package provides it, such as `curl-git` for `curl`. Velora also reinstalls a font package if fontconfig cannot find its required family. If an adapter is detected, enable and start `bluetooth.service`; otherwise leave its service state unchanged. Discovery and pairing are not enabled automatically.
4. Install missing AUR packages with yay or paru. If needed, build yay from `https://aur.archlinux.org/yay.git` using makepkg. Use `--skip-aur` to omit this step.
5. Build the native shell tools from their Cargo lockfile or install their packaged binaries. Existing offline translation models are reused on update.
6. Verify every default font family. Arch provides Material Symbols Rounded, the two Nerd Fonts, Noto Sans, CJK and Emoji. Velora supplies Google Sans Flex, Space Grotesk and Readex Pro with their licenses. The installer verifies each file's SHA-256 and font family before publishing it in `$XDG_DATA_HOME/fonts/velora-*`, refreshes fontconfig and checks the result. This also works with `--skip-aur`. An existing `--skip-packages` installation missing only the icon font can still use the verified upstream fallback.
7. Check runtime commands for the selected components, the Qt/QML modules imported by both shell styles, and the native shell helper. A failure stops installation before configuration linking.
8. Initialize Git submodules, back up existing configuration targets, create links, and install Dolphin integrations. Hyprland parses the linked configuration before the installer registers it. A configuration error rolls back the journaled files and reports the parser diagnostic.
9. Register `~/.local/bin/velora`, the Update Velora launcher, and the user update timer.
10. Configure desktop and network services. If you opted into graphical login, verify its Hyprland session entry and configure the selected manager for the next boot.
11. Apply the update timer setting and reload a running Hyprland session unless `--no-reload` is set.

The installer enables the PipeWire and PulseAudio-compatible sockets, WirePlumber, and the user `ydotool` service. User services are enabled for the next login even when the current terminal has no user service manager. The virtual keyboard uses `/etc/modules-load.d/velora-uinput.conf`, `/etc/udev/rules.d/70-velora-uinput.rules`, and a user service override under `~/.config/systemd/user/ydotool.service.d/velora.conf`. Logind grants the active local session access to `/dev/uinput`; the daemon's socket is private to that user at `$XDG_RUNTIME_DIR/ydotool.sock`. Log in again after repairing an existing installation so the desktop inherits that socket path.

A fresh installation proposes NetworkManager for Velora's Wi-Fi controls. On the archinstall **Minimal** profile, copying the ISO network configuration can leave systemd-networkd and standalone iwd enabled. The installer lists competing services and offers to switch them at the next boot. The current connection stays up through installation. After reboot, connect from Velora and enter the Wi-Fi password once if the network was saved only in the previous manager. Static addresses configured in that manager also need a NetworkManager profile. Its original files stay on disk.

Use `--network-manager keep` to retain your network setup. A first unattended `install --yes` accepts the proposed switch. For an existing install, run `./velora deps --network-manager migrate` to schedule it explicitly, then reboot. An iwd backend configured in NetworkManager stays available. `--skip-packages` skips system service changes. The installation backup records the previous boot services when Velora switches network managers. Restoring that backup schedules the previous services for the next boot.

The required dependencies include Qt's KDE platform integration, Breeze icons and a fallback cursor theme. Bibata is used when installed; otherwise the desktop uses Breeze cursors. Kando, local AI models, MicroTeX math rendering, WARP, EasyEffects and vendor GPU switchers are optional integrations with separately installed software. Optional application shortcuts use the applications you choose to install.

Velora keeps personal settings in `$XDG_CONFIG_HOME/velora/config.json` (normally `~/.config/velora/config.json`). On upgrade, the installer imports settings, presets, actions and other files from the previous `illogical-impulse` directory. Existing Velora files take precedence. The old path points to the new directory so saved paths and custom shortcuts keep working. A fresh installation starts from the tracked example.

The remaining desktop configuration links point into the checkout. If you move or rename the checkout, run `./velora relink` from the new place.

A new desktop starts with the bundled **Autumn** wallpaper by Josef Bartoň (JoeyJazz), used with the artist's permission. **All rights reserved; commercial use of the artwork by third parties is not permitted.** Autumn, Komona Sunset and Mountain are available offline. Personal wallpaper choices are preserved. See the [wallpaper credits and terms](../licenses/wallpapers.md).

The package managers are still interactive when `--yes` is passed. The option accepts Velora's component and installation plan; it does not pass `--noconfirm` to package managers.

## Existing installations

```bash
./velora install --skip-packages      # Relink and register maintenance tools
./velora relink                       # After moving or renaming the checkout: point every link at it again
./velora install --skip-aur           # Official packages and native tools
./velora install --with-aur           # Enable AUR packages even after a saved --skip-aur
./velora install --no-reload          # Apply files without reloading Hyprland
./velora install --no-updates         # Disable scheduled update checks
./velora deps                         # Reconcile dependencies without relinking
./velora doctor                       # Inspect missing dependencies, tools and stale links
```

For `install`, `deps` and `doctor`, `--skip-aur` and `--with-aur` are mutually exclusive. With neither flag, the saved AUR preference is reused (AUR enabled by default). `install` saves the resolved choice for later installs and updates; `deps` and `doctor` can override it for that invocation.

Old `illogical-impulse-*` metapackages are no longer built or maintained by Velora. The installer does not automatically remove packages from your system. On an older installation, inspect the metapackages and their removal transaction yourself; avoid recursive dependency removal if the desktop still needs those packages.

## Backups and recovery

Backups are stored under `$XDG_STATE_HOME/velora/backups/`, normally `~/.local/state/velora/backups/`. Every installation has a unique backup directory and a JSON Lines journal recording its changed targets.

```bash
velora restore
velora restore BACKUP_ID
```

If linking, configuration validation, registration or final system setup fails, Velora restores the journaled files. These include the MIME defaults, KDE settings and existing virtual-keyboard overrides it edits. After an interruption during linking, running the same install command recovers the interrupted configuration before retrying. Release enough space or repair the reported permissions first. A successful install can also be restored with the commands above. Later user files go into the backup's `before-restore-*` directory. Existing system input rules are backed up alongside the originals with a suffix containing the backup ID. Pacman packages, system upgrades, compiled dependencies and shared services installed during preparation remain available for the retry.

Older Folis backups remain in `~/.local/state/folis/backups/`. They are kept as-is and are not listed by the new journal-based restore command.

## Common problems

| Problem | Action |
| --- | --- |
| Python or Git is missing | Install `python` and `git` using pacman. |
| An AUR build fails | Read the makepkg/helper output, fix the reported dependency, or rerun with `--skip-aur`. |
| Bluetooth adapter was connected after installation | Run `./velora deps` to enable `bluetooth.service`; `--skip-packages` skips system service setup. |
| A download fails or a package is still missing | Read the package manager's error, restore mirror or AUR access and rerun the same command. Velora checks the selected packages again before configuring services. |
| Text, icons or spacing look wrong | Run `velora doctor` to see each missing font family, then `velora deps` to repair it. Log out and back in so running Qt apps reload their fonts. `--skip-packages` requires the official font packages to be installed already. |
| Wallpaper previews fail or a Qt page does not load | Run `velora doctor`; its runtime checks name missing QML modules and native tools. Run `velora deps` to repair them. |
| Network, sound or the virtual keyboard does not work | Run `velora doctor` to inspect the relevant services. Use `velora deps --network-manager migrate` and reboot to hand networking over to NetworkManager. For audio or the keyboard, run `velora deps` and log in again. |
| The update timer cannot start | Log into the user session, then run `systemctl --user enable --now velora-update.timer`. |
| `velora` is not found | Run `./velora` from the checkout or use `~/.local/bin/velora`; add `~/.local/bin` to PATH. |
| A monitor has the wrong mode or scale | Open Settings → Displays and inspect `~/.config/hypr/custom/monitors.*`. |
| Configuration linking fails | Read the failed command; the installer restores journaled targets. Resolve the cause and rerun. |
| An update refuses local changes | Review `git status` and commit the changes you want to retain. |

## XDG locations

The installer respects `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and `XDG_STATE_HOME`. With the default values, configuration is under `~/.config`, data under `~/.local/share`, and maintenance state under `~/.local/state/velora`.

The optional offline translator keeps its engine and models in `$XDG_DATA_HOME/folis/translate`.

## Automatic source builds

The guided installer offers source builds and package installation as separate choices. The same choices are available as command-line options:

```bash
./velora install --build-from-source
./velora install --build-from-source quickshell,hyprland
./velora install --build-package --build-from-source
./velora deps --build-from-source quickshell --rebuild
./velora install --no-source-builds
```

`--build-from-source` without a list selects Hyprland and Quickshell. A list must name packages in the selected dependency components. Official recipes are fetched with `pkgctl repo clone --protocol https`; AUR recipes are cloned directly from AUR. The installer provisions the Arch build tools, runs makepkg as your regular user, and installs the result through pacman. Build and installation errors stop the attempt and retain the diagnostic output. Signature checks are preserved.

Built archives are kept under `$XDG_CACHE_HOME/velora/packages`. Recipe revisions and installed versions are recorded under `$XDG_STATE_HOME/velora/source-builds`. Unchanged stable recipes are reused; `--rebuild` forces a rebuild, and VCS recipes are rebuilt to pick up source changes. Binary-only `-bin` recipes are rejected for source builds. `--skip-aur` also excludes AUR source builds.

See the Arch manuals for [makepkg](https://man.archlinux.org/man/makepkg.8.en) and [pkgctl repo clone](https://man.archlinux.org/man/pkgctl-repo-clone.1.en).

## Installing Velora as an Arch package

```bash
./velora install --build-package
```

This builds the current project sources into a `.pkg.tar.zst` archive, installs it with pacman, and runs the packaged installer automatically. The package contains the actual shell, configuration templates, helper scripts, license notices, and maintenance tools. It does not introduce dependency metapackages.

System files are installed under `/usr/share/velora`, with a command in `/usr/bin/velora`. User configuration links point into the writable `$XDG_DATA_HOME/velora/runtime` copy. On an update, unchanged templates are refreshed. Local edits are preserved; conflicting incoming files are placed in `runtime/.incoming/` for review.

For a build without installation:

```bash
./velora package --output ./artifacts/release
```

Package builds include the current source tree, including new project files, while honoring Git exclusions. Runtime shell settings and install markers are omitted. Review local changes before distributing a package.
