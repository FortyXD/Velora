# README screenshots

The README gallery shows Velora's actual Quickshell settings app. Images are stored locally in [`.github/assets/screenshots/`](../.github/assets/screenshots/) so they remain available with the repository, without an external image host.

## Gallery contents

| File | Settings page | What it shows |
| --- | --- | --- |
| `appearance.png` | Appearance | The built-in live preview of the wallpaper, bar, window colors, and styling. |
| `bar.png` | Bar | The visual bar layout editor and placement controls. |
| `widgets.png` | Widgets | Desktop widget selection and clock settings. |
| `lock.png` | Lock Screen | The lock screen layout editor and its live preview. |
| `desktop.png` | Desktop & Dock | The workspace preview and window tiling layout controls. |

The images use an isolated English demo profile, the display name **Velora**, the bundled default wallpaper, a custom lavender accent palette, and a configured lock screen layout. They illustrate one possible configuration. Desktop and lock screen miniatures inside the app are live previews, rather than captures of a running desktop or an active lock screen.

The settings content was captured with Qt Quick's `grabToImage` using a temporary capture wrapper. Window controls and page layouts come from the project source. The wrapper and demo profile are outside the repository; personal configuration, messages, and other applications are excluded.

The [Velora banner](../.github/assets/velora-banner.svg) is a native SVG illustration. It is branding artwork, separate from the application screenshots.

## Refreshing the gallery

1. Use a separate demo account or an isolated XDG profile with English selected. Keep credentials, notification history, private files, and identifying account details out of the profile.
2. Start the settings app from the source tree. For example, open Appearance:

   ```bash
   QS_SETTINGS_PAGE=appearance qs -p dots/.config/quickshell/ii/settings.qml
   ```

3. Use the same window dimensions and theme for each image. Wait for page transitions, fonts, and previews to finish loading. Capture the settings window only. With grim and slurp installed, select the window's bounds:

   ```bash
   grim -g "$(slurp)" /tmp/velora-appearance.png
   ```

4. Inspect the result at full size before replacing an asset. Keep text legible, retain the real interface, and use PNG files. Do not add simulated controls or composite unrelated applications into the images.
5. Keep the filenames in the table above, or update the README links and alternative text together. Verify that clicking each thumbnail opens the matching full-size image.

Opening the **Lock Screen** settings page is sufficient for `lock.png`; do not lock the session to capture its editor. Use a consistent demo profile when adding more pages, and describe any sample data in the image caption or this document.
