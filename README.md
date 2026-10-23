# Velora

**A desktop shaped around you.**

Velora is a customizable desktop shell for **Arch Linux**, built with **Hyprland** and **Quickshell**. Arrange your bar, build a desktop layout, switch complete looks, and manage everyday tasks through one settings app.

Velora is an independently maintained fork of [Illogical Impulse by end-4](https://github.com/end-4/dots-hyprland). It develops that foundation into its own desktop experience, with visual layout editors, expanded system controls, integrated tools, and a dedicated installation and update workflow.

[Install](#installation) · [Features](#features) · [Updates](#updates) · [Documentation](#documentation) · [License](#license)

## Features

### Make the desktop yours

- **Bar editor.** Drag widgets into five placement zones, group them into pills, set click and scroll actions, and import or export layouts. Choose floating bars, islands, transparency, outlines, and custom spacing.
- **Desktop widgets.** Arrange clocks, weather, media controls, and productivity widgets directly on the desktop.
- **Complete looks.** Save and apply presets covering wallpaper, colors, bar, dock, widgets, and window animations. Choose which parts to apply and undo a change.
- **Lock screen editor.** Position and configure the clock, password field, greeting, weather, media, notifications, and other elements with a live preview.
- **Wallpaper collection.** Use local images, online providers, daily wallpapers, video playback through mpvpaper, or built-in animated shader backgrounds.

### Keep everyday controls close

- **Sound.** Select input and output devices, balance channels, adjust per-app audio, view microphone levels, and record a microphone test.
- **Notifications.** Keep Do Not Disturb across restarts and choose banner, history-only, blocked, or priority behavior per application.
- **Power saving.** Reduce animations, blur, wallpaper playback, previews, visualizers, and polling. Apply automatically on battery or toggle it yourself.
- **Quick settings and hot corners.** Customize sidebar controls and assign corner actions for search, panels, screenshots, locking, or your own commands.
- **Keyboard controls.** Preview layouts and pressed keys, manage switching behavior, and edit shortcuts.
- **Timers.** Use a countdown, stopwatch, or Pomodoro timer from the sidebar or command line.

### Tools built into the workflow

The Toolbox combines media and document conversion, video downloads through yt-dlp, QR generation and scanning, OCR, and color tools. Dolphin context menus expose conversions and other actions directly from your files. Office document conversion uses LibreOffice when installed.

The shell also includes application search, workspace previews, clipboard history, media controls, and the Illogical Impulse foundation's assistant and translation features.

## Installation

Velora currently supports **Arch Linux only** and uses Hyprland's Lua configuration format. Start from a working Arch installation with graphics drivers, a normal user account, network access, and sudo configured.

```bash
sudo pacman -Syu --needed git python

git clone --recurse-submodules https://github.com/FortyXD/Velora.git ~/Velora
cd ~/Velora
./velora install
```

Velora is developed at [FortyXD/Velora](https://github.com/FortyXD/Velora).

The installer guides you through optional components, shows its plan before applying changes, installs missing dependencies, prepares a locked Python environment, and backs up configuration files before linking them. Existing shell settings are preserved. If configuration linking fails, it restores the files changed by that attempt.

Official packages come from pacman. AUR packages use an existing **yay** or **paru** installation; if neither is available, the installer builds yay from its AUR recipe. Package managers retain their normal prompts. Velora uses actual dependencies rather than the old `illogical-impulse-*` metapackages.

Preview the full plan without changing files:

```bash
./velora install --dry-run
```

For an existing system with dependencies already installed:

```bash
./velora install --skip-packages
```

Optional components can be selected in the installer or excluded explicitly:

```bash
./velora components
./velora install --without toolbox,live-wallpapers
```

Build the core dependencies from source automatically, build Velora itself as an Arch package, or combine both:

```bash
./velora install --build-from-source
./velora install --build-package
./velora install --build-package --build-from-source
```

To build selected dependencies, use `--build-from-source quickshell,hyprland`. Source recipes are fetched from Arch's packaging repositories or AUR and built with makepkg. Your selection is reused during updates.

To produce a package archive without installing it:

```bash
./velora package --output ./artifacts/release
```

The Velora package contains the shell's actual source and maintenance tools. Package installations keep writable configuration under `~/.local/share/velora/runtime/` and preserve local edits when refreshing templates.

`--skip-aur` omits AUR packages, `--no-reload` keeps the current Hyprland session running without a reload, and `--no-updates` disables scheduled update checks. `--yes` accepts the installer plan for unattended use; pacman and AUR helpers still prompt normally.

For checkout installations, keep the checkout in place: configuration links point into it. Open **Settings → Displays** and verify your monitors, resolution, scale, keyboard layout, and wallpaper path before relying on the configuration on another machine. The included configuration contains the maintainer's display defaults.

See the [installation guide](docs/installation.md) for prerequisites, recovery, and troubleshooting.

## First steps

| Shortcut | Action |
| --- | --- |
| `Super` | Application search |
| `Super+I` | Settings |
| `Super+/` | Shortcut reference |
| `Super+Alt+J` | Bar editor |
| `Super+Shift+I` | Toolbox |
| `Super+N` | Quick settings and notifications |
| `Super+L` | Lock the screen |

Use **Settings → Presets** to save your current look. Use **Settings → Wallpaper** for local images, online sources, live wallpapers, and animated backgrounds. Unsplash, Pexels, and Pixabay require your own API keys.

## Updates

Open **Settings → About → GitHub updates** to check for a new version, choose published GitHub releases or changes on your tracked branch, and enable or disable automatic checks. The page shows installed and available versions. Background checks run approximately every six hours; opening the page also checks when automatic checks are enabled.

When a version is available, choose **Install update**, or find **Update Velora** in the application launcher. Package installations automatically build and install a new Velora package from the selected GitHub source. The terminal shows progress and lets you confirm installation.

```bash
velora update --check
velora update --interactive
velora update-settings --channel release
```

Updates reconcile dependencies and source builds, refresh the locked Python environment, and rerun the installer using your saved choices. In checkout installations, uncommitted work or diverged history must be resolved before updating. Package installations retain edited runtime templates and save conflicting incoming templates for review.

```bash
velora doctor        # Diagnose missing tools, packages and Python environment
velora status        # Inspect installation and update state
velora restore       # List configuration backups
velora restore ID    # Restore a chosen backup
```

If `velora` is not on your PATH yet, use `./velora` from the checkout or `~/.local/bin/velora`.

[Update behavior and recovery](docs/updates.md)

## Project layout

```text
velora                 User-facing installation and maintenance command
scripts/               Installer, linking and update implementation
dependencies/          Arch dependency components and Python lockfile
packaging/             Arch package recipe template
dots/.config/          Desktop shell and application configuration
dots/.local/share/     Desktop integration, assets and helper scripts
home/                  Shell entry files
dots-extra/            Optional application configurations and font sets
docs/                  Installation, updates and development guides
tests/                 Installer and updater regression tests
licenses/              Third-party notices and license texts
```

Internal paths such as `quickshell/ii`, `illogical-impulse`, and `folis` remain in use for compatibility with existing configurations and integrations.

## Documentation

- [Installation and recovery](docs/installation.md)
- [Updates and dependency management](docs/updates.md)
- [Development and repository structure](docs/development.md)
- [Release process](docs/release.md)
- [Third-party licensing](licenses/README.md)

Report Velora issues in [this repository](https://github.com/FortyXD/Velora/issues). Include the relevant command, its output, and `velora doctor` results.

## Credits

Velora builds on the work of **end-4 and the Illogical Impulse contributors**, **outfoxxed and Quickshell contributors**, and **Hyprland contributors**. Additional upstream acknowledgements are retained in [NOTICE](NOTICE), with component-specific attribution in [licenses/README.md](licenses/README.md).

## License

Velora is distributed under the **GNU General Public License, version 3**. See [LICENSE](LICENSE) and [NOTICE](NOTICE). Third-party code and assets retain their respective licenses and attribution.
