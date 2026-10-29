#!/usr/bin/env bash
# Compiles the shaders for Qt Quick: the animated wallpapers (services/ShaderWallpaper.qml) and the theme
# transition (themeWave). Run after editing a .frag.
cd "$(dirname "$0")" || exit 1
for f in *.frag; do
    /usr/lib/qt6/bin/qsb --qt6 -o "$f.qsb" "$f" || exit 1
done
