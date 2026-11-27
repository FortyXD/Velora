# Velora 0.2.2

You can now compare a preset with your current desktop by dragging a divider, choose which parts to apply, and revisit your three most recent wallpapers. The README includes eleven recordings of the current interface, from first-run setup to editing the panel.

## Desktop and settings

- Preview built-in live wallpapers and choose an image, animated image or muted video for the lock screen. The GDM login screen can follow the desktop, match the lock screen or use a separate file.
- Explore disk usage, assign default apps by role and file type, and see keyboard layouts and shortcuts on a visual map.
- Power analytics shows measured battery discharge and the estimated share used by individual applications. btop and tmux follow your terminal palette. A fresh neofetch configuration displays the two-color Velora logo.

## Connections and the local assistant

- Network & VPN can import connection files, proxy links and subscriptions. The optional VPN component includes NetworkManager plugins and sing-box.
- The opt-in local assistant can work with an attached folder, propose file changes for approval and operate controls exposed through application accessibility. You can choose trusted folders, set model context and memory retention, and enable model preparation after login. [Assistant guide](https://github.com/FortyXD/Velora/blob/v0.2.2/docs/assistant.md)

## Community contributions

Thanks to @YakuninVladimir for bringing the desktop palette and built-in shader wallpapers to GDM, repairing dependencies on existing Hyprland installations, and setting up the Velora login screen during installation. [#27](https://github.com/FortyXD/Velora/pull/27) · [#28](https://github.com/FortyXD/Velora/pull/28) · [#29](https://github.com/FortyXD/Velora/pull/29) · [#30](https://github.com/FortyXD/Velora/pull/30)

## Install or update

Existing users can open **Settings → General → Software Update** or run `velora update --interactive --channel release`. Updates started in Settings continue when the window closes. Reopen it to see progress or finish a pending installation.

The installer imports settings, presets and actions from `~/.config/illogical-impulse/` into `~/.config/velora/`. Existing files in the Velora directory take precedence. Custom shortcuts can continue to use the old path. [Upgrade guide](https://github.com/FortyXD/Velora/blob/v0.2.2/docs/updates.md)

For a package install, download the Arch package and `SHA256SUMS` into the same directory. Run `sha256sum --check SHA256SUMS`, update Arch with `sudo pacman -Syu`, then install the downloaded file with `sudo pacman -U ./velora-*.pkg.tar.zst`. Run `velora install` as your regular user, then log out and back in. [Installation guide](https://github.com/FortyXD/Velora/blob/v0.2.2/docs/installation.md)

The package includes the matching Velora source, shape submodule, Cargo lockfiles and build scripts in `/usr/share/velora/`. The GPL and author notices are installed in `/usr/share/licenses/velora/`. [Velora 0.2.2 source](https://github.com/FortyXD/Velora/tree/v0.2.2)
