#!/usr/bin/env bash
# Usage: wallpaper_from_url.sh <image url>
# Downloads the image into ~/Pictures/Wallpapers (keeping its file name) and applies it.
NOTIFY_TITLE="Wallpaper"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

url=$1
[[ -n "$url" ]] || fail "No image URL given."
name=$("$(dirname "${BASH_SOURCE[0]}")/../../helper" wallpaper-filename "$url") || fail "Invalid wallpaper URL."
host=$(awk -F/ '{print $3}' <<< "$url")
dir="$(get_pictures_dir)/Wallpapers"
mkdir -p -- "$dir"

notify_progress "$NOTIFY_TITLE" "Downloading from $host…"
dest="$dir/$name"
[[ -f "$dest" ]] || fetch_image "$url" "$dest"
apply_wallpaper "$dest"
