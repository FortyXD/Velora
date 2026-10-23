#!/usr/bin/env bash
set -euo pipefail
velora_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec "$velora_root/velora" install "$@"
