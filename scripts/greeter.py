#!/usr/bin/env python3
"""Opt-in GDM theme. Never modifies PAM, GDM sessions or GNOME's resources."""
import argparse
import ast
import hashlib
import json
import os
import pwd
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

UUID = 'velora-greeter@velora'
SUPPORTED = {'51.1'}
STATE = Path('/var/lib/velora/greeter')
EXTENSION = Path('/usr/share/gnome-shell/extensions') / UUID
PROFILE = Path('/etc/dconf/profile/gdm')
SETTINGS = Path('/etc/dconf/db/gdm.d/90-velora')
SYNC_CONFIG = Path('/etc/velora/greeter-wallpaper.json')
SYNC_STATE = Path('/var/lib/velora-greeter')
SYNC_FILES = {
    'scripts/greeter_wallpaper.py': Path('/usr/lib/velora/greeter-wallpaper.py'),
    'resources/greeter/velora-greeter-wallpaper.service': Path('/etc/systemd/system/velora-greeter-wallpaper.service'),
    'resources/greeter/velora-greeter-wallpaper.socket': Path('/etc/systemd/system/velora-greeter-wallpaper.socket'),
    'resources/greeter/velora-greeter-wallpaper-user.service': Path('/etc/systemd/user/velora-greeter-wallpaper.service'),
}
SYNC_SYSUSERS = Path('/etc/sysusers.d/velora-greeter.conf')
SYNC_SYSTEM_WANTS = Path('/etc/systemd/system/sockets.target.d/90-velora-greeter.conf')
SYNC_USER_WANTS = Path('/etc/systemd/user/default.target.d/90-velora-greeter.conf')


def sync_paths():
    return {*SYNC_FILES.values(), SYNC_CONFIG, SYNC_SYSUSERS, SYNC_SYSTEM_WANTS, SYNC_USER_WANTS}


def user_service(owner, action):
    if not Path(f'/run/user/{owner}/bus').exists():
        return
    account = pwd.getpwuid(owner)
    prefix = ['runuser', '-u', account.pw_name, '--', 'env', f'XDG_RUNTIME_DIR=/run/user/{owner}',
              f'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{owner}/bus', '/usr/bin/systemctl', '--user']
    subprocess.run([*prefix, 'daemon-reload'], check=True, timeout=10)
    subprocess.run([*prefix, action, 'velora-greeter-wallpaper.service'], check=True, timeout=10)


def sync_owner(requested=None):
    # The login background is global. Updates by another account never take it over.
    owner = json.loads(SYNC_CONFIG.read_bytes())['owner_uid'] if SYNC_CONFIG.exists() else requested
    if type(owner) is not int or owner < 1000 or pwd.getpwuid(owner).pw_shell.endswith(('nologin', 'false')):
        raise ValueError('Specify the normal desktop account with --owner-uid')
    return owner


def install_sync(transaction, source, owner):
    for relative, target in SYNC_FILES.items():
        data = (source / relative).read_bytes().replace(b'@OWNER_UID@', str(owner).encode())
        transaction.write(target, data)
    transaction.write(SYNC_CONFIG, (json.dumps({'owner_uid': owner, 'owner_name': pwd.getpwuid(owner).pw_name}, indent=2) + '\n').encode())
    transaction.write(SYNC_SYSUSERS, b'u velora-greeter-sync - "Velora login wallpaper" /var/lib/velora-greeter /usr/bin/nologin\n')
    transaction.write(SYNC_SYSTEM_WANTS, b'[Unit]\nWants=velora-greeter-wallpaper.socket\n')
    transaction.write(SYNC_USER_WANTS, b'[Unit]\nWants=velora-greeter-wallpaper.service\n')
    subprocess.run(['systemd-sysusers', str(SYNC_SYSUSERS)], check=True)
    subprocess.run(['systemctl', 'daemon-reload'], check=True)
    subprocess.run(['systemctl', 'restart', 'velora-greeter-wallpaper.socket', 'velora-greeter-wallpaper.service'], check=True)
    user_service(owner, 'restart')


