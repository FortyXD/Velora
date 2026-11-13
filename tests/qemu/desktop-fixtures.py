#!/usr/bin/env python3
"""Guest-only visual fixtures and an explicit Hyprland 0.57.0 test session."""
import json
from pathlib import Path
import subprocess
import zipfile
from PIL import Image, ImageDraw

if not Path('/var/lib/velora-qemu-ready').exists():
    raise SystemExit('This script is only for the disposable Velora QEMU guest')

home = Path.home()
samples = home / 'Preview samples'
samples.mkdir(exist_ok=True)
frames = []
for index, color in enumerate(['#ffb692', '#adcdb5', '#c5baff']):
    picture = Image.new('RGB', (800, 500), '#261812')
    painter = ImageDraw.Draw(picture)
    painter.rounded_rectangle((80 + index * 60, 100, 520 + index * 60, 400), 45, fill=color)
    painter.text((110, 160), f'Velora Quick Look / frame {index + 1}', fill='#261812', font_size=30)
    frames.append(picture)
frames[0].save(samples / 'Осень и пробелы.png')
frames[0].save(samples / 'animation.gif', save_all=True, append_images=frames[1:], duration=300, loop=0)
frames[0].save(samples / 'document.pdf', save_all=True, append_images=frames[1:])
(samples / 'notes.txt').write_text('Velora Quick Look\n\nКириллица, пробелы и обычный текст.\n' * 8)
(samples / 'large.txt').write_text('Large file preview\n' * 100000)
(samples / 'broken.pdf').write_bytes(b'%PDF-1.7\nbroken')
(samples / 'unknown.bin').write_bytes(bytes(range(256)) * 4)
(home / 'upload-test.html').write_text('''<!doctype html><meta charset="utf-8">
<style>body{background:#261812;color:#f5dfd3;font:24px sans-serif;padding:60px}input{font:20px sans-serif}</style>
<h1>Velora · KDE portal</h1><label>Choose files <input type="file" multiple accept="image/*,.txt,.pdf"></label>''')
profile = home / 'firefox-qemu'
profile.mkdir(exist_ok=True)
(profile / 'user.js').write_text('''user_pref("widget.use-xdg-desktop-portal.file-picker", 1);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
''')
with zipfile.ZipFile(samples / 'archive.zip', 'w') as archive:
    archive.writestr('папка/документ.txt', 'Preview lists entries without extraction')
subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=12', '-t', '5',
                '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(samples / 'video.mp4')], check=True)
subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=4', str(samples / 'audio.wav')], check=True)

(home / 'qemu-hyprland.lua').write_text('''hl.monitor({output = "", mode = "1280x800@60", position = "0x0", scale = 1})
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("QT_PLUGIN_PATH", os.getenv("HOME") .. "/.local/share/velora/qt6/plugins")
hl.env("QT_QPA_GENERIC_PLUGINS", "velora-file-dialog")
hl.config({general = {gaps_in = 8, gaps_out = 16}, decoration = {rounding = 16, blur = {enabled = false}}, animations = {enabled = false}, input = {kb_layout = "us,ru", kb_options = "grp:alt_shift_toggle"}})
hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_PLUGIN_PATH QT_QPA_GENERIC_PLUGINS QT_QPA_PLATFORMTHEME")
    hl.exec_cmd("foot")
end)
package.path = os.getenv("HOME") .. "/.config/hypr/?.lua;" .. package.path
require("hyprland.rules")
''')
launcher = home / 'qemu-hyprland'
launcher.write_text('''#!/bin/sh
exec env LIBGL_ALWAYS_SOFTWARE=1 LD_LIBRARY_PATH="$HOME/hyprland0570/usr/lib" "$HOME/hyprland0570/usr/bin/Hyprland" --config "$HOME/qemu-hyprland.lua"
''')
launcher.chmod(0o755)
desktop = home / 'velora-qemu.desktop'
desktop.write_text(f'''[Desktop Entry]
Name=Velora QEMU (Hyprland 0.57.0)
Exec={launcher}
Type=Application
DesktopNames=Hyprland
''')
subprocess.run(['sudo', 'install', '-m644', str(desktop), '/usr/share/wayland-sessions/velora-qemu.desktop'], check=True)
print(json.dumps({'samples': str(samples), 'session': str(launcher)}))
