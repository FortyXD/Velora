#!/usr/bin/env bash
# Used on login and after an in-session install. Each display owns its clipboard watchers.
set -eu
config=${1:?missing Quickshell config}
runtime=${XDG_RUNTIME_DIR:?}/velora-clipboard
mkdir -p -- "$runtime"
qs -n -d -c "$config"
for type in text image; do
    # A previous Velora release may already be watching this display without a lock.
    legacy=false
    while read -r pid; do
        if grep -zFxq -- "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" "/proc/$pid/environ" 2>/dev/null; then
            legacy=true
            break
        fi
    done < <(pgrep -u "$UID" -f "^wl-paste --type $type --watch bash -c cliphist store && qs ")
    if "$legacy"; then continue; fi
    flock --nonblock --no-fork "$runtime/${WAYLAND_DISPLAY##*/}-$type.lock" \
        wl-paste --type "$type" --watch sh -c 'cliphist store && qs -c "$1" ipc call cliphistService update' sh "$config" &
done
