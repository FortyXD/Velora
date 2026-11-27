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
from typing import NamedTuple
import warnings
from string import Template

CONFIG = Path('/etc/velora/greeter-wallpaper.json')
STATE = Path('/var/lib/velora-greeter')
SOCKET = '/run/velora-greeter-wallpaper.sock'
HEADER = struct.Struct('!4sII')
PALETTE_TEMPLATE = Path('/usr/lib/velora/greeter-palette.css.in')
# Fixed wire order for VPL1. Only RGB triples may cross the socket.
PALETTE_ROLES = ('primary', 'on_primary', 'surface', 'on_surface', 'surface_container',
                 'secondary_container', 'on_secondary_container', 'outline', 'error')
MAX_EDGE = 2560
MAX_PIXELS = 2560 * 1600
MAX_INPUT = 64 * 1024 * 1024
IMAGE_ADDRESS_SPACE = 512 * 1024**2
VIDEO_ADDRESS_SPACE = 1024**3  # FFmpeg maps shared codec libraries and worker stacks.
IMAGE_NAME = re.compile(r'wallpaper-[a-f0-9]{64}\.jpg\Z')
CLEAN_ENV = {'PATH': '/usr/bin', 'LANG': 'C.UTF-8'}


SHADERS = ('aurora', 'liquid', 'grid', 'dunes')
SHADER = struct.Struct('!BBB12s')  # preset index, speed in twentieths, fps, four RGB colors


# Only raw RGB cells cross the greeter privilege boundary.
CELL = (512, 288)
FPS, MAX_FRAMES = 8, 64
FRAME_BYTES = CELL[0] * CELL[1] * 3
MAX_WIRE = HEADER.size + 1 + FRAME_BYTES * MAX_FRAMES
MEDIA_SUFFIXES = {'.gif', '.webp', '.mp4', '.webm', '.mkv', '.mov', '.avi', '.m4v'}
ATLAS_NAME = re.compile(r'animation-[a-f0-9]{64}\.jpg\Z')


class MediaLoop(NamedTuple):
    count: int
    pixels: bytes


