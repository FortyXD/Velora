#!/usr/bin/env bash
# Shared user-facing capture entry point; ordinary options are forwarded to grim.
set -euo pipefail
umask 077

cursor_args=()
case "${VELORA_SCREENSHOT_CURSOR-}" in
    true) cursor_args+=(-c) ;;
    false) ;;
    "")
        config="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
        if jq -e '.screenSnip.showCursor == true' "$config" >/dev/null 2>&1; then
            cursor_args+=(-c)
        fi
        ;;
    *)
        printf 'Invalid VELORA_SCREENSHOT_CURSOR: expected true or false\n' >&2
        exit 2
        ;;
esac

image=""
original_cursor_mode=""
set_cursor_mode() {
    # Reapply the current position to refresh cursor planes without moving it.
    hyprctl eval "hl.config({cursor={no_hardware_cursors=$1}}); local p=hl.get_cursor_pos(); hl.dispatch(hl.dsp.cursor.move({x=p.x,y=p.y}))" >/dev/null
}
cleanup() {
    if [[ -n "$original_cursor_mode" ]]; then
        # Do not overwrite an unrelated display-settings change made meanwhile.
        current=$(hyprctl getoption cursor:no_hardware_cursors -j 2>/dev/null | jq -r '.int' 2>/dev/null) || current=""
        if [[ "$current" == 0 ]]; then
            set_cursor_mode "$original_cursor_mode" || printf 'Could not restore screenshot cursor mode\n' >&2
        fi
    fi
    if [[ -n "$image" ]]; then rm -f -- "$image" || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_capture_tool() {
    # wl-copy may fork a long-lived clipboard owner. Only this shell may hold
    # the lock; inherited descriptors would block every subsequent capture.
    if [[ -n "${cursor_lock:-}" ]]; then "$@" {cursor_lock}>&-; else "$@"; fi
}

copy=false
case "${1-}" in
    --select-region)
        # Cancellation must not replace the clipboard or change cursor mode.
        region=$(slurp) || exit $?
        [[ -n "$region" ]] || exit 1
        set -- -g "$region"
        copy=true
        ;;
    --clipboard)
        shift
        copy=true
        ;;
esac

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
    # All captures share the lock, including cursor-on requests, so a temporary
    # hardware-cursor override cannot race another capture or its restoration.
    exec {cursor_lock}>"$XDG_RUNTIME_DIR/velora-screenshot-cursor.lock"
    flock "$cursor_lock"
    if [[ ${#cursor_args[@]} == 0 ]]; then
        mode=$(hyprctl getoption cursor:no_hardware_cursors -j 2>/dev/null | jq -r '.int' 2>/dev/null) || mode=""
        case "$mode" in
            1|2)
                # Software-composited cursors are baked into grim's frames even
                # without -c. Switch planes only for capture, then restore.
                original_cursor_mode="$mode"
                set_cursor_mode 0
                ;;
        esac
    fi
fi

if "$copy"; then
    image=$(mktemp "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/velora-screenshot.XXXXXX")
    run_capture_tool grim "${cursor_args[@]}" "$@" "$image"
    run_capture_tool wl-copy --type image/png < "$image"
else
    run_capture_tool grim "${cursor_args[@]}" "$@"
fi
