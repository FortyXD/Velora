#!/usr/bin/env bash
# Fallback for the OCR keybinding when the shell isn't running.
set -euo pipefail
umask 077
image=$(mktemp --suffix=.png)
trap 'rm -f -- "$image"' EXIT
# SLURP_ARGS is a list of arguments, not shell source.
read -r -a selection_args <<< "${SLURP_ARGS:-}"
area=$(slurp "${selection_args[@]}")
grim -g "$area" "$image"
languages=$(tesseract --list-langs | awk 'NR>1{print $1}' | paste -sd+ -)
tesseract "$image" stdout -l "$languages" | wl-copy
