#!/usr/bin/env bash
set -euo pipefail
backend=$1
action=$2
shift 2

# cliphist accepts an ID and tab on stdin. The preview can contain private clipboard text.
decode() {
    [[ $1 =~ ^[0-9]+$ ]] || return 1
    if [[ ${backend##*/} == *cliphist* ]]; then
        printf '%s\t\n' "$1" | "$backend" decode
    else
        "$backend" decode "$1"
    fi
}

case $action in
    copy) decode "$1" | wl-copy ;;
    paste)
        delay=$1
        shift
        for id in "$@"; do
            decode "$id" | wl-copy
            sleep "$delay"
            ydotool key -d 1 29:1 47:1 47:0 29:0
            sleep "$delay"
        done
        ;;
    delete)
        [[ $1 =~ ^[0-9]+$ ]]
        printf '%s\t\n' "$1" | "$backend" delete
        ;;
    preview)
        umask 077
        mkdir -p -- "$(dirname -- "$2")"
        set -C
        decode "$1" > "$2"
        ;;
    *) exit 2 ;;
esac
