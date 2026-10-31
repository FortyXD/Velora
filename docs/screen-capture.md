# Screenshot cursor

Open **Settings → Screenshots & tools → Screenshots** and toggle **Show cursor in screenshots**.

- **Off** (default): screenshots do not include the mouse pointer, preserving the previous behavior.
- **On**: include the pointer in screen captures (`Print`, `Ctrl+Print`, the overlay screenshot button) and region captures in both panel styles. The preference also applies to the shell-off region fallback.

The region picker freezes the image before displaying the selection overlay. Its screenshot includes the pointer at that initial position, not the selection crosshair or the pointer's later position. The shell-off fallback uses a live `slurp` selection and captures after selection.

The preference is saved as the boolean `screenSnip.showCursor` in the shell configuration. It does not change screen-recording cursor behavior or internal brightness sampling. Screen translation continues to request a cursor-free source.

## Implementation and checks

User-facing capture paths use `scripts/images/screenshot.sh`, which forwards arguments to `grim` and adds `-c` only when enabled. Quickshell passes its current in-memory preference explicitly; shortcuts read the saved preference. Missing or malformed settings fall back to hiding the cursor. Clipboard captures are copied only after `grim` succeeds; cancellation or capture failure leaves the clipboard unchanged, and temporary captures are removed.

On Hyprland, a software-composited cursor can be baked into frames even without `-c`. For cursor-free captures, the helper temporarily enables hardware cursor planes when software cursors are forced, refreshes the cursor at its current position, and restores the previous mode on exit (including ordinary errors and interrupt/termination signals). Captures are serialized with a private runtime lock so that simultaneous requests cannot race the override/restoration. No persistent compositor configuration is edited. This workaround requires Hyprland's Lua cursor API and working hardware cursor support.

Run the isolated tests with:

```bash
python3 -m unittest discover -s tests -p test_screenshot_cursor.py -v
```

They cover both preference values, old/invalid configuration, argument quoting, explicit live preferences, cancelled/failed selections, production Quickshell capture wiring, and persistence without changes to video settings. Actual `grim` capture requires a running Wayland session supporting cursor capture.
