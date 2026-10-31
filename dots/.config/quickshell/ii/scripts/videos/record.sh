#!/usr/bin/env bash
# The shell asks for the status every second, so that one doesn't start an interpreter
if [[ $# -eq 1 && $1 == status ]]; then
    helper="${VELORA_HELPER:-$(type -P velora-helper || echo "$HOME/.local/bin/velora-helper")}"
    [[ -x $helper ]] && exec "$helper" recorder-status
fi
exec python3 "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/recorder.py" "$@"
