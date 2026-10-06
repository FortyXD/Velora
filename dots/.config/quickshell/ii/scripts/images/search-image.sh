#!/usr/bin/env bash
# Upload a cropped screenshot and open the configured image search engine.
set -euo pipefail

screenshot=${1:?Missing screenshot path}
search_base=${2:?Missing image search URL}
upload_endpoint=${3:-https://uguu.se/upload}
proxy_url=${4:-}
trap 'rm -f -- "$screenshot"' EXIT

fail() {
    printf 'Image search: %s\n' "$1" >&2
    notify-send -a 'Image search' -u critical 'Image search failed' "$1" 2>/dev/null || true
    exit 1
}

# Conda can shadow curl with a build whose CA file no longer exists.
# Prefer distro tools; retain PATH lookup for systems such as NixOS.
curl_bin=/usr/bin/curl
jq_bin=/usr/bin/jq
[[ -x $curl_bin ]] || curl_bin=$(command -v curl) || fail 'curl is not installed.'
[[ -x $jq_bin ]] || jq_bin=$(command -v jq) || fail 'jq is not installed.'
[[ -s $screenshot ]] || fail 'The selected screenshot could not be read.'

# Send PNG metadata even though the temporary screenshot has no extension.
upload() {
    "$curl_bin" --silent --show-error --fail \
        --connect-timeout 5 --max-time 30 \
        "$@" \
        -F 'files[]=@-;filename=screenshot.png;type=image/png' \
        "$upload_endpoint" < "$screenshot"
}

# Direct access works independently of whether the local proxy is running.
# Only retry through the configured proxy when the direct request fails.
if ! response=$(upload --noproxy '*'); then
    if [[ -z $proxy_url ]] || ! response=$(upload --proxy "$proxy_url" --noproxy ''); then
        fail 'Could not upload the image. Check your connection and try again.'
    fi
fi

if ! image_url=$("$jq_bin" -er '
    select(.success == true) | .files[0].url
    | select(type == "string" and test("^https?://[^[:space:]]+$"))
    | @uri' <<< "$response"); then
    fail 'The upload service did not return a valid image link. Try again later.'
fi

xdg-open "${search_base}${image_url}" || fail 'Could not open the browser.'
