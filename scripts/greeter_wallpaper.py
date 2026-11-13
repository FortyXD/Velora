#!/usr/bin/env python3
"""GDM wallpaper bridge: unprivileged image sandbox -> authenticated RGB socket.

The system service runs as a dedicated user, never root. No client path, URL or
compressed image crosses its socket. See docs/desktop-extras.md for the boundary.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import resource
import signal
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import time
import warnings

CONFIG = Path('/etc/velora/greeter-wallpaper.json')
STATE = Path('/var/lib/velora-greeter')
SOCKET = '/run/velora-greeter-wallpaper.sock'
HEADER = struct.Struct('!4sII')
MAX_EDGE = 2560
MAX_PIXELS = 2560 * 1600
MAX_INPUT = 64 * 1024 * 1024
IMAGE_NAME = re.compile(r'wallpaper-[a-f0-9]{64}\.jpg\Z')
CLEAN_ENV = {'PATH': '/usr/bin', 'LANG': 'C.UTF-8'}


def configuration():
    info = CONFIG.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022 or info.st_size > 4096:
        raise ValueError('Wallpaper configuration must be a root-owned, non-writable regular file')
    value = json.loads(CONFIG.read_bytes())
    if type(value.get('owner_uid')) is not int or value['owner_uid'] < 1000:
        raise ValueError('Wallpaper owner must be a regular user')
    return value


def loginctl(*args):
    return subprocess.check_output(['/usr/bin/loginctl', *args], env=CLEAN_ENV,
                                   text=True, timeout=2, stderr=subprocess.DEVNULL).strip()


def active_desktop(uid):
    """Authorization is account-based: its local graphical session must be unlocked."""
    try:
        sessions = loginctl('show-user', str(uid), '-p', 'Sessions', '--value').split()
        for session in sessions[:32]:
            if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}', session):
                continue
            keys = ('User', 'Active', 'Remote', 'Class', 'Type', 'Seat', 'LockedHint', 'Desktop')
            props = dict(line.split('=', 1) for line in loginctl(
                'show-session', session, *[part for key in keys for part in ('-p', key)]).splitlines() if '=' in line)
            if (props.get('User') == str(uid) and props.get('Active') == 'yes'
                    and props.get('Remote') == 'no' and props.get('Class') == 'user'
                    and props.get('Type') in ('wayland', 'x11') and props.get('Seat')
                    and props.get('LockedHint') == 'no'):
                return props.get('Desktop') or props['Type']
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def receive(connection, size, deadline):
    data = bytearray()
    while len(data) < size:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Incomplete wallpaper request')
        connection.settimeout(remaining)
        chunk = connection.recv(min(65536, size - len(data)))
        if not chunk:
            raise ValueError('Truncated wallpaper request')
        data.extend(chunk)
    return bytes(data)


def read_frame(connection):
    deadline = time.monotonic() + 4
    magic, width, height = HEADER.unpack(receive(connection, HEADER.size, deadline))
    if magic == b'VCLR' and width == height == 0:
        frame = None
    elif (magic == b'VRG1' and 0 < width <= MAX_EDGE and 0 < height <= MAX_EDGE
          and width * height <= MAX_PIXELS):
        frame = width, height, receive(connection, width * height * 3, deadline)
    else:
        raise ValueError('Invalid wallpaper dimensions or protocol')
    connection.settimeout(max(.001, deadline - time.monotonic()))
    if connection.recv(1):
        raise ValueError('Trailing wallpaper data')
    return frame


def atomic(path, data):
    # STATE is service-owned, never writable by callers. Replace, never follow links.
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.pending-', delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(data)
            output.flush()
            os.fchmod(output.fileno(), 0o644)
            os.fsync(output.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def publish(frame, authorized):
    """Encode trusted bounded pixels; authorize again immediately before committing."""
    previous = ''
    try:
        previous = json.loads((STATE / 'current.json').read_bytes()).get('image', '')
    except (OSError, ValueError, AttributeError):
        pass
    name = ''
    if frame is not None:
        from PIL import Image, ImageFilter, ImageEnhance
        width, height, pixels = frame
        picture = Image.frombytes('RGB', (width, height), pixels)
        picture = ImageEnhance.Brightness(picture.filter(ImageFilter.GaussianBlur(16))).enhance(.54)
        output = io.BytesIO()
        picture.save(output, format='JPEG', quality=90)
        data = output.getvalue()
        name = 'wallpaper-' + hashlib.sha256(data).hexdigest() + '.jpg'
    if not authorized():
        raise PermissionError('Local graphical session is no longer active and unlocked')
    if name:
        atomic(STATE / name, data)
    atomic(STATE / 'current.json', (json.dumps({'image': name}) + '\n').encode())
    keep = (name, previous) if name else ()
    for path in STATE.iterdir():
        if (IMAGE_NAME.fullmatch(path.name) and path.name not in keep) or path.name.startswith('.pending-'):
            path.unlink(missing_ok=True)


def handle(connection, owner, last_update=0):
    _, uid, _ = struct.unpack('3i', connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
    if uid != owner or not active_desktop(owner):
        raise PermissionError('Only the configured active local account may change the login wallpaper')
    if time.monotonic() - last_update < 1:
        raise ValueError('Wallpaper updates are limited to once per second')
    frame = read_frame(connection)
    publish(frame, lambda: active_desktop(owner))
    connection.sendall(b'OK\n')


def serve():
    owner = configuration()['owner_uid']
    if os.geteuid() == 0:
        raise PermissionError('The wallpaper service must not run as root')
    if os.environ.get('LISTEN_PID') != str(os.getpid()) or os.environ.get('LISTEN_FDS') != '1':
        raise ValueError('Requires exactly one systemd activation socket')
    last_update = 0
    with socket.socket(fileno=3) as listener:
        listener.settimeout(30)
        while True:
            try:
                connection, _ = listener.accept()
            except TimeoutError:
                return
            with connection:
                try:
                    handle(connection, owner, last_update)
                    last_update = time.monotonic()
                except (OSError, ValueError, MemoryError) as error:
                    # Do not log client data or paths; journald also rate-limits this unit.
                    print(type(error).__name__ + ': wallpaper request rejected', flush=True)
                    try:
                        connection.settimeout(.1)
                        connection.sendall(b'ERROR\n')
                    except OSError:
                        pass


def encode():
    """Runs only inside bubblewrap, with one input and no network or user home."""
    resource.setrlimit(resource.RLIMIT_CPU, (8, 8))
    resource.setrlimit(resource.RLIMIT_AS, (512 * 1024**2, 512 * 1024**2))
    resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024**2, 16 * 1024**2))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    from PIL import Image, ImageOps
    Image.MAX_IMAGE_PIXELS = 24_000_000
    warnings.simplefilter('error', Image.DecompressionBombWarning)
    with Image.open('/input', formats=['JPEG', 'PNG', 'WEBP', 'GIF', 'BMP', 'TIFF']) as picture:
        # First frame of animated images. No external converters or metadata survive.
        picture = ImageOps.exif_transpose(picture)
        picture.thumbnail((2560, 1600))
        if picture.mode in ('RGBA', 'LA', 'P'):
            rgba = picture.convert('RGBA')
            picture = Image.new('RGB', rgba.size, '#261812')
            picture.paste(rgba, mask=rgba.getchannel('A'))
        picture = picture.convert('RGB')
        sys.stdout.buffer.write(HEADER.pack(b'VRG1', *picture.size) + picture.tobytes())


def decode(path):
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_INPUT:
            raise ValueError('Wallpaper must be a regular image no larger than 64 MiB')
        command = ['/usr/bin/prlimit', '--as=536870912', '--cpu=10', '--fsize=67108864', '--core=0', '--',
                   '/usr/bin/bwrap', '--die-with-parent', '--unshare-all', '--new-session',
                   '--cap-drop', 'ALL', '--clearenv', '--ro-bind', '/usr', '/usr',
                   '--symlink', 'usr/lib', '/lib', '--symlink', 'usr/lib', '/lib64',
                   '--symlink', 'usr/bin', '/bin', '--proc', '/proc', '--dev', '/dev', '--tmpfs', '/tmp',
                   '--ro-bind', str(Path(__file__).resolve()), '/worker.py',
                   '--ro-bind-data', str(fd), '/input', '--chdir', '/tmp',
                   '--setenv', 'PATH', '/usr/bin', '/usr/bin/python3', '-I', '/worker.py', 'encode']
        # A regular output file, not an unbounded in-memory subprocess pipe.
        with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
            process = subprocess.Popen(command, pass_fds=(fd,), stdout=output, stderr=errors,
                                       start_new_session=True, env=CLEAN_ENV)
            try:
                result = process.wait(timeout=12)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                raise ValueError('Wallpaper decoding timed out') from None
            if result:
                raise ValueError('Wallpaper decoding failed inside the sandbox')
            output.seek(0)
            data = output.read(HEADER.size + MAX_PIXELS * 3 + 1)
            if len(data) > HEADER.size + MAX_PIXELS * 3 or len(data) < HEADER.size:
                raise ValueError('Invalid decoded wallpaper size')
            return data
    finally:
        os.close(fd)


def send(data):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(15)
        connection.connect(SOCKET)
        connection.sendall(data)
        connection.shutdown(socket.SHUT_WR)
        if connection.recv(16) != b'OK\n':
            raise ValueError('Wallpaper update was not accepted')


def local_path(value):
    from urllib.parse import urlsplit, unquote
    value = str(value)
    if value.startswith('file:'):
        uri = urlsplit(value)
        if uri.netloc not in ('', 'localhost') or uri.query or uri.fragment:
            raise ValueError('Wallpaper must be a local file')
        value = unquote(uri.path)
    path = Path(value).expanduser()
    if not path.is_absolute():
        raise ValueError('Wallpaper must be an absolute local path')
    return path


def watch():
    from gi.repository import Gio, GLib
    owner = configuration()['owner_uid']
    if owner != os.getuid():
        return
    background = Gio.Settings.new('org.gnome.desktop.background')
    interface = Gio.Settings.new('org.gnome.desktop.interface')
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    options = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'illogical-impulse/config.json'
    loop = GLib.MainLoop()
    last_key = None
    failed_decode = None
    last_error = None
    pending = 0

    def refresh():
        nonlocal last_key, last_error, pending, failed_decode
        pending = 0
        try:
            if configuration()['owner_uid'] != owner:
                loop.quit()
                return False
            desktop = active_desktop(owner)
            if not desktop:
                return False
            settings = json.loads(options.read_bytes()).get('background', {}) if options.exists() else {}
            enabled = settings.get('syncGreeterWallpaper', True) is not False
            if not enabled:
                key, data = ('disabled',), HEADER.pack(b'VCLR', 0, 0)
            else:
                # Some GDM sessions leave logind's Desktop empty. Resolve GNOME
                # on this user's bus rather than inheriting a stale manager env.
                gnome = 'gnome' in desktop.lower()
                if desktop in ('wayland', 'x11'):
                    gnome = bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                        'org.freedesktop.DBus', 'NameHasOwner', GLib.Variant('(s)', ('org.gnome.Shell',)),
                        GLib.VariantType.new('(b)'), Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
                if gnome:
                    dark = interface.get_string('color-scheme') == 'prefer-dark'
                    value = background.get_string('picture-uri-dark' if dark else 'picture-uri')
                else:
                    value = settings.get('wallpaperPath', '')
                    if Path(value).suffix.lower() in ('.mp4', '.webm', '.mkv', '.mov', '.avi', '.m4v'):
                        value = settings.get('thumbnailPath', '')
                if not value:
                    return False
                path = local_path(value)
                info = path.stat()
                key = (str(path), info.st_dev, info.st_ino, info.st_mtime_ns, info.st_size)
                if key in (last_key, failed_decode):
                    return False
                try:
                    data = decode(path)
                except ValueError:
                    failed_decode = key
                    raise
            if key != last_key:
                send(data)
                last_key, last_error = key, None
                print('Login wallpaper updated' if enabled else 'Bundled login wallpaper restored', flush=True)
        except FileNotFoundError:
            if not CONFIG.exists():
                loop.quit()
        except (OSError, ValueError, TypeError, AttributeError, GLib.Error) as error:
            # Retry on later changes/session activation; keep the last published image.
            message = type(error).__name__ + ': login wallpaper unchanged'
            if message != last_error:
                print(message, flush=True)
                last_error = message
        return False

    def changed(*_):
        nonlocal pending
        if pending:
            GLib.source_remove(pending)
        pending = GLib.timeout_add(1100, refresh)

    options.parent.mkdir(parents=True, exist_ok=True)
    monitor = Gio.File.new_for_path(str(options.parent)).monitor_directory(Gio.FileMonitorFlags.NONE, None)
    monitor.connect('changed', changed)
    background.connect('changed', changed)
    interface.connect('changed::color-scheme', changed)
    # Covers session activation and editing the image in place, with no permanent
    # image parser or root process. Config/GSettings changes are debounced immediately.
    GLib.timeout_add_seconds(15, lambda: (changed(), True)[1])
    changed()
    loop.run()
    monitor.cancel()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('serve', 'watch', 'encode', 'sync'))
    parser.add_argument('image', nargs='?')
    args = parser.parse_args()
    if args.action == 'sync':
        if not args.image:
            parser.error('sync requires an image path')
        send(decode(local_path(args.image)))
    else:
        globals()[args.action]()


if __name__ == '__main__':
    main()