def source_fingerprint(source):
    paths = [source / 'scripts/greeter.py', *(source / name for name in SYNC_FILES),
             *(source / 'resources/greeter' / name for name in ('extension.js', 'stylesheet.css', 'metadata.json', 'logo.svg')),
             *(source / 'dots/.config/quickshell/ii/assets/images' / name for name in ('autumn.jpg', 'autumn.NOTICE.md'))]
    digest = hashlib.sha256()
    for path in paths:
        digest.update(path.relative_to(source).as_posix().encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def is_current(source):
    """Read-only check, so an unchanged theme never needs administrator authorization."""
    try:
        receipt = json.loads((STATE / 'current.json').read_text())
        expected = {str(PROFILE), str(SETTINGS), *(str(path) for path in sync_paths()),
                    *(str(EXTENSION / name) for name in ('extension.js', 'stylesheet.css', 'metadata.json',
                                                        'logo.svg', 'autumn.jpg', 'autumn.NOTICE.md'))}
        return ((STATE / 'manifest.json').is_file()
                and receipt['source'] == source_fingerprint(source)
                and set(receipt['files']) == expected
                and all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
                        for path, digest in receipt['files'].items()))
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return False


def version():
    try:
        output = subprocess.check_output(['gnome-shell', '--version'], text=True)
        return re.search(r'\b\d+\.\d+(?:\.\d+)?', output).group(0)
    except (OSError, subprocess.CalledProcessError, AttributeError):
        return None


def status():
    current = version()
    return {'installed': (STATE / 'manifest.json').exists(), 'gnome': current,
            'supported': current in SUPPORTED, 'supported_versions': sorted(SUPPORTED),
            'extension': str(EXTENSION), 'backup': str(STATE),
            'effective_after': 'next GDM greeter start',
            'wallpaper_sync': {'installed': SYNC_CONFIG.is_file(),
                               'owner_uid': sync_owner() if SYNC_CONFIG.exists() else None,
                               'state': str(SYNC_STATE)}}


