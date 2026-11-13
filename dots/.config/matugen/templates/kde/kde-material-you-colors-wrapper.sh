#!/usr/bin/env bash
# Compatibility entry point for wallpaper/preset jobs. The selected variant is
# already reflected in colors.json; no second color generator or KWin is needed.
set -euo pipefail
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
exec /usr/bin/python3 -I "$config_root/quickshell/ii/scripts/colors/kde-theme.py"
