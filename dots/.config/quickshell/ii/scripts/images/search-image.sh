#!/usr/bin/env bash
# Upload a cropped screenshot and open the configured image search engine.
# Several temporary hosts are tried in turn, each directly and then through the proxy,
# because any single one can be down or blocked on the current network.
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

# The file goes through stdin so unusual characters in its path can't confuse curl's -F parsing.
# PNG metadata is sent even though the temporary screenshot has no extension.
post() {
    "$curl_bin" --silent --show-error --fail \
        --connect-timeout 5 --max-time 25 \
        "$@" < "$screenshot"
}

# Prints a public image link, or fails. $1 = provider, rest = curl network options.
upload_to() {
    local provider=$1 response
    shift
    case $provider in
        uguu)
            response=$(post "$@" -F 'files[]=@-;filename=screenshot.png;type=image/png' "$upload_endpoint") || return 1
            "$jq_bin" -er 'select(.success == true) | .files[0].url' <<< "$response"
            ;;
        litterbox)
            # Files expire after an hour, which is plenty for a search
            response=$(post "$@" -F reqtype=fileupload -F time=1h \
                -F 'fileToUpload=@-;filename=screenshot.png;type=image/png' \
                https://litterbox.catbox.moe/resources/internals/api.php) || return 1
            printf '%s\n' "$response"
            ;;
        tmpfiles)
            response=$(post "$@" -F 'file=@-;filename=screenshot.png;type=image/png' \
                https://tmpfiles.org/api/v1/upload) || return 1
            # The returned page link becomes a direct file link with /dl/
            "$jq_bin" -er 'select(.status == "success") | .data.url' <<< "$response" \
                | sed 's#^https\?://tmpfiles.org/#https://tmpfiles.org/dl/#'
            ;;
    esac
}

image_url=""
for provider in uguu litterbox tmpfiles; do
    # Direct access works independently of whether the local proxy is running
    routes=("direct")
    [[ -n $proxy_url ]] && routes+=("proxy")
    for route in "${routes[@]}"; do
        if [[ $route == direct ]]; then
            net=(--noproxy '*')
        else
            net=(--proxy "$proxy_url" --noproxy '')
        fi
        if candidate=$(upload_to "$provider" "${net[@]}" 2>/dev/null) \
            && [[ $candidate =~ ^https://[^[:space:]]+$ ]]; then
            image_url=$candidate
            break 2
        fi
        printf 'Image search: %s (%s) failed, trying the next option\n' "$provider" "$route" >&2
    done
done

[[ -n $image_url ]] || fail 'Could not upload the image to any service. Check your connection or proxy and try again.'

encoded_url=$("$jq_bin" -rn --arg url "$image_url" '$url | @uri')
xdg-open "${search_base}${encoded_url}" || fail 'Could not open the browser.'
