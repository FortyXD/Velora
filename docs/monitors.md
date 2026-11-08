# Displays

Velora keeps monitor choices in `~/.config/hypr/custom/monitors.json` (one entry per output:
`mode`, `position`, `scale`, `transform`, `vrr`, `mirror`, `disabled`) and generates
`custom/monitors.lua` from it. Hyprland is reloaded after each change. Manual rules belong in
another file, because `monitors.lua` is overwritten.

Settings → Displays edits those choices. The arrangement canvas draws the outputs in the
**logical** desktop coordinates Hyprland uses, fitted to the widget, and a drop is only snapped
to a neighbouring edge when it lands close to one; otherwise it keeps the place it was released
on. Overlapping two outputs is refused. Positions are normalised so the layout always starts at
`0x0`.

`hyprctl monitors all` reports an **enabled** output in scaled pixels and a **disabled** one in
mode pixels. `HyprlandMonitors.modeText()` recovers the real mode from `availableModes`
accordingly; rebuilding the mode from the reported size instead would divide by the scale twice
and write a mode that the panel does not have.

## Nothing left lit

Disabling the built-in panel and unplugging the only external display would leave zero enabled
outputs: a black screen, a placeholder Wayland screen and a shell whose windows have no real
monitor. The service therefore treats "every connected output is switched off by the saved
choices" as an invalid state and lights the built-in panel with a known-good configuration
instead: `mode = "preferred"`, `position = "0x0"`, `transform = 0`, keeping only the scale that
was chosen for that panel.

This fallback is **not** written into `monitors.json`: the saved intent stays untouched, so
plugging the external display back restores the arrangement (and the built-in goes back off if
that is what was asked for). Settings and the generated lua show the effective state, while the
user's choice remains the intent.

Two details of Hyprland make this trickier than it looks, and both are handled:

- `hyprctl monitors all` reports an **enabled** output in scaled pixels and a **disabled** one in
  mode pixels, and an unplugged output can stay in the list as disabled instead of disappearing.
  "Is anything lit" is therefore read from the live `disabled` flag, never from the saved intent.
- When no real output is left enabled, Hyprland creates a virtual **`FALLBACK`** output
  (1920x1080) so the desktop keeps working. It is filtered out of the display list: counting it
  as a screen made the service believe everything was fine while the user saw nothing, and it is
  not a display anyone can arrange.

The reaction belongs to the shell (`shell.qml` calls `HyprlandMonitors.watch()`), because a
singleton that only the settings window touches stops existing the moment that window closes —
which is exactly when an unplug happens. The built-in panel is excluded from "something the user
asked for is lit" while the fallback is written, otherwise enabling it would clear the fallback
and switch it off again in a loop.

Hotplug is also guarded elsewhere: `ScreenCorners` skips a screen that Hyprland has not
registered yet, the wallpaper parallax tolerates a missing monitor, and bar popups stop asking
`mapFromItem` before their window exists.

## Checks

```sh
python3 -m unittest discover -s tests -p test_monitor_layout.py -v
```

The geometry and the fallback run against the production singleton inside Quickshell with
synthetic `hyprctl` data, private `HOME`/`XDG_*` directories and no compositor: scaled and
rotated modes, the fallback when nothing is lit, and the restore when the external returns.
Physical plug/unplug on real hardware is a separate manual check.
