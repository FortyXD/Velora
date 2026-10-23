#!/usr/bin/env bash
# Compiles the animated wallpaper shaders (services/ShaderWallpaper.qml) for Qt Quick. Run after editing a .frag.
cd "$(dirname "$0")" || exit 1
for f in *.frag; do
    /usr/lib/qt6/bin/qsb --qt6 -o "$f.qsb" "$f" || exit 1
done
