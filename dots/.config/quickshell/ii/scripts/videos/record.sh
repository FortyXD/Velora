#!/usr/bin/env bash
# Keep this entry point for shortcuts and third-party callers.
exec python3 "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/recorder.py" "$@"
