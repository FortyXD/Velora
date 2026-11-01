#!/usr/bin/env bash
set -euo pipefail
umask 077
image=$(mktemp --suffix=.png)
trap 'rm -f -- "$image"' EXIT
area=$(slurp)
grim -g "$area" "$image"
image_link=$(curl --fail --silent --show-error --max-time 60 -F "files[]=@${image}" 'https://uguu.se/upload' | jq -er '.files[0].url')
encoded_link=$(jq -rn --arg url "$image_link" '$url | @uri')
xdg-open "https://lens.google.com/uploadbyurl?url=${encoded_link}"
