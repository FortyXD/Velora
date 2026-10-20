#!/usr/bin/env bash
# Picks a color on screen with hyprpicker, copies it, and remembers it for the toolbox's Colors tab.
state="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/color_history.json"
color=$(hyprpicker -a -f hex 2>/dev/null) || exit 1
color=${color^^}
[[ "$color" =~ ^#[0-9A-F]{6}$ ]] || exit 1
mkdir -p -- "$(dirname -- "$state")"
[[ -s "$state" ]] || echo '[]' > "$state"
jq --arg c "$color" '[$c] + map(select(. != $c)) | .[:50]' "$state" > "$state.tmp" && mv -f -- "$state.tmp" "$state"
echo "$color"
