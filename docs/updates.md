# Updates and dependencies

## Automatic checks, manual installation

The installer registers `velora-update.service` and `velora-update.timer` in the user's systemd configuration. The timer checks shortly after login and approximately every six hours, with a small randomized delay. It fetches the remote of the current branch's configured tracking relationship and records the result in `$XDG_STATE_HOME/velora/update.json`.

A check never installs dependencies, merges commits, changes checked-out files, or restarts the desktop. An available target triggers a desktop notification when the notification service is accessible. Settings → About reads the same status file and offers **Check for updates** and **Install update** buttons. Installation opens Kitty, the required desktop terminal, to show progress and package-manager prompts.

```bash
velora update --check
velora update --check --json
velora update --interactive
velora update --dry-run
```

A dry run compares cached Git refs without network access or state-file changes. A regular check performs a fetch and updates the status file. An explicit `velora update` applies an available update; `--interactive` adds a commit preview and confirmation.

The updater uses the branch's configured remote, typically your Velora `origin`. It does not merge Illogical Impulse changes automatically. Upstream integration remains a maintainer task.

## Applying an update

The updater checks for local changes and diverged history before replacing source files. It fast-forwards to the exact commit that was checked, then runs the updated installer with the saved component selection. The installer reconciles newly declared dependencies and the Python lockfile, refreshes links and integrations, and backs up replaced configuration files.

Local edits are never stashed or discarded automatically. Commit them before updating; if your commits and the remote have diverged, resolve that history first. Some theme and generated Hyprland files currently live in the linked checkout, so runtime changes can also require review before an update.

Source and system package changes do not form one atomic transaction. If package installation fails after the Git fast-forward, the source remains at the newer commit. Resolve the reported error and run `velora install --yes`. `$XDG_STATE_HOME/velora/last-update.json` records the previous commit and whether the installation completed. `velora status` displays it.

After a successful update, restart Quickshell or log in again to load all changed shell code. Velora does not interrupt the active shell automatically.

## Timer controls

```bash
systemctl --user status velora-update.timer
systemctl --user start velora-update.service
journalctl --user -u velora-update.service
systemctl --user disable --now velora-update.timer
```

Rerunning `velora install --no-updates` also disables scheduled checks. Checks need network access and a reachable tracking remote. A failed check records its error while retaining the previous known update information; it does not report a successful update check.

See [systemd timer documentation](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html) for scheduling behavior.

## Dependency manifest

`dependencies/arch.toml` is the source of truth for Arch packages. Each component has a description, a required/optional flag, a list of official package names, and a list of AUR package names. Shared packages are deduplicated before installation.

There are no local Velora or Illogical Impulse metapackages. The installer compares the chosen components with `pacman -Qq` and requests only missing packages. Package removals are left to the user. Existing packages continue to receive ordinary Arch/AUR updates through the system's package tools.

## Python dependencies

`dependencies/python/requirements.in` declares the shell's Python dependencies. `requirements.txt` pins their versions. The installer creates the compatible Python 3.12 environment with uv, then uses `uv pip sync` to match that lockfile.

To update the lockfile as a maintainer:

```bash
cd dependencies/python
uv pip compile --python-version 3.12 requirements.in -o requirements.txt
```

Use `--upgrade` when deliberately updating all pins, or `--upgrade-package NAME` for a selected package. Review and test the resulting changes before committing them. See [uv's locking and synchronization documentation](https://docs.astral.sh/uv/pip/compile/).

## GitHub update settings

Settings → About → GitHub updates provides controls for automatic checks and the update channel, displays installed and available versions, and opens an interactive update in a terminal.

```bash
velora update-settings
velora update-settings --channel release
velora update-settings --channel branch
velora update-settings --automatic-checks off
velora update-settings --automatic-checks on
velora update --check --channel release
```

The **release** channel checks the latest stable, published GitHub release through the GitHub API, resolves its tag, and installs the exact associated commit. If there is no published release, the check explains that condition; it does not report the installation as current. The **branch** channel follows the configured tracking branch. Prereleases are excluded from the stable release channel. See [GitHub's release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release).

Update preferences are stored in `$XDG_STATE_HOME/velora/update-settings.json`. They are shared by the CLI, Settings, and the background service. A channel passed to `velora update --channel` applies to that invocation; `velora update-settings --channel` saves the choice.

## Updating a package installation

For a system package installation, the updater compares the embedded source revision with GitHub. It clones the requested source, checks out the exact checked commit, initializes its submodules, builds the new Velora package, installs it through pacman, and reruns the packaged installer with your saved component and dependency source-build selection.

Writable user templates are refreshed separately from system package files. Local edits are retained, and conflicting incoming versions are saved under `runtime/.incoming/`. Package replacement, dependency installation, and template refresh are separate operations. If a later step fails, the preceding package or dependency changes remain installed; fix the reported error and rerun `velora install`.
