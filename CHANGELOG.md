# Changelog

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