class AnimatedWallpaper(NamedTuple):
    image: tuple
    shader: dict


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
    shader = None
    if magic == b'VSH1':
        preset, speed, fps, rgb = SHADER.unpack(receive(connection, SHADER.size, deadline))
        if preset >= len(SHADERS) or not 5 <= speed <= 60 or not 5 <= fps <= 60:
            raise ValueError('Invalid shader preset or playback rate')
        shader = dict(name=SHADERS[preset], speed=speed / 20, fps=fps,
                      colors=[rgb[i:i + 3].hex() for i in range(0, len(rgb), 3)])
        magic = b'VRG1'
    if magic == b'VAN1' and (width, height) == CELL:
        count = receive(connection, 1, deadline)[0]
        if not 1 <= count <= MAX_FRAMES:
            raise ValueError('Invalid animation length')
        frame = MediaLoop(count, receive(connection, count * FRAME_BYTES, deadline))
    elif magic == b'VCLR' and width == height == 0:
        frame = None
    elif magic == b'VPL1' and width in (0, len(PALETTE_ROLES)) and height == 1:
        frame = receive(connection, width * 3, deadline)
    elif (magic == b'VRG1' and 0 < width <= MAX_EDGE and 0 < height <= MAX_EDGE
          and width * height <= MAX_PIXELS):
        frame = width, height, receive(connection, width * height * 3, deadline)
    else:
        raise ValueError('Invalid wallpaper dimensions or protocol')
    connection.settimeout(max(.001, deadline - time.monotonic()))
    if connection.recv(1):
        raise ValueError('Trailing wallpaper data')
    return AnimatedWallpaper(frame, shader) if shader else frame


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
    """Publish wallpaper pixels or palette roles after rechecking the active session."""
    if isinstance(frame, bytes):
        path = STATE / 'palette.css'
        if frame:
            colors = {role: '#' + bytes(rgb).hex() for role, rgb in
                      zip(PALETTE_ROLES, struct.iter_unpack('BBB', frame), strict=True)}
            css = Template(PALETTE_TEMPLATE.read_text()).substitute(colors).encode()
        if not authorized():
            raise PermissionError('Local graphical session is no longer active and unlocked')
        if frame:
            atomic(path, css)
        else:
            path.unlink(missing_ok=True)
        return
    previous = {}
    try:
        previous = json.loads((STATE / 'current.json').read_bytes())
    except (OSError, ValueError, AttributeError):
        pass
    manifest = {}
    if isinstance(frame, AnimatedWallpaper):
        manifest['shader'] = frame.shader
        frame = frame.image
    atlas_data = None
    if isinstance(frame, MediaLoop):
        from PIL import Image, ImageEnhance
        columns = min(8, frame.count)
        atlas = Image.new('RGB', (CELL[0] * columns, CELL[1] * ((frame.count + columns - 1) // columns)))
        for i in range(frame.count):
            raw = frame.pixels[i * FRAME_BYTES:(i + 1) * FRAME_BYTES]
            tile = ImageEnhance.Brightness(Image.frombytes('RGB', CELL, raw)).enhance(.54)
            atlas.paste(tile, (i % columns * CELL[0], i // columns * CELL[1]))
        buf = io.BytesIO()
        atlas.save(buf, format='JPEG', quality=86)
        atlas_data = buf.getvalue()
        manifest['animation'] = {'atlas': 'animation-' + hashlib.sha256(atlas_data).hexdigest() + '.jpg',
                                 'count': frame.count}
        frame = (*CELL, frame.pixels[:FRAME_BYTES])
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
    if atlas_data is not None:
        atomic(STATE / manifest['animation']['atlas'], atlas_data)
    manifest['image'] = name
    atomic(STATE / 'current.json', (json.dumps(manifest) + '\n').encode())
    keep = {name, previous.get('image'), previous.get('animation', {}).get('atlas'), manifest.get('animation', {}).get('atlas')} if name else set()
    for path in STATE.iterdir():
        if ((IMAGE_NAME.fullmatch(path.name) or ATLAS_NAME.fullmatch(path.name)) and path.name not in keep) or path.name.startswith('.pending-'):
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


def media_pixels(kind, moving):
    """Decode inside the unprivileged namespace. Cap dimensions, duration and frame count."""
    from PIL import Image, ImageOps
    maximum = MAX_FRAMES if moving else 1
    if kind == 'animated-image':
        with Image.open('/input', formats=['GIF', 'WEBP']) as picture:
            if not getattr(picture, 'is_animated', False):
                return None
            data = bytearray()
            elapsed = emitted = 0
            for index in range(min(picture.n_frames, 2048)):
                picture.seek(index)
                elapsed += max(10, picture.info.get('duration', 100))
                end = min(maximum, max(1, round(elapsed * FPS / 1000)))
                if end > emitted:
                    tile = ImageOps.fit(picture.convert('RGB'), CELL).tobytes()
                    data.extend(tile * (end - emitted))
                    emitted = end
                if emitted == maximum: break
            return bytes(data)
    # File-only, with a restricted demuxer list. No user paths or streams in GDM.
    args = ['/usr/bin/ffmpeg', '-nostdin', '-v', 'error', '-cpucount', '1', '-max_alloc', str(MAX_INPUT),
            '-threads', '1', '-max_pixels', '24000000',
            '-protocol_whitelist', 'file,pipe', '-format_whitelist', 'mov,matroska,webm,avi',
            '-i', '/input', '-an', '-sn', '-dn', '-filter_threads', '1', '-vf',
            f'fps={FPS},scale=512:288:force_original_aspect_ratio=increase,crop=512:288',
            '-frames:v', str(maximum), '-threads', '1', '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1']
    return subprocess.check_output(args, timeout=8)


def encode(kind='', moving=True):
    """Runs only inside bubblewrap, with one input and no network or user home."""
    resource.setrlimit(resource.RLIMIT_CPU, (8, 8))
    address_space = VIDEO_ADDRESS_SPACE if kind == 'video' else IMAGE_ADDRESS_SPACE
    resource.setrlimit(resource.RLIMIT_AS, (address_space, address_space))
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_WIRE, MAX_WIRE))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    from PIL import Image, ImageOps
    Image.MAX_IMAGE_PIXELS = 24_000_000
    warnings.simplefilter('error', Image.DecompressionBombWarning)
    if kind:
        pixels = media_pixels(kind, moving)
        if pixels is not None:
            count, remainder = divmod(len(pixels), FRAME_BYTES)
            if remainder or not 1 <= count <= MAX_FRAMES: raise ValueError('Invalid decoded frames')
            header = HEADER.pack(b'VAN1', *CELL) + bytes([count]) if count > 1 else HEADER.pack(b'VRG1', *CELL)
            sys.stdout.buffer.write(header + pixels)
            return
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


def decode(path, *, motion=False):
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_INPUT:
            raise ValueError('Wallpaper must be a regular image no larger than 64 MiB')
        suffix = path.suffix.lower()
        video = suffix in MEDIA_SUFFIXES and suffix not in ('.gif', '.webp')
        address_space = VIDEO_ADDRESS_SPACE if video else IMAGE_ADDRESS_SPACE
        command = ['/usr/bin/prlimit', f'--as={address_space}', '--cpu=10', '--fsize=67108864', '--core=0', '--',
                   '/usr/bin/bwrap', '--die-with-parent', '--unshare-all', '--new-session',
                   '--cap-drop', 'ALL', '--clearenv', '--ro-bind', '/usr', '/usr',
                   '--symlink', str(Path('/lib').resolve()).lstrip('/'), '/lib',
                   '--symlink', str(Path('/lib64').resolve()).lstrip('/'), '/lib64',
                   '--symlink', 'usr/bin', '/bin', '--proc', '/proc', '--dev', '/dev', '--tmpfs', '/tmp',
                   '--ro-bind', str(Path(__file__).resolve()), '/worker.py',
                   '--ro-bind-data', str(fd), '/input', '--chdir', '/tmp',
                   '--setenv', 'PATH', '/usr/bin', '/usr/bin/python3', '-I', '/worker.py', 'encode']
        if video or (motion and suffix in ('.gif', '.webp')):
            command.append(('animated-image' if suffix in ('.gif', '.webp') else 'video') + ('-loop' if motion else '-still'))
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
                errors.seek(0)
                reason = errors.read(2048).decode(errors='replace').strip()
                raise ValueError('Wallpaper decoding failed inside the sandbox: ' + reason)
            output.seek(0)
            data = output.read(MAX_WIRE + 1)
            if len(data) > MAX_WIRE or len(data) < HEADER.size:
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


def shader_settings(config, palette_path):
    background = config.get('background', {})
    options = background.get('shaderWallpaper', {})
    name = options.get('name') if isinstance(options, dict) else None
    if not background.get('animateGreeterWallpaper', False) or name not in SHADERS:
        return b''
    colors = options.get('colors') or []
    try:
        if not colors:
            with palette_path.open('rb') as palette_file:
                raw = palette_file.read(8193)
            if len(raw) > 8192:
                return b''
            palette = json.loads(raw)
            overrides = config.get('appearance', {}).get('palette', {}).get('roleOverrides', {})
            colors = []
            for role in ('primary', 'tertiary', 'secondary'):
                custom = overrides.get(role)
                colors.append(custom if isinstance(custom, str) and re.fullmatch(r'#[0-9a-fA-F]{6}', custom) else palette[role])
            if not re.fullmatch(r'#[0-9a-fA-F]{6}', palette['background']):
                return b''
            bg = bytes.fromhex(palette['background'][1:])
            # ShaderWallpaperView mixes the primary with black in a light theme.
            colors.append(palette['background'] if min(bg) + max(bg) < 255 else
                          '#' + bytes(round(c * .35) for c in bytes.fromhex(colors[0][1:])).hex())
        if len(colors) != 4 or not all(isinstance(c, str) and re.fullmatch(r'#[a-fA-F0-9]{6}', c) for c in colors):
            return b''
        speed = round(float(options.get('speed', 1)) * 20)
        fps = int(options.get('fps', 30))
        return SHADER.pack(SHADERS.index(name), max(5, min(60, speed)), max(5, min(60, fps)),
                           bytes.fromhex(''.join(c[1:] for c in colors)))
    except (OSError, ValueError, KeyError, TypeError, AttributeError, OverflowError):
        return b''  # Keep the still image until the theme is ready.


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


def desktop_palette(path, overrides):
    with path.open('rb') as source:
        data = source.read(8193)
    if len(data) > 8192:
        raise ValueError('Oversized desktop palette')
    roles = json.loads(data)
    if not isinstance(roles, dict):
        raise ValueError('Invalid desktop palette')
    for key in PALETTE_ROLES:
        if not re.fullmatch(r'#[0-9a-fA-F]{6}', str(roles.get(key))):
            raise ValueError('Incomplete desktop palette')
    for key in ('primary', 'on_surface', 'surface_container'):
        custom = overrides.get(key)
        if not isinstance(custom, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', custom):
            continue
        roles[key] = custom
        if key == 'primary':
            # Match MaterialPalette.accentInk when the user overrides the accent.
            bg, fg = [luminance(roles[k]) for k in ('primary', 'on_primary')]
            if (max(bg, fg) + .05) / (min(bg, fg) + .05) < 4.5:
                roles['on_primary'] = '#000000' if bg > .179 else '#ffffff'
    return b''.join(bytes.fromhex(roles[key][1:]) for key in PALETTE_ROLES)


def luminance(color):
    channels = (v / 255 for v in bytes.fromhex(color[1:]))
    linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in channels]
    return sum(v * weight for v, weight in zip(linear, (.2126, .7152, .0722)))


def watch():
    from gi.repository import Gio, GLib
    owner = configuration()['owner_uid']
    if owner != os.getuid():
        return
    background = Gio.Settings.new('org.gnome.desktop.background')
    interface = Gio.Settings.new('org.gnome.desktop.interface')
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    options = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'velora/config.json'
    state_home = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
    palette_path = state_home / 'quickshell/user/generated/colors.json'
    loop = GLib.MainLoop()
    last_key = None
    last_palette = None
    failed_decode = None
    last_error = None
    pending = 0

    def refresh():
        nonlocal last_key, last_error, pending, failed_decode, last_palette
        pending = 0
        try:
            if configuration()['owner_uid'] != owner:
                loop.quit()
                return False
            desktop = active_desktop(owner)
            if not desktop:
                return False
            config = json.loads(options.read_bytes()) if options.exists() else {}
            settings = config.get('background', {})
            enabled = settings.get('syncGreeterWallpaper', True) is not False
            try:
                overrides = config.get('appearance', {}).get('palette', {}).get('roleOverrides', {})
                palette = (desktop_palette(palette_path, overrides)
                           if settings.get('syncGreeterPalette', False) else b'')
            except (OSError, ValueError, AttributeError):
                palette = None
            if palette is not None and palette != last_palette:
                send(HEADER.pack(b'VPL1', len(palette) // 3, 1) + palette)
                last_palette = palette
                # The socket accepts one update/second. Resume wallpaper sync after that interval.
                changed()
                return False
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
                lock = config.get('lock', {})
                source = lock.get('greeterSource', 'desktop')
                custom = lock.get('greeterPath', '') if source == 'file' else lock.get('backgroundPath', '') if source == 'lock' else ''
                motion = lock.get('animatedWallpaper', True) if source in ('file', 'lock') else settings.get('animateGreeterWallpaper', False)
                if custom:
                    value = custom
                elif gnome:
                    dark = interface.get_string('color-scheme') == 'prefer-dark'
                    value = background.get_string('picture-uri-dark' if dark else 'picture-uri')
                else:
                    value = settings.get('wallpaperPath', '')
                    if not motion and settings.get('thumbnailPath') and Path(value).suffix.lower() in ('.mp4', '.webm', '.mkv', '.mov', '.avi', '.m4v'):
                        value = settings.get('thumbnailPath', '')
                if not value:
                    return False
                path = local_path(value)
                info = path.stat()
                shader = b'' if gnome or custom or (source == 'lock' and not motion) else shader_settings(config, palette_path)
                key = (motion, shader, str(path), info.st_dev, info.st_ino, info.st_mtime_ns, info.st_size)
                if key in (last_key, failed_decode):
                    return False
                try:
                    try:
                        data = decode(path, motion=motion and not shader)
                    except ValueError:
                        if not motion: raise
                        data = decode(path, motion=False)
                    if shader:
                        data = b'VSH1' + data[4:HEADER.size] + shader + data[HEADER.size:]
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

    def palette_changed(_monitor, file, other, _event):
        if any(item and item.get_basename() == 'colors.json' for item in (file, other)):
            changed()

    try:
        palette_monitor = Gio.File.new_for_path(str(palette_path.parent)).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
        palette_monitor.connect('changed', palette_changed)
    except GLib.Error:
        palette_monitor = None  # The periodic refresh also covers first-time palette creation.
    background.connect('changed', changed)
    interface.connect('changed::color-scheme', changed)
    # Covers session activation and editing the image in place, with no permanent
    # image parser or root process. Config/GSettings changes are debounced immediately.
    GLib.timeout_add_seconds(15, lambda: (changed(), True)[1])
    changed()
    loop.run()
    monitor.cancel()
    if palette_monitor:
        palette_monitor.cancel()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('serve', 'watch', 'encode', 'sync'))
    parser.add_argument('image', nargs='?')
    args = parser.parse_args()
    if args.action == 'sync':
        if not args.image:
            parser.error('sync requires an image path')
        send(decode(local_path(args.image)))
    elif args.action == 'encode' and args.image:
        kind, _, mode = args.image.rpartition('-')
        if kind not in ('video', 'animated-image') or mode not in ('loop', 'still'): parser.error('Invalid decoder mode')
        encode(kind, mode == 'loop')
    else:
        globals()[args.action]()


if __name__ == '__main__':
    main()
