"""Expose standard GTK header buttons in free window modes. Preserve explicit user layouts."""

import fcntl
import json
import os
from pathlib import Path
import sys
from gi.repository import Gio

state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "velora"
marker = state / "gtk-window-controls.json"
enable = sys.argv[1] in ("floating", "canvas")
if not enable and not marker.exists():
    raise SystemExit(0)
source = Gio.SettingsSchemaSource.get_default()
schema = source.lookup("org.gnome.desktop.wm.preferences", True) if source else None
if not schema or not schema.has_key("button-layout"):
    raise SystemExit(0)
prefs = Gio.Settings.new_full(schema, None, None)
key = "button-layout"
state.mkdir(parents=True, exist_ok=True)
with (state / "gtk-window-controls.lock").open("a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        installed = json.loads(marker.read_text())
    except (OSError, ValueError):
        installed = None
    if not enable:
        if installed and prefs.get_string(key) == installed:
            prefs.reset(key)
            Gio.Settings.sync()
        marker.unlink(missing_ok=True)
    elif prefs.get_user_value(key) is None:
        layout = prefs.get_string(key)
        left, _, right = layout.partition(":")
        buttons = [b for b in right.split(",") if b]
        missing = [b for b in ("minimize", "maximize") if b not in buttons and b not in left.split(",")]
        if missing and prefs.is_writable(key):
            index = buttons.index("close") if "close" in buttons else len(buttons)
            buttons[index:index] = missing
            managed = left + ":" + ",".join(buttons)
            tmp = marker.with_suffix(".tmp")
            tmp.write_text(json.dumps(managed))
            tmp.replace(marker)
            if prefs.set_string(key, managed):
                Gio.Settings.sync()
            else:
                marker.unlink(missing_ok=True)
