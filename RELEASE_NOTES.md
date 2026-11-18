# Velora 0.2.1

Desktop tools start faster, long notes use less memory, and the screen recorder sleeps while waiting for work.

## Desktop tools and Notes

- Toolbox, Quick Look, window preview management, wallpaper palettes, screen recording and battery analytics now use Rust helpers. Offline translation starts on demand and works with existing model files.
- Notes used to create a copy button for every list entry, including those far outside the viewport. In a local test with 1,000 entries it created 10 buttons after the change. CPU time in that test fell from 0.71 to 0.26 seconds and peak memory from 162 to 109 MiB. These figures describe the test workload. Battery life was not measured.
- In local startup measurements, generating a QR code took 4 ms, down from 52 ms. The offline translator returned its first response in 177 ms, down from 225 ms.

## Windows, settings and notifications

- The floating window mode gains compositor controls for the canvas, window frames and captions on Hyprland 0.57.0. Settings adds controls for touchpad gestures and shortcuts.
- Settings includes display and pointer controls, a microphone monitor, a theme palette editor, notification quiet hours and banner placement. The panel editor, window previews and lock screen also received updates.

## Community fixes

Thanks to @impala-tape for all four contributions.

- Interactive Zsh sessions save and share command history. [#21](https://github.com/FortyXD/Velora/pull/21)
- The installer and diagnostics honor an explicit `--with-aur` or `--skip-aur` even when a different preference was saved. [#22](https://github.com/FortyXD/Velora/pull/22)
- Dragging a recording region into a hot corner no longer triggers its action. Cancelling the selection re-enables hot corners. [#23](https://github.com/FortyXD/Velora/pull/23)
- Wi-Fi password prompts distinguish networks with the same name and different security settings. Editing a saved profile preserves changes made concurrently through NetworkManager. [#24](https://github.com/FortyXD/Velora/pull/24)

## Install or update

Existing users can update through Settings → General → Software Update or run `velora update --interactive --channel release`.

For a package install, download the Arch package and `SHA256SUMS` into the same directory, run `sha256sum --check SHA256SUMS`, update Arch with `sudo pacman -Syu` and install the downloaded file with `sudo pacman -U ./velora-*.pkg.tar.zst`. Run `velora install` as your regular user, then log out and back in. [Installation guide](https://github.com/FortyXD/Velora/blob/v0.2.1/docs/installation.md)