def atomic(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(data)
            output.flush()
            os.fchmod(output.fileno(), mode)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


class Transaction:
    def __init__(self):
        STATE.mkdir(parents=True, exist_ok=True)
        self.manifest = STATE / 'manifest.json'
        self.entries = json.loads(self.manifest.read_text()) if self.manifest.exists() else {}
        (STATE / 'original').mkdir(mode=0o700, exist_ok=True)

    def write(self, path, data):
        if path.is_symlink() or path.parent.resolve() != path.parent:
            raise ValueError(f'Refusing redirected system path: {path}')
        key = str(path)
        if key not in self.entries:
            original = STATE / 'original' / hashlib.sha256(key.encode()).hexdigest()
            if path.exists():
                shutil.copy2(path, original)
            self.entries[key] = str(original) if path.exists() else None
            atomic(self.manifest, (json.dumps(self.entries, indent=2) + '\n').encode())
        atomic(path, data)


def restore():
    (STATE / 'current.json').unlink(missing_ok=True)
    manifest = STATE / 'manifest.json'
    if not manifest.exists():
        return
    entries = json.loads(manifest.read_text())
    had_sync = str(SYNC_CONFIG) in entries
    if had_sync:
        if SYNC_CONFIG.exists():
            user_service(sync_owner(), 'stop')
        subprocess.run(['systemctl', 'stop', 'velora-greeter-wallpaper.socket', 'velora-greeter-wallpaper.service'], check=True)
    for name, original in reversed(list(entries.items())):
        path = Path(name)
        if path.is_symlink() or path.parent.resolve() != path.parent:
            raise ValueError(f'Refusing redirected system path: {path}')
        if original:
            backup = Path(original)
            atomic(path, backup.read_bytes(), backup.stat().st_mode & 0o777)
        else:
            path.unlink(missing_ok=True)
    subprocess.run(['dconf', 'update'], check=True)
    if had_sync:
        subprocess.run(['systemctl', 'daemon-reload'], check=True)
        # Only our fixed generated assets; never follow a state-directory symlink.
        if not SYNC_STATE.is_symlink() and SYNC_STATE.parent.resolve() == SYNC_STATE.parent and SYNC_STATE.exists():
            for path in SYNC_STATE.iterdir():
                if path.name == 'current.json' or re.fullmatch(r'wallpaper-[a-f0-9]{64}\.jpg', path.name) or path.name.startswith('.pending-'):
                    path.unlink(missing_ok=True)
    # Retain the original backup for inspection; subsequent opt-ins get a new baseline.
    os.replace(manifest, STATE / 'restored-manifest.json')


def enabled_extensions():
    account = next((name for name in ('gdm-greeter', 'gdm') if any(user.pw_name == name for user in pwd.getpwall())), None)
    # GDM 51 creates an ephemeral greeter account only while running. Before its first
    # start, there is no per-user database; read system defaults with a fresh HOME.
    prefix = ['runuser', '-u', account, '--'] if account else []
    with tempfile.TemporaryDirectory(prefix='velora-gdm-read-') as directory:
        # No shared root desktop settings when the ephemeral GDM account is absent.
        clean_home = [] if account else ['XDG_CONFIG_HOME=' + directory]
        result = subprocess.run([*prefix, 'env', 'GIO_USE_VFS=local', 'DCONF_PROFILE=gdm', *clean_home,
                                 'gsettings', 'get', 'org.gnome.shell', 'enabled-extensions'],
                                text=True, capture_output=True, check=True, timeout=10)
    value = ast.literal_eval(result.stdout.strip().removeprefix('@as '))
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError('Could not read the existing GDM extension list')
    return list(dict.fromkeys([*value, UUID]))


def apply(source, owner_uid=None):
    if version() not in SUPPORTED:
        print('This GNOME version is not verified; keeping the standard greeter.')
        return False
    if not Path('/usr/share/gdm').is_dir():
        raise ValueError('Install GDM before selecting the Velora login theme')
    extension = source / 'resources/greeter'
    wallpaper = source / 'dots/.config/quickshell/ii/assets/images/autumn.jpg'
    extensions = enabled_extensions()
    owner = sync_owner(owner_uid)
    transaction = Transaction()
    try:
        vendor_profile = Path('/usr/share/dconf/profile/gdm')
        profile = (PROFILE.read_text() if PROFILE.exists() else vendor_profile.read_text() if vendor_profile.exists()
                   else 'user-db:user\nfile-db:/usr/share/gdm/greeter-dconf-defaults\n')
        if 'system-db:gdm' not in profile.splitlines():
            lines = profile.splitlines()
            lines.insert(1, 'system-db:gdm')
            profile = '\n'.join(lines) + '\n'
        transaction.write(PROFILE, profile.encode())
        for name in ('extension.js', 'stylesheet.css', 'metadata.json', 'logo.svg'):
            transaction.write(EXTENSION / name, (extension / name).read_bytes())
        # A static blur costs nothing during login and needs no user home or GPU effect.
        from PIL import Image, ImageFilter, ImageEnhance
        import io
        with Image.open(wallpaper) as picture:
            picture.thumbnail((2560, 1600))
            picture = ImageEnhance.Brightness(picture.filter(ImageFilter.GaussianBlur(16))).enhance(0.54)
            output = io.BytesIO()
            picture.convert('RGB').save(output, format='JPEG', quality=90)
        transaction.write(EXTENSION / 'autumn.jpg', output.getvalue())
        notice = source / 'dots/.config/quickshell/ii/assets/images/autumn.NOTICE.md'
        transaction.write(EXTENSION / 'autumn.NOTICE.md', notice.read_bytes())
        settings = "[org/gnome/shell]\nenabled-extensions=" + repr(extensions) + "\ndisable-user-extensions=false\n"
        transaction.write(SETTINGS, settings.encode())
        subprocess.run(['dconf', 'update'], check=True)
        install_sync(transaction, source, owner)
        receipt = {'source': source_fingerprint(source),
                   'files': {name: hashlib.sha256(Path(name).read_bytes()).hexdigest()
                             for name in transaction.entries}}
        atomic(STATE / 'current.json', (json.dumps(receipt, indent=2) + '\n').encode())
    except BaseException:
        restore()
        raise
    print('Velora login theme and automatic wallpaper sync installed. Theme applies on the next GDM start. Restore: velora greeter restore')
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('status', 'apply', 'restore'))
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--owner-uid', type=int, default=int(os.environ.get('SUDO_UID', '0')))
    args = parser.parse_args()
    if args.action == 'status':
        print(json.dumps(status(), indent=2))
        return
    if os.geteuid() != 0:
        parser.error('System theme changes require root; use velora install --login-theme velora or velora greeter restore')
    if args.action == 'apply':
        apply(args.source, args.owner_uid)
    else:
        restore()
        print('Previous GDM configuration restored. Changes apply on the next greeter start.')


if __name__ == '__main__':
    main()
