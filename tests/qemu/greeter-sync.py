#!/usr/bin/env python3
"""Live service checks, only in an installed QEMU guest with an unlocked desktop."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import time

if not Path('/var/lib/velora-qemu-ready').exists():
    raise SystemExit('Run only in the disposable QEMU guest')
spec = importlib.util.spec_from_file_location('bridge', '/usr/lib/velora/greeter-wallpaper.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
from PIL import Image, ImageDraw

root = Path.home() / 'evidence'
config = Path.home() / '.config/illogical-impulse/config.json'
manifest = Path('/var/lib/velora-greeter/current.json')
original = config.read_bytes()


def update(**changes):
    value = json.loads(config.read_bytes())
    value.setdefault('background', {}).update(changes)
    temporary = config.with_suffix('.sync-test')
    temporary.write_text(json.dumps(value))
    temporary.replace(config)


def current():
    return json.loads(manifest.read_bytes())['image'] if manifest.exists() else None


def wait_for(condition):
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(.2)
    raise AssertionError('Timed out waiting for wallpaper publication')


def log(message):
    print('PASS ' + message, flush=True)


for index, colors in enumerate([('#245a97', '#a8527c'), ('#168475', '#caa14f')]):
    picture = Image.new('RGB', (1600, 1000), colors[0])
    draw = ImageDraw.Draw(picture)
    draw.ellipse((200, 80, 1350, 1200), fill=colors[1])
    picture.save(root / f'sync-wallpaper-{index}.png')
image0, image1 = (str(root / f'sync-wallpaper-{i}.png') for i in range(2))
assert bridge.active_desktop(os.getuid())
update(syncGreeterWallpaper=False)
wait_for(lambda: current() == '')
before = current()
update(wallpaperPath=image0, syncGreeterWallpaper=True)
wait_for(lambda: current() and current() != before)
first = current()
log('ordinary Velora config change publishes without sudo')

update(wallpaperPath=image1)
wait_for(lambda: current() != first)
second = current()
log('second wallpaper replaces the first atomically')

bad = root / 'sync-damaged.png'
bad.write_bytes(b'broken png')
update(wallpaperPath=str(bad))
time.sleep(3)
assert current() == second
log('damaged image preserves last good wallpaper')

# An unauthorized account cannot update even when another account has a desktop.
code = "import socket; s=socket.socket(socket.AF_UNIX); s.connect('/run/velora-greeter-wallpaper.sock'); print(s.recv(16).decode().strip())"
answer = subprocess.check_output(['sudo', '-u', 'nobody', 'python3', '-c', code], text=True).strip()
assert answer == 'ERROR'
assert current() == second
log('different uid rejected using kernel peer credentials')

with socket.socket(socket.AF_UNIX) as client:
    client.connect(bridge.SOCKET)
    client.sendall(bridge.HEADER.pack(b'VRG1', 0xffffffff, 0xffffffff))
    client.shutdown(socket.SHUT_WR)
    assert client.recv(16) == b'ERROR\n'
assert current() == second
log('malformed payload preserves published wallpaper')

session = next(item for item in bridge.loginctl('show-user', str(os.getuid()), '-p', 'Sessions', '--value').split()
               if 'Active=yes' in bridge.loginctl('show-session', item, '-p', 'Active')
               and 'Type=wayland' in bridge.loginctl('show-session', item, '-p', 'Type')
               and 'Remote=no' in bridge.loginctl('show-session', item, '-p', 'Remote'))
path = '/org/freedesktop/login1/session/' + session
# This changes only the VM logind hint; it does not lock/kill the compositor.
def locked(value):
    subprocess.run(['busctl', 'call', 'org.freedesktop.login1', path,
                    'org.freedesktop.login1.Session', 'SetLockedHint', 'b', value], check=True)

locked('true')
try:
    assert bridge.active_desktop(os.getuid()) is None
    with socket.socket(socket.AF_UNIX) as client:
        client.connect(bridge.SOCKET)
        assert client.recv(16) == b'ERROR\n'
    update(wallpaperPath=image0)
    time.sleep(2)
    assert current() == second
    log('locked session cannot publish')
finally:
    locked('false')

update(syncGreeterWallpaper=False)
wait_for(lambda: current() == '')
log('settings toggle restores bundled Autumn')
update(syncGreeterWallpaper=True)
wait_for(lambda: current() not in ('', second))
log('re-enabling resumes automatic synchronization')

assert len(list(manifest.parent.glob('*.jpg'))) <= 2
assert not os.access(manifest.parent, os.W_OK)
assert manifest.stat().st_uid != 0
log('read-only public output, non-root owner, bounded history')
subprocess.run(['systemctl', '--user', 'restart', 'velora-greeter-wallpaper.service'], check=True)
wait_for(lambda: current() == first)
log('watcher restart preserves expected background')
(root / 'sync-original-config.json').write_bytes(original)
print('All live service checks passed; blue/pink wallpaper retained for GDM screenshots.', flush=True)
