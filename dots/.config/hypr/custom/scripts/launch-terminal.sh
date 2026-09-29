#!/usr/bin/env bash
set -euo pipefail

session_name="term-$(date +%Y%m%d-%H%M%S)-$$"

exec kitty -- tmux source-file "$HOME/.tmux.conf" \; source-file "$HOME/.config/tmux/tmux.conf" \; new-session -s "$session_name" -n zsh 'exec /bin/zsh -l'
