#!/usr/bin/env bash
# Random SFW anime wallpaper from Wallhaven, at least as large as the focused monitor.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

notify_progress "Random wallpaper" "Downloading from wallhaven.cc…"
resolution=$(hyprctl monitors -j | jq -r '(map(select(.focused)) + .)[0] | "\(.width)x\(.height)"' 2>/dev/null)
[[ "$resolution" =~ ^[0-9]+x[0-9]+$ ]] || resolution="1920x1080"
response=$(api_get "https://wallhaven.cc/api/v1/search?categories=010&purity=100&sorting=random&atleast=$resolution")
# Prefer images with the monitor's aspect ratio, fall back to any result
monitorRatio=$(awk -Fx '{ printf "%.2f", $1 / $2 }' <<< "$resolution")
link=$(jq -r --argjson r "$monitorRatio" \
    '([.data[] | select((.ratio | tonumber) - $r | fabs < 0.15)] + .data)[0].path // empty' <<< "$response" 2>/dev/null)
[[ -n "$link" ]] || fail "wallhaven.cc returned no image for $resolution."
ext="${link##*.}"

downloadPath=$(download_path "$ext")
fetch_image "$link" "$downloadPath"
apply_wallpaper "$downloadPath"
