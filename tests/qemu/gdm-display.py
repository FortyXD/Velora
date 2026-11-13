#!/usr/bin/env python3
"""Guest-only temporary GDM monitor changes through Mutter's public D-Bus API."""
import argparse
import json
import os
from pathlib import Path
import pwd
from gi.repository import Gio, GLib

if not Path('/var/lib/velora-qemu-ready').exists():
    raise SystemExit('Only run inside QEMU as the GDM greeter user')
parser = argparse.ArgumentParser()
parser.add_argument('--width', type=int, default=1280)
parser.add_argument('--height', type=int, default=800)
parser.add_argument('--scale', type=float, default=1)
args = parser.parse_args()
uid = pwd.getpwnam('gdm-greeter').pw_uid
os.environ['DBUS_SESSION_BUS_ADDRESS'] = f'unix:path=/run/user/{uid}/bus'
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
def call(method, parameters=None):
    return bus.call_sync('org.gnome.Mutter.DisplayConfig', '/org/gnome/Mutter/DisplayConfig',
        'org.gnome.Mutter.DisplayConfig', method, parameters, None, Gio.DBusCallFlags.NONE, 10000, None).unpack()
serial, monitors, logical, properties = call('GetCurrentState')
connector = monitors[0][0][0]
modes = monitors[0][1]
mode = next(m for m in modes if m[1:3] == (args.width, args.height) or list(m[1:3]) == [args.width, args.height])
call('ApplyMonitorsConfig', GLib.Variant('(uua(iiduba(ssa{sv}))a{sv})',
    (serial, 1, [(0, 0, args.scale, 0, True, [(connector, mode[0], {})])], {})))
print(json.dumps({'resolution': [args.width, args.height], 'scale': args.scale, 'temporary': True}))
