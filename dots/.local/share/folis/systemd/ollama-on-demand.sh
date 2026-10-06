#!/usr/bin/env bash
# Makes Ollama start on the first request and stop after 10 minutes without connections,
# instead of running all the time. Clients (ollama CLI, the shell) keep using 127.0.0.1:11434.
# Usage: sudo ollama-on-demand.sh          install
#        sudo ollama-on-demand.sh --undo   back to the always-on ollama.service
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
units=/etc/systemd/system

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
command -v ollama >/dev/null || { echo "Ollama is not installed, nothing to do."; exit 0; }

if [[ "${1:-}" == "--undo" ]]; then
    systemctl disable --now ollama-proxy.socket ollama-proxy.service 2>/dev/null || true
    rm -f "$units/ollama-proxy.socket" "$units/ollama-proxy.service" "$units/ollama.service.d/folis-on-demand.conf"
    rmdir "$units/ollama.service.d" 2>/dev/null || true
    systemctl daemon-reload
    systemctl enable --now ollama.service
    echo "Ollama runs all the time again."
    exit 0
fi

install -Dm644 "$src/ollama.service.d/folis-on-demand.conf" "$units/ollama.service.d/folis-on-demand.conf"
install -Dm644 "$src/ollama-proxy.socket" "$units/ollama-proxy.socket"
install -Dm644 "$src/ollama-proxy.service" "$units/ollama-proxy.service"
systemctl daemon-reload
systemctl disable --now ollama.service
systemctl enable --now ollama-proxy.socket
echo "Done: Ollama starts on demand and stops after 10 idle minutes."
