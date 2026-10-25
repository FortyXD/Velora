#!/usr/bin/env bash
# Downloads a wallpaper found online into the wallpaper library, with its credits next to it.
# usage: download_wallpaper.sh <url> <destination> [--apply] [--meta <json>] [--title <text>] [--loop <start>:<end>:<crossfade>]
# --loop (videos): keeps start..end seconds of the download, made to repeat without a jump (make_loop)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

url=$1
dest=$2
shift 2 || { echo "usage: $0 <url> <destination> [--apply] [--meta <json>] [--title <text>] [--loop <start>:<end>:<crossfade>]" >&2; exit 2; }
apply=0
meta=""
loop=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --apply) apply=1; shift ;;
        --meta) meta=$2; shift 2 ;;
        --title) NOTIFY_TITLE=$2; shift 2 ;;
        --loop) loop=$2; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
NOTIFY_TITLE=${NOTIFY_TITLE:-Online wallpaper}

mkdir -p -- "$(dirname -- "$dest")" || fail "Cannot create $(dirname -- "$dest")."
if [[ ! -f "$dest" && -n "$loop" ]]; then
    IFS=: read -r loop_start loop_end loop_fade <<< "$loop"
    source_file="${dest%.*}.source.${url##*.}"
    source_file=${source_file%%\?*}
    notify_progress "$NOTIFY_TITLE" "Downloading…"
    [[ -f "$source_file" ]] || fetch_image "$url" "$source_file"
    notify_progress "$NOTIFY_TITLE" "Making it loop…"
    make_loop "$source_file" "$dest" "$loop_start" "$loop_end" "$loop_fade"
    rm -f -- "$source_file"
elif [[ ! -f "$dest" ]]; then
    notify_progress "$NOTIFY_TITLE" "Downloading…"
    fetch_image "$url" "$dest"
fi
[[ -n "$meta" ]] && printf '%s\n' "$meta" > "${dest%.*}.json"

if [[ $apply -eq 1 ]]; then
    apply_wallpaper "$dest"
else
    args=(-a "$NOTIFY_APP" -t 3000)
    [[ -n "$notification_id" ]] && args+=(-r "$notification_id")
    notify-send "${args[@]}" "$NOTIFY_TITLE" "Saved to $dest" 2>/dev/null
fi
