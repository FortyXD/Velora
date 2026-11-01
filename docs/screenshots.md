# Velora in motion

These are recordings of **the running Velora shell inside Hyprland**, with real layer-shell panels, settings windows and applications. The README opens in Autumn Tree; Pastel Sky intentionally uses its light palette, and Aurora uses its dark palette.

## Recordings

| Clip | What happens on the desktop |
| --- | --- |
| [Switch presets](../.github/assets/demos/styles.gif) | Autumn Tree → Pastel Sky → Aurora → Autumn Tree, through Velora's native preset transition. |
| [More looks](../.github/assets/demos/preset-gallery.gif) | Scroll through the actual built-in preset gallery. |
| [Edit the bar](../.github/assets/demos/bar.gif) | Open the on-desktop editor, add weather, move it, and change the bar's edge and grouping. |
| [Desktop widgets](../.github/assets/demos/widgets.gif) | Add a calendar, note and Pomodoro; start and reset the timer. |
| [Lock editor](../.github/assets/demos/lock.gif) | Change arrangements and resize the clock in the full-screen editor. |
| [Live wallpapers](../.github/assets/demos/live-wallpapers.gif) | Aurora, Liquid and Neon Grid running behind the shell. |
| [Everyday use](../.github/assets/demos/workflow.gif) | Dolphin, workspace overview, app library, notifications and quick controls. |
| [Appearance settings](../.github/assets/demos/settings-style.gif) | Appearance, wallpaper, widgets, desktop, bar, sidebars and lock screen. |
| [Device settings](../.github/assets/demos/settings-device.gif) | Displays, keyboard, shortcuts, mouse, sound and battery. |
| [System settings](../.github/assets/demos/settings-system.gif) | Wi-Fi, networks, Bluetooth, general settings, apps, notifications, search, tools and advanced options. |
| [Energy saving](../.github/assets/demos/energy.gif) | Choose automatic and manual energy-saving policies. |
| [First-run setup](../.github/assets/demos/onboarding.gif) | Language, display, desktop layout, window behavior, appearance and optional extras. |
| [Guided tour](../.github/assets/demos/tour.gif) | The real tour checks off actions as apps open and focus moves between a tiled terminal and file manager. |

The lock screen clip shows its editor, without locking the capture session. Miniatures visible *inside Settings* are the application's own controls; the desktop surrounding those windows is the actual compositor output.

## Desktop stills

| Autumn Tree | Pastel Sky | Aurora |
| --- | --- | --- |
| [](../.github/assets/demos/autumn-tree.png) | [](../.github/assets/demos/pastel-sky.png) | [](../.github/assets/demos/aurora-style.png) |

[Autumn with applications](../.github/assets/demos/autumn-workflow.png) · [Candy](../.github/assets/demos/candy.png) · [Lime Grid](../.github/assets/demos/lime-grid.png) · [Desktop widgets](../.github/assets/demos/widgets.png) · [Lock editor](../.github/assets/demos/lock-editor.png)

## Settings gallery

Open any image at full size. These show the actual settings window on an Autumn Tree desktop.

| Appearance & desktop | Devices | Connections & system |
| --- | --- | --- |
| [Appearance](../.github/assets/demos/settings/appearance.png) | [Displays](../.github/assets/demos/settings/displays.png) | [Wi-Fi](../.github/assets/demos/settings/wifi.png) |
| [Wallpaper](../.github/assets/demos/settings/wallpaper.png) | [Keyboard](../.github/assets/demos/settings/keyboard.png) | [Network & VPN](../.github/assets/demos/settings/connections.png) |
| [Widgets](../.github/assets/demos/settings/widgets.png) | [Keyboard shortcuts](../.github/assets/demos/settings/shortcuts.png) | [Bluetooth](../.github/assets/demos/settings/bluetooth.png) |
| [Desktop & Dock](../.github/assets/demos/settings/desktop.png) | [Mouse & touchpad](../.github/assets/demos/settings/mouse.png) | [General](../.github/assets/demos/settings/general.png) |
| [Bar](../.github/assets/demos/settings/bar.png) | [Sound](../.github/assets/demos/settings/sound.png) | [Default apps](../.github/assets/demos/settings/apps.png) |
| [Sidebars](../.github/assets/demos/settings/sidebars.png) | [Battery & energy](../.github/assets/demos/settings/battery.png) | [Notifications](../.github/assets/demos/settings/notifications.png) |
| [Lock screen](../.github/assets/demos/settings/lock.png) | | [Search](../.github/assets/demos/settings/search.png) |
| [Presets](../.github/assets/demos/preset-gallery.png) | | [Tools](../.github/assets/demos/settings/tools.png) |
| | | [Advanced](../.github/assets/demos/settings/advanced.png) |

