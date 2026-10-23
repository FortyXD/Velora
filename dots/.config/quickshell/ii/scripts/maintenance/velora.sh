#!/usr/bin/env bash
set -euo pipefail
for velora_binary in "$HOME/.local/bin/velora" /usr/bin/velora; do
    if [[ -x $velora_binary ]]; then
        exec "$velora_binary" "$@"
    fi
done
velora_script=$(readlink -f -- "${BASH_SOURCE[0]}")
velora_root=$(cd -- "$(dirname -- "$velora_script")/../../../../../.." && pwd -P)
if [[ -x $velora_root/velora ]]; then
    exec "$velora_root/velora" "$@"
fi
printf 'Velora maintenance tools are unavailable. Run ./velora install from your checkout.\n' >&2
exit 1
