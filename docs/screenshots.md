# Screenshots and recordings

The README contains real desktop recordings using the three bundled wallpapers:
**Autumn** (default), **Komona Sunset** and **Mountain**. Click a preset preview to
open its full-size still image. Media lives in [`.github/assets/demos/`](../.github/assets/demos/).

Autumn is used with Josef Bartoň's permission. **© Josef Bartoň (JoeyJazz).
All rights reserved. Commercial use of this artwork by third parties is not
permitted**, including when it appears in a screenshot or recording.

## Re-recording

Use a separate demo account or isolated desktop session with Velora's normal dependencies installed, including its Python environment and Qt application theming. Also install `grim`, `wf-recorder` and `ffmpeg`. The helper below records an existing session; it does not build an isolated session for you.

When using custom XDG directories for an isolated session, also point every Matugen
`input_path` and `output_path` at that session: the shipped `~` paths otherwise
refer to the normal user profile. Confirm the generated `colors.json` is in the
session's state directory and the widgets have the selected palette before recording.

Copy the normal Kitty, tmux, zsh/Starship, Dolphin and KDE configuration into the
demo profile. Keep the configured Qt platform theme and icon theme available;
launching Kitty with `--config NONE` or forcing a different Dolphin style does not
represent the desktop. Use a separate tmux server and Kitty control socket. Load
the normal Hyprland shortcut definitions so the tour's shortcut list is populated.

1. Start Velora, apply Autumn, Komona Sunset or Mountain, and wait for shell **and application** themes to finish. Populate only sample content. Open a file manager to confirm that a dark preset also gives applications a dark palette.
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

   The setup assistant is `qs -p dots/.config/quickshell/ii/onboarding.qml`. Choose **Tiling** for window behavior. Start capturing only after its opening screen is visible, and stop before closing its final screen so the clip contains no bare desktop. Before recording the desktop tour, run `qs -c ii ipc call windowMode set tiling`, wait for the transition, and check that `qs -c ii ipc call windowMode get` returns `tiling`. Start the tour with `qs -c ii ipc call tour start`. Record the setup assistant in the demo profile because its choices change settings.
4. Capture stills after animations settle:

   ```bash
   grim -o VELORA artifacts/readme/mountain-night.png
   ```

5. Play every clip and inspect changed states at full size, including the first and last frames decoded from the finished GIF. Check alignment, text clipping, icon and wallpaper loading, dark/light application palettes, native transitions and the loop seam. In the bar editor, check horizontal → vertical → horizontal orientation. In the tour, wait for the populated shortcut list and the completion card. Keep the complete action visible; do not publish loading failures or compositor startup notices.
6. Copy reviewed media to `.github/assets/demos/`, then preview the README at desktop and mobile widths. Keep raw recordings, temporary profiles, downloaded originals and logs under ignored `artifacts/` or outside the repository.

## Artwork and attribution

- **Autumn:** Josef Bartoň (JoeyJazz), artist permission with the copyright and noncommercial restriction above. [Permission notice](../dots/.config/quickshell/ii/assets/images/autumn.NOTICE.md).
- **Komona Sunset:** David Revoy, CC BY 4.0. [Source and notice](../dots/.config/quickshell/ii/assets/images/komona-sunset.NOTICE.md).
- **Mountain**, dark variant: Andy Betts, CC BY-SA 4.0. [Source and notice](../dots/.config/quickshell/ii/assets/images/mountain-night.NOTICE.md).
- The [banner](../.github/assets/velora-banner.svg) is original SVG branding.

Keep each artwork's terms distinct in recordings that show several presets. Previews scale
or crop the source images, overlay the desktop UI, and reduce colors when encoded
as GIFs. Keep the corresponding attribution and terms with shared previews; the
Mountain artwork adaptations remain under CC BY-SA 4.0.

See the [media notice](../.github/assets/demos/README.md) and
[licensing guide](../licenses/README.md) for the per-file credits.
