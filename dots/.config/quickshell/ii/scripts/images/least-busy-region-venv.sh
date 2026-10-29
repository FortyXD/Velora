#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The native helper does the same search in a fraction of the time, on one core instead of all of
# them, so placing desktop widgets doesn't stutter animations. It has no largest-region or drawing mode.
helper="${VELORA_HELPER-$(command -v velora-helper 2>/dev/null || { [[ -x "$HOME/.local/bin/velora-helper" ]] && echo "$HOME/.local/bin/velora-helper"; })}"
if [[ -n "$helper" ]] && ! printf '%s\n' "$@" | grep -qxE -- '-l|--largest-region|-v|--visual-output'; then
    # Exec, so canceling an obsolete analysis stops its work
    exec "$helper" region "$@"
fi

analysis_venv="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/.venv}"
# Keep the Python process as the job itself, so canceling an obsolete analysis
# actually stops its CPU work instead of leaving a child behind.
exec "$analysis_venv/bin/python3" "$SCRIPT_DIR/least_busy_region.py" "$@"
