#!/usr/bin/env bash
# Downloads a wallpaper found online into the wallpaper library, with its credits next to it.
# usage: download_wallpaper.sh <url> <destination> [--apply] [--meta <json>] [--title <text>] [--loop <start>:<end>:<crossfade>] [--upgrade]
# --loop (videos): keeps start..end seconds of the download, made to repeat without a jump (make_loop)
# --upgrade: makes an existing loop again, quietly and one at a time. The script starts it in the background
#   itself for a loop made by an older version, so applying a look never waits on a download.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

url=$1
dest=$2
shift 2 || { echo "usage: $0 <url> <destination> [--apply] [--meta <json>] [--title <text>] [--loop <start>:<end>:<crossfade>] [--upgrade]" >&2; exit 2; }
apply=0
meta=""
loop=""
upgrade=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --apply) apply=1; shift ;;
        --meta) meta=$2; shift 2 ;;
        --title) NOTIFY_TITLE=$2; shift 2 ;;
        --loop) loop=$2; shift 2 ;;
        --upgrade) upgrade=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
NOTIFY_TITLE=${NOTIFY_TITLE:-Online wallpaper}

# Downloads the source and makes the loop at $dest; the source is removed once the loop is made
make_dest_loop() {
    local loop_start loop_end loop_fade source_file
    IFS=: read -r loop_start loop_end loop_fade <<< "$loop"
    source_file="${dest%.*}.source.${url##*.}"
    source_file=${source_file%%\?*}
    notify_progress "$NOTIFY_TITLE" "Downloading…"
    [[ -f "$source_file" ]] || fetch_image "$url" "$source_file"
    notify_progress "$NOTIFY_TITLE" "Making it loop…"
    make_loop "$source_file" "$dest" "$loop_start" "$loop_end" "$loop_fade"
    rm -f -- "$source_file"
}

mkdir -p -- "$(dirname -- "$dest")" || fail "Cannot create $(dirname -- "$dest")."

if [[ $upgrade -eq 1 ]]; then
    # Nothing to see unless it works: on any failure (offline, host blocked) the older loop simply stays
    notify_progress() { :; }
    fail() { echo "$1" >&2; exit 1; }
    exec 9> "${XDG_RUNTIME_DIR:-/tmp}/wallpaper-loop-upgrade.lock"
    flock 9 # One download and encode at a time, however many looks were applied
    loop_is_current "$dest" && exit 0 # Made by an earlier run meanwhile
    make_dest_loop
    # The players still have the older file open
    if [[ $(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null) == "$dest" ]]; then
        qs -c "$(basename "$(cd "$RANDOM_WALL_SCRIPT_DIR/../../.." && pwd)")" ipc call liveWallpaper reload &>/dev/null
    fi
    exit 0
fi

if [[ -n "$loop" && ! -f "$dest" ]]; then
    make_dest_loop
elif [[ -n "$loop" ]] && ! loop_is_current "$dest"; then
    # Made by an older version (at most 1440p): used as it is now and made again in the background
    setsid -f bash -- "${BASH_SOURCE[0]}" "$url" "$dest" --loop "$loop" --upgrade </dev/null &>/dev/null
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
