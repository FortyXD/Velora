#!/usr/bin/env bash
# Opens the Folis toolbox: open.sh [converter|downloader|qr|ocr|colors] [files…]
# A running toolbox gets the tab and files over IPC instead of a second window.
toolbox="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/toolbox.qml"
tab=${1:-converter}
shift || true
files=""
for file in "$@"; do
    files+="$(realpath -- "$file" 2>/dev/null || printf '%s' "$file")"$'\n'
done
if qs -p "$toolbox" ipc call toolbox open "$tab" "$files" &>/dev/null; then
    hyprctl dispatch 'hl.dsp.focus({ window = "title:^(Folis Toolbox)$" })' &>/dev/null
    exit 0
fi
TOOLBOX_TAB="$tab" TOOLBOX_FILES="$files" exec qs -p "$toolbox"
