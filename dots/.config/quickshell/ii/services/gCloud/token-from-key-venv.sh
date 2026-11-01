#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

venv="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/.venv}"
if [[ "$venv" == '~/'* ]]; then venv="$HOME/${venv:2}"; fi
exec "$venv/bin/python" "$SCRIPT_DIR/token_from_key.py" "$@"
