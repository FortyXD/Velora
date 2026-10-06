#!/usr/bin/env bash
# Random SFW wallpaper from Konachan. konachan.net often stalls on a direct
# connection from some networks; in that case this fails fast with a message.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

notify_progress "Random wallpaper" "Downloading from konachan.net…"
page=$((1 + RANDOM % 1000))
response=$(api_get "https://konachan.net/post.json?tags=rating%3Asafe&limit=1&page=$page")
link=$(jq -r '.[0].file_url // empty' <<< "$response" 2>/dev/null)
[[ -n "$link" ]] || fail "konachan.net returned no image."
ext="${link##*.}"

downloadPath=$(download_path "$ext")
fetch_image "$link" "$downloadPath"
apply_wallpaper "$downloadPath"