## Capture profile

The recordings use a separate home directory and private D-Bus session in a Bubblewrap namespace. A headless KWin session hosts nested Hyprland, which renders a 1600 × 900 virtual output. Velora's normal shell, native helper, presets, shaders, settings and applications run there. `grim` captures stills; `wf-recorder` captures video at 30 fps.

The profile contains sample weather, notes, notifications and files. Widget positions, card backgrounds and clock details are personalized using normal settings. Cached copies of the presets' original artwork allow recording without network access. Temporary IPC hooks invoke the same methods as the controls to make the capture repeatable; they do not replace visible components or draw substitute desktop windows.

The capture session has no physical battery, wireless adapter or audio devices. Their settings pages demonstrate the UI; the energy clip demonstrates policy selection, not a measured battery-life improvement or a physical unplug event. Device behavior still needs testing on the relevant hardware.

GIFs retain the application's real transitions. Only the final half-second blends back to the opening frame to soften the loop boundary. Most clips are 960 pixels wide at 20 fps; the full-screen live wallpaper montage is 800 pixels at 15 fps to keep its download smaller. Desktop stills retain the original resolution. Settings stills are cropped around the real window at its original pixel scale, saving repeated copies of the surrounding wallpaper.

## Re-recording

Use a separate demo account or isolated desktop session with Velora's normal dependencies installed, including its Python environment and Qt application theming. Also install `grim`, `wf-recorder` and `ffmpeg`. The helper below records an existing session; it does not build an isolated session for you.

1. Start Velora, apply Autumn Tree, and wait for shell **and application** themes to finish. Populate only sample content. Open a file manager to confirm that a dark preset also gives applications a dark palette.
2. Find the capture output with `hyprctl monitors`. Record real interactions:

   ```bash
   python3 docs/readme/record.py --monitor VELORA --seconds 14 \
       --output artifacts/readme/bar.gif
   ```

   Use your actual output name instead of `VELORA`. The MP4 is retained beside the GIF. To encode a recording again:

   ```bash
   python3 docs/readme/record.py --input artifacts/readme/bar.mp4 \
       --output artifacts/readme/bar.gif --width 960 --fps 20
   ```

3. Open an individual settings page with:

   ```bash
   QS_SETTINGS_PAGE=appearance qs -p dots/.config/quickshell/ii/settings.qml
   ```

   The setup assistant is `qs -p dots/.config/quickshell/ii/onboarding.qml`. Choose **Tiling** for window behavior. Before recording the desktop tour, run `qs -c ii ipc call windowMode set tiling`, wait for the transition, and check that `qs -c ii ipc call windowMode get` returns `tiling`. Start the tour with `qs -c ii ipc call tour start`. Record the setup assistant in the demo profile because its choices change settings.
4. Capture stills after animations settle:

   ```bash
   grim -o VELORA artifacts/readme/autumn-tree.png
   ```

5. Play every clip and inspect changed states at full size. Check alignment, text clipping, icon and wallpaper loading, dark/light application palettes, native transitions and the loop seam. In the bar editor, check horizontal → vertical → horizontal orientation. Keep the complete action visible; do not publish loading failures or compositor startup notices.
6. Copy reviewed media to `.github/assets/demos/`, then preview the README at desktop and mobile widths. Keep raw recordings, temporary profiles, downloaded originals and logs under ignored `artifacts/` or outside the repository.

## Artwork and attribution

- **Autumn Tree:** *Before the leaves have fallen* by **JoeyJazz**. [Artist's page](https://www.deviantart.com/joeyjazz/art/Before-the-leaves-have-fallen-854162011), [bundled notice](../dots/.config/quickshell/ii/assets/images/autumn.NOTICE.md). Artist copyright; not covered by Velora's GPL license.
- **Pastel Sky:** *Alien Moon* by **rmRadev**. [Artist's page](https://www.deviantart.com/rmradev/art/Alien-Moon-743912901), [preset and original source](../dots/.config/quickshell/ii/defaults/presets/pastel.json). The original download is not added to the repository; the screenshots show it as a wallpaper. Copyright remains with the artist.
- **Aurora, Candy and Lime Grid:** generated by [Velora's shaders](../dots/.config/quickshell/ii/assets/shaders/).
- **Preset gallery artwork:** each card retains its author/source credit. Full attribution and source links are stored with [the individual presets](../dots/.config/quickshell/ii/defaults/presets/), including their video preview images. Those third-party works retain their own licenses.
- The [banner](../.github/assets/velora-banner.svg) is original SVG branding in Autumn Tree's warm palette.

Other notices remain in the [licensing guide](../licenses/README.md).
