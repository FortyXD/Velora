#!/bin/bash

INTERVAL=2
TOTAL_DURATION=30
SOURCE_TYPE="monitor"  # monitor | input

while getopts "i:t:s:" opt; do
  case $opt in
    i) INTERVAL=$OPTARG ;;
    t) TOTAL_DURATION=$OPTARG ;;
    s) SOURCE_TYPE=$OPTARG ;;
    *) exit 1 ;;
  esac
done

if ! command -v songrec >/dev/null 2>&1; then
    exit 1
fi

if [ "$SOURCE_TYPE" = "monitor" ]; then
    AUDIO_DEVICE=$(pactl get-default-sink).monitor
elif [ "$SOURCE_TYPE" = "input" ]; then
    AUDIO_DEVICE=$(pactl info | grep "Default Source:" | awk '{print $3}' || true)
else
    echo "Invalid source type"
    exit 1
fi

if [ -z "$AUDIO_DEVICE" ] || ! pactl list short sources | grep -q "$AUDIO_DEVICE"; then
    exit 1
fi

work_dir=$(mktemp -d) || exit 1
FIFO="$work_dir/songrec"

cleanup() {
    if [ -n "${SONGREC_PID:-}" ]; then
        kill "$SONGREC_PID" 2>/dev/null || true
        wait "$SONGREC_PID" 2>/dev/null || true
    fi
    rm -f -- "$FIFO"
    rmdir -- "$work_dir"
}
trap cleanup EXIT
mkfifo "$FIFO" || exit 1

# timeout owns the child lifecycle; no detached sleeper can later signal a reused PID.
timeout --kill-after=2 "$TOTAL_DURATION" songrec listen --audio-device "$AUDIO_DEVICE" --request-interval "$INTERVAL" --json --disable-mpris > "$FIFO" &
SONGREC_PID=$!

while IFS= read -r line; do
    if jq -e '.matches | length > 0' >/dev/null 2>&1 <<< "$line"; then
        echo "$line"
        exit 0
    fi
done < "$FIFO"

exit 0
