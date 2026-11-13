#!/usr/bin/env python3
"""Run a command on the guest's Hyprland desktop from an SSH test connection."""
import argparse
import json
import os
from pathlib import Path
import subprocess

if not Path('/var/lib/velora-qemu-ready').exists():
    raise SystemExit('Only run this in the disposable QEMU guest')
parser = argparse.ArgumentParser()
parser.add_argument('--detach', action='store_true')
parser.add_argument('--log', default='desktop-command.log')
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
instance = json.loads(subprocess.check_output(['hyprctl', '-j', 'instances']))[0]
runtime = f'/run/user/{os.getuid()}'
environment = dict(os.environ, XDG_RUNTIME_DIR=runtime, DBUS_SESSION_BUS_ADDRESS=f'unix:path={runtime}/bus',
                   HYPRLAND_INSTANCE_SIGNATURE=instance['instance'], WAYLAND_DISPLAY=instance['wl_socket'],
                   XDG_CURRENT_DESKTOP='Hyprland', QT_QPA_PLATFORM='wayland', QT_QPA_PLATFORMTHEME='kde',
                   QT_PLUGIN_PATH=str(Path.home() / '.local/share/velora/qt6/plugins'), QT_QPA_GENERIC_PLUGINS='velora-file-dialog')
if args.detach:
    with (Path.home() / 'evidence' / args.log).open('w') as log:
        process = subprocess.Popen(args.command, env=environment, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        print(process.pid)
else:
    raise SystemExit(subprocess.call(args.command, env=environment))
