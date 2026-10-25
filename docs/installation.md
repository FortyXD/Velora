# Installing Velora on Arch Linux

## Before installation

Use a working Arch Linux system with graphics drivers, a regular user account, sudo access, and an internet connection. Install Git and Python 3.11 or newer with `sudo pacman -Syu --needed git python`. Hyprland must support the Lua configuration API used by the repository.

Run the installer as your normal user. It requests sudo for package installation and the power profile service. Read its plan and the package manager's prompts before proceeding.

Installer diagnostics and package-manager subprocesses use an English locale so error reports remain consistent.

```bash
git clone --recurse-submodules https://github.com/FortyXD/Velora.git ~/Velora
cd ~/Velora
./velora install --dry-run
./velora install
```

Running `./velora` in a terminal opens the same guided installer. `./install.sh` and `./setup install` also use this installer for compatibility.

## Choosing components

The desktop and shell components are required. The installer offers optional applications, Toolbox dependencies, additional fonts and themes, and video wallpaper support. Press Enter to keep the displayed selection, enter component numbers to choose optional components, or enter `none` for the required components only.

```bash
./velora components
./velora install --without toolbox,live-wallpapers
```

Choices are saved in `$XDG_STATE_HOME/velora/installation.json` and reused by updates. Excluding a component omits its dependency installation; shared shell code and configuration templates remain available. It does not uninstall packages you already have.

## What the installer does

1. Validate tools, repository files, and the component selection.
2. Display configuration paths and the planned package, backup, and update behavior.
3. Install missing official packages with `pacman -Syu --needed`. Using `-Syu` avoids refreshing Arch's databases without a full system upgrade. A package counts as installed when another package provides it, such as `curl-git` for `curl`.
4. Install missing AUR packages with yay or paru. If needed, build yay from `https://aur.archlinux.org/yay.git` using makepkg. Use `--skip-aur` to omit this step.
5. Create the shell's Python 3.12 environment with uv and synchronize the committed lockfile.
6. Download the Google Sans Flex interface font into `~/.local/share/fonts/velora-google-sans-flex` when fontconfig does not already provide it. Arch does not package it; a failed download only prints a warning, and `velora deps` retries it.
7. Initialize Git submodules, back up existing configuration targets, create links, and install Dolphin integrations.
8. Register `~/.local/bin/velora`, the Update Velora launcher, and the user update timer.
9. Reload a running Hyprland session unless `--no-reload` is set.

The installer preserves an existing `illogical-impulse/config.json` and seeds a missing one from the tracked example. Linked configuration files take effect from the checkout. Keep that directory after installation. If you move or rename it, run `./velora relink` from the new place.

The package managers are still interactive when `--yes` is passed. The option accepts Velora's component and installation plan; it does not pass `--noconfirm` to package managers.

## Existing installations

```bash
./velora install --skip-packages      # Relink and register maintenance tools
./velora relink                       # After moving or renaming the checkout: point every link at it again
./velora install --skip-aur           # Official packages and Python environment
./velora install --no-reload          # Apply files without reloading Hyprland
./velora install --no-updates         # Disable scheduled update checks
./velora deps                         # Reconcile dependencies without relinking
./velora doctor                       # Inspect missing dependencies, tools and stale links
```

Old `illogical-impulse-*` metapackages are no longer built or maintained by Velora. The installer does not automatically remove packages from your system. On an older installation, inspect the metapackages and their removal transaction yourself; avoid recursive dependency removal if the desktop still needs those packages.

## Backups and recovery

Backups are stored under `$XDG_STATE_HOME/velora/backups/`, normally `~/.local/state/velora/backups/`. Every installation has a unique backup directory and a JSON Lines journal recording its changed targets.

```bash
velora restore
velora restore BACKUP_ID
```

If linking or registration fails, the installer immediately restores journaled configuration files. Installed packages, Python environment changes, and external application settings are outside this file rollback. A successful installation can be restored later with the same command. Later target files are moved into the backup's `before-restore-*` directory rather than discarded.

Older Folis backups remain in `~/.local/state/folis/backups/`. They are kept as-is and are not listed by the new journal-based restore command.

## Common problems

| Problem | Action |
| --- | --- |
| Python or Git is missing | Install `python` and `git` using pacman. |
| An AUR build fails | Read the makepkg/helper output, fix the reported dependency, or rerun with `--skip-aur`. |
| A package download fails | Check network access and Arch mirrors, then rerun the installer. |
| Python environment setup fails | Read uv's error. Check network access and build prerequisites, then run `velora deps`. |
| The update timer cannot start | Log into the user session, then run `systemctl --user enable --now velora-update.timer`. |
| `velora` is not found | Run `./velora` from the checkout or use `~/.local/bin/velora`; add `~/.local/bin` to PATH. |
| A monitor has the wrong mode or scale | Open Settings → Displays and inspect `~/.config/hypr/custom/monitors.*`. |
| Configuration linking fails | Read the failed command; the installer restores journaled targets. Resolve the cause and rerun. |
| An update refuses local changes | Review `git status` and commit the changes you want to retain. |

## XDG locations

The installer respects `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and `XDG_STATE_HOME`. With the default values, configuration is under `~/.config`, data under `~/.local/share`, and maintenance state under `~/.local/state/velora`.

Hyprland's current environment configuration still selects the default `~/.local/state/quickshell/.venv` Python environment. If you use a custom state directory, update `~/.config/hypr/hyprland/env.lua` to use the same location.

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
