# Updates and dependencies

## Automatic checks, manual installation

The installer registers `velora-update.service` and `velora-update.timer` in the user's systemd configuration. The timer checks shortly after login and approximately every six hours, with a small randomized delay. It fetches the remote of the current branch's configured tracking relationship and records the result in `$XDG_STATE_HOME/velora/update.json`.

An available update triggers a desktop notification when the notification service is accessible. Settings → General → Software Update reads the same status file and offers **Check for updates** and **Install update**. Installation runs in a user service, so you can close Settings and reopen it to see progress. System changes request administrator authorization when needed.

```bash
velora update --check
velora update --check --json
velora update --interactive
velora update --dry-run
```

A dry run compares cached Git refs without network access or state-file changes. A regular check performs a fetch and updates the status file. An explicit `velora update` applies an available update; `--interactive` adds a commit preview and confirmation.

The updater uses the branch's configured remote, typically your Velora `origin`. Maintainers integrate changes from upstream projects.

## Applying an update

The updater checks for local changes and diverged history before replacing source files. It fast-forwards to the exact commit that was checked, then runs the updated installer with the saved component selection. The installer reconciles newly declared dependencies and the Python lockfile, refreshes links and integrations, and backs up replaced configuration files.

The updater preserves personal shell settings and generated Hyprland files. If it reports edits to project source, review them with `git status`. If the branch has diverged, reconcile your commits with its tracked branch.

If package installation fails after the Git fast-forward, the source stays at the newer commit. Resolve the reported error and run `velora update` again or select **Finish update** in Settings. The updater resumes installation with your saved choices. `velora status` shows the previous commit and whether installation completed.

After a successful update, restart Quickshell or log in again to load all changed shell code. Velora does not interrupt the active shell automatically.

### Upgrading from the Illogical Impulse settings directory

Use **Install update** in Settings or run `velora update` as usual. The installer imports your configuration, presets, actions and other personal files from `~/.config/illogical-impulse/` to `~/.config/velora/`. Existing files in the Velora directory take precedence. The old path continues to work for shortcuts. Both paths respect `XDG_CONFIG_HOME`.

If you already received the new files through `git pull` or pacman, the same command finishes the migration. A background check only reports it. After migration, an ordinary check reports the installation as current.

Some older Velora Git installations report a custom action or prompt as an untracked source edit and pause the first update. Run `git status --short --untracked-files=all` in your Velora checkout. If it lists only personal files under `?? dots/.config/illogical-impulse/`, use the following commands in that checkout to resume the update on your selected channel.

```bash
printf '\n/dots/.config/illogical-impulse/*\n' >> "$(git rev-parse --git-path info/exclude)"
./velora update
```

The exclude entry applies only to untracked files in the old settings directory. Git continues to report edits to tracked project files.

If your checkout comes directly from `end-4/dots-hyprland`, follow the [Velora installation guide](installation.md) in a separate Velora checkout. The installer imports the existing settings, and subsequent updates follow Velora.

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

The installer compares the chosen components with `pacman -Qq` and requests only missing packages. Package removals are left to the user. Existing packages continue to receive ordinary Arch/AUR updates through the system's package tools.

## Native desktop tools

The updater builds the shell helpers using `tools/Cargo.lock` or installs their packaged binaries. The offline translator uses its own Cargo lockfile and reuses existing models in `$XDG_DATA_HOME/folis/translate/models`.

## GitHub update settings

Settings → General → Software Update lets you choose a channel, toggle automatic checks, and follow installation progress while the user service runs.

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

Writable user templates are refreshed separately from system package files. Local edits are retained, and conflicting incoming versions are saved under `runtime/.incoming/`. If installation stops after the package was replaced, fix the reported error and run `velora update` to finish.
