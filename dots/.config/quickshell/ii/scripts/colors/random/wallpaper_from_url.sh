#!/usr/bin/env bash
# Usage: wallpaper_from_url.sh <image url>
# Downloads the image into ~/Pictures/Wallpapers (keeping its file name) and applies it.
NOTIFY_TITLE="Wallpaper"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

url=$1
[[ -n "$url" ]] || fail "No image URL given."
host=$(awk -F/ '{print $3}' <<< "$url")
name=$(basename "${url%%\?*}")
name=$(printf '%b' "${name//%/\\x}") # URL-decode
dir="$(get_pictures_dir)/Wallpapers"
mkdir -p -- "$dir"

notify_progress "$NOTIFY_TITLE" "Downloading from $host…"
dest="$dir/$name"
[[ -f "$dest" ]] || fetch_image "$url" "$dest"
apply_wallpaper "$dest"
