# Changelog

## 0.1.2 — 2026-10-29

- Brightness controls select the backlight belonging to the connected screen on hybrid GPU laptops, instead of sometimes changing an unused GPU's backlight.
- Moving wallpapers keep the full resolution of their source, up to 4K, instead of 1440p, and are encoded at a higher quality. A video made by an earlier version is made again in the background when its look is applied: the look switches at once with the older video, and the new one replaces it when ready.
- Videos are scaled to each screen's size with spline36 instead of bilinear filtering, which is sharper. The still frame shown on the lock screen is saved at a higher JPEG quality.
- Touchpad defaults enable tap-to-click and bottom-right physical clicks. Mouse & Touchpad settings offer a choice between corner and two-finger physical clicks, with tapping controlled separately. Existing custom overrides are preserved; installations without overrides use the new defaults.
- Installs and dependency setup include BlueZ and enable Bluetooth when an adapter is detected. `--skip-packages` leaves packages, the Python environment and system services unchanged, including when used with `velora deps`.
- Wi-Fi status symbols stay upright during connection changes, with a separate activity ring that stops while hidden. Background scans do not animate the bar's connection indicator.

## 0.1.1 — 2026-10-25

- Both sidebars are made of parts you choose and arrange, and any part can go in either sidebar, on its own or as a tab: the top row, sliders, quick toggles, notifications, calendar, to-do, timer, the assistant, translator and image browser, plus new parts:
  - **Media:** what's playing, with its cover and controls.
  - **Weather:** now, the next hours, the coming days and details.
  - **Clipboard:** your copy history, searchable; click to copy again.
  - **Notes:** the overlay's notes, kept in sync.
  - **System:** processor, memory and swap with graphs, network speed, battery and updates.
  - **Quick tools:** screenshot, recording, color picker, text from the screen, screen search, emoji, music recognition, QR codes, file conversion and your own apps.
- The Sidebars page keeps a picture of the sidebar in place beside the settings: drag parts, hide them, click one to set it up, move it to the other sidebar or into tabs, and add parts from a catalog. New installs get a left sidebar with media, weather, quick tools and tabs for the assistant, translator, clipboard and notes; existing sidebars stay as they were.
- The Bar page keeps the bar in view: a strip of the screen with the bar at its edge stays on top, with Widgets, Look, Behavior and Ready-made bars in tabs below, each scrolling on its own, and the selected widget's card beside the catalog.
- Nine new looks with hand-drawn and anime moving wallpapers in place of the three nature videos. Each video is cut to a stretch that repeats without a jump, with a short crossfade where it starts over, and saved at 1440p and 30 fps.
- Looks with moving wallpapers now pause only under a fullscreen window instead of under any window.
- A look's video plays on its card once it has been downloaded; cards no longer stream clips from the web.
- Applying another look while a wallpaper is still downloading no longer switches back to the first one when the download finishes.
- `velora relink` points every configuration link at the checkout again after it was moved or renamed, and `velora doctor` reports links that are missing or point elsewhere. The update timer follows a moved checkout.
- Settings that fail to save now show a notification instead of failing silently.
- Colors generated from the wallpaper and files written by the settings app are no longer tracked by Git, so changing a look or a setting no longer blocks `velora update`. Updates keep your copies.
- Hyprland is no longer reloaded while its configuration can't be reached.
- Video playback in the shell and the settings app uses VA-API only. On laptops with an NVIDIA GPU, Qt no longer wakes the GPU, and once that GPU has crashed it no longer hangs the settings app.

## 0.1.0 — 2026-10-23

First Velora release, developed from Illogical Impulse.

- Customizable bar layouts, desktop widgets, appearance presets, and lock screen editing.
- Expanded sound, networking, notifications, keyboard, and power controls.
- Local, online, video, and shader wallpapers.
- Integrated conversion, downloads, QR, OCR, and color tools.
- Arch-only guided installation with component selection, dependency checks, configuration backups, and recovery.
- Automatic dependency source builds and a self-contained Velora Arch package.
- GitHub branch and stable-release update channels with Settings controls, showing the result and time of the last check; turning on automatic checks sets up the background timer when needed.
- English installation, maintenance, development, and release documentation.
- GPLv3 licensing with upstream and third-party attribution.
- Lock screen editor: drag the clock, greeting, password field, music, weather, notification count and timer in a live miniature or at full size, with animations on locking and unlocking and live wallpapers kept moving behind the blur.
- Weather from met.no with Open-Meteo and wttr.in as fallbacks, located by GPS, a city or the IP address, with an hourly and three-day forecast.
- Six looks with moving wallpapers: three freely licensed videos and three animated backgrounds drawn by the shell. Preset cards play a clip on hover and can be filtered to moving wallpapers.
- Looks can carry a lock screen arrangement.
- The Sidebars page shows each part of the right sidebar as a card in sidebar order, with its own settings, arrows, and a switch. Parts and quick toggles can be dragged in the live pictures; the others make room as you drag.
- Dragging in settings previews keeps working while the page could scroll.
- The installer installs the Qt modules, fonts, and tools the shell needs (Qt 5 Compat, Qt Positioning, the Qt Multimedia FFmpeg backend, Kirigami, KSyntaxHighlighting, libnotify, Material Symbols, Google Sans Flex, and others) and treats packages provided by alternatives such as `curl-git` as installed.
