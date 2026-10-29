#!/usr/bin/env bash
# Shared helpers for the random wallpaper scripts. Source this file.
# Downloads must never leave a half-written image behind: some hosts stall after
# ~20 KB on a direct connection, so everything has timeouts and is validated.

RANDOM_WALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCHWALL="$RANDOM_WALL_SCRIPT_DIR/../switchwall.sh"
SHELL_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
NOTIFY_APP="Wallpaper"
NOTIFY_TITLE="${NOTIFY_TITLE:-Random wallpaper}"
notification_id=""

get_pictures_dir() {
    if command -v xdg-user-dir &> /dev/null; then
        xdg-user-dir PICTURES
        return
    fi

    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    if [ -f "$config_file" ]; then
        local pictures_path
        pictures_path=$(source "$config_file" >/dev/null 2>&1; echo "$XDG_PICTURES_DIR")
        echo "${pictures_path/#\$HOME/$HOME}"
        return
    fi

    echo "$HOME/Pictures"
}

# notify_progress <title> <body>: shows (or replaces) the progress notification
notify_progress() {
    local args=(-a "$NOTIFY_APP" -p)
    [[ -n "$notification_id" ]] && args+=(-r "$notification_id")
    notification_id=$(notify-send "${args[@]}" "$1" "$2" 2>/dev/null)
}

# fail <message>: reports the error and exits
fail() {
    local args=(-a "$NOTIFY_APP" -u critical)
    [[ -n "$notification_id" ]] && args+=(-r "$notification_id")
    notify-send "${args[@]}" "$NOTIFY_TITLE failed" "$1"
    echo "$1" >&2
    exit 1
}

# curl_error_text <exit code> <host>: human-readable reason for a curl failure
curl_error_text() {
    case $1 in
        6) echo "Could not resolve $2 (DNS blocked or offline)." ;;
        7|28) echo "$2 is not responding. It may be blocked without a VPN." ;;
        18) echo "The download from $2 was cut off." ;;
        22) echo "$2 refused the request (HTTP error)." ;;
        35|60) echo "Secure connection to $2 failed." ;;
        *) echo "Download from $2 failed (curl error $1)." ;;
    esac
}

# api_get <url>: prints the response body, fails with a readable message
api_get() {
    local host body rc
    host=$(awk -F/ '{print $3}' <<< "$1")
    body=$(curl --fail --silent --location --compressed \
        --connect-timeout 8 --speed-limit 512 --speed-time 10 --max-time 30 \
        --retry 2 --retry-all-errors -- "$1")
    rc=$?
    [[ $rc -eq 0 ]] || fail "$(curl_error_text "$rc" "$host")"
    printf '%s' "$body"
}

# fetch_image <url> <destination>: downloads to a temp file, checks it decodes, then moves it into place.
# A destination ending in a video extension is checked as a video (live wallpapers) and may take longer.
fetch_image() {
    local url=$1 dest=$2 host tmp rc video=0 max_time=300
    host=$(awk -F/ '{print $3}' <<< "$url")
    case "${dest,,}" in *.mp4|*.webm|*.mkv|*.mov|*.avi) video=1; max_time=900 ;; esac
    tmp=$(mktemp "${dest}.part.XXXXXX") || fail "Cannot write to $(dirname "$dest")."
    # --speed-limit aborts a stalled transfer after 10 s instead of hanging forever
    curl --fail --silent --location \
        --connect-timeout 8 --speed-limit 1024 --speed-time 10 --max-time "$max_time" \
        --retry 2 --retry-all-errors -o "$tmp" -- "$url"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        rm -f -- "$tmp"
        fail "$(curl_error_text "$rc" "$host")"
    fi
    if [[ $video -eq 1 ]]; then
        # A playable video stream: catches error pages and cut-off downloads
        if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$tmp" 2>/dev/null | grep -q .; then
            rm -f -- "$tmp"
            fail "The file from $host is not a playable video."
        fi
    # Full decode: catches truncated PNGs and error pages that aren't images
    elif ! magick "${tmp}[0]" null: &>/dev/null; then
        rm -f -- "$tmp"
        fail "The file from $host is not a valid image."
    fi
    chmod 644 -- "$tmp" # mktemp creates it private
    mv -f -- "$tmp" "$dest"
}

# Written into every made loop. Loops without it come from an older make_loop (at most 1440p) and are made again.
LOOP_TAG="wallpaper loop 2"

# loop_is_current <video>: whether the video is a loop made by this version of make_loop
loop_is_current() {
    [[ $(ffprobe -v error -show_entries format_tags=comment -of csv=p=0 "$1" 2>/dev/null) == "$LOOP_TAG" ]]
}

# make_loop <source> <destination> <start> <end> <crossfade>: cuts start..end (seconds) out of a video and
# blends its last <crossfade> seconds into its first, so it repeats without a jump. Clips found online
# rarely end where they began. Kept at the source's resolution up to 4K, and mpv scales it to each screen's
# own size; at most 30 fps, half the decoding of 60; and 4:2:0, which hardware decoders play (xfade alone would
# hand the encoder 4:4:4).
make_loop() {
    local src=$1 dest=$2 start=$3 end=$4 fade=$5 tmp length
    length=$(awk -v s="$start" -v e="$end" 'BEGIN { print e - s }')
    awk -v l="$length" -v f="$fade" 'BEGIN { exit !(l > 2 * f && f > 0) }' || fail "The loop is too short for its crossfade."
    tmp=$(mktemp "${dest}.part.XXXXXX.mp4") || fail "Cannot write to $(dirname "$dest")."
    # [main] is start+fade..end, [head] the first fade seconds; fading main's tail into head ends the clip
    # on the very frame it starts with
    if ! ffmpeg -v error -y -ss "$start" -to "$end" -i "$src" -filter_complex \
        "[0:v]fps=30,scale=-2:'min(2160,ih)':flags=lanczos,format=yuv420p,split[a][b];[a]trim=start=$fade,setpts=PTS-STARTPTS[main];[b]trim=end=$fade,setpts=PTS-STARTPTS[head];[main][head]xfade=transition=fade:duration=$fade:offset=$(awk -v l="$length" -v f="$fade" 'BEGIN { print l - 2 * f }'),format=yuv420p[out]" \
        -map "[out]" -an -c:v libx264 -profile:v high -pix_fmt yuv420p -preset medium -crf 18 \
        -metadata comment="$LOOP_TAG" -movflags +faststart "$tmp"; then
        rm -f -- "$tmp"
        fail "Couldn't make the video loop."
    fi
    chmod 644 -- "$tmp"
    mv -f -- "$tmp" "$dest"
}

# download_path <extension>: alternates names so the new file never overwrites the wallpaper in use
download_path() {
    local dir path current
    dir="$(get_pictures_dir)/Wallpapers"
    mkdir -p -- "$dir"
    path="$dir/random_wallpaper.$1"
    current=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null)
    [[ "$path" == "$current" ]] && path="$dir/random_wallpaper-1.$1"
    echo "$path"
}

# apply_wallpaper <path>
apply_wallpaper() {
    notify_progress "$NOTIFY_TITLE" "Generating colors…"
    "$SWITCHWALL" --image "$1" || fail "Could not apply the wallpaper."
    local args=(-a "$NOTIFY_APP" -t 3000)
    [[ -n "$notification_id" ]] && args+=(-r "$notification_id")
    notify-send "${args[@]}" "$NOTIFY_TITLE" "Applied $(basename "$1")" 2>/dev/null
}
