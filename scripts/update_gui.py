"""A user service keeps a graphical update alive when Settings is closed."""
import argparse
from collections import deque
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

UNIT = 'velora-update-install.service'
ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')


def directory():
    return Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'velora'


def write_status(value):
    directory().mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=directory(), delete=False) as output:
        json.dump(dict(value, updated_at=time.time()), output)
        output.flush()
        os.replace(output.name, directory() / 'gui-update.json')


def active():
    return subprocess.run(['systemctl', '--user', 'is-active', '--quiet', UNIT],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def status():
    try:
        value = json.loads((directory() / 'gui-update.json').read_text())
    except (OSError, ValueError):
        return {}
    if value.get('status') in ('starting', 'running') and time.time() - value.get('updated_at', 0) > 10 and not active():
        value.update(status='failed', error='The update was interrupted. You can retry it.')
        write_status(value)
    return value


def start(binary):
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', ''))
    if not runtime.is_absolute() or runtime.stat().st_uid != os.getuid():
        raise ValueError('Open Software Update from your desktop session.')
    with (runtime / 'velora-update-launch.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if active():
            return
        subprocess.run(['systemctl', '--user', 'reset-failed', UNIT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        write_status({'status': 'starting', 'phase': 'checking', 'tail': []})
        command = ['systemd-run', '--user', '--collect', '--quiet', '--service-type=exec', '--unit=' + UNIT]
        for name in ('WAYLAND_DISPLAY', 'DISPLAY', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS',
                     'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP', 'QT_QPA_PLATFORM',
                     'QT_QPA_PLATFORMTHEME', 'QT_PLUGIN_PATH', 'QT_QPA_GENERIC_PLUGINS',
                     'XDG_STATE_HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME'):
            if name in os.environ:
                command.append('--setenv=' + name + '=' + os.environ[name])
        command += ['/usr/bin/python3', str(Path(__file__).resolve()), '--worker', str(binary)]
        result = subprocess.run(command, text=True, capture_output=True)
        if result.returncode:
            write_status({'status': 'failed', 'error': result.stderr.strip() or 'Could not start the update.'})
            raise ValueError('Could not start the background update: ' + result.stderr.strip())


def show_progress():
    page = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'quickshell/user/settings_page.txt'
    page.parent.mkdir(parents=True, exist_ok=True)
    page.write_text('updates')
    shell = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'quickshell/ii/settings.qml'
    subprocess.Popen(['qs', '-p', str(shell)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def worker(binary):
    value = {'status': 'running', 'phase': 'checking', 'tail': []}
    tail = deque(maxlen=12)
    write_status(value)
    try:
        runtime = os.environ.get('XDG_RUNTIME_DIR')
        # Only this operation gets the wrapper. No password is stored or cached by Velora.
        with tempfile.TemporaryDirectory(prefix='velora-update-', dir=runtime) as temporary:
            folder = Path(temporary)
            sudo = folder / 'sudo'
            sudo.write_text('#!/bin/sh\nexec /usr/bin/sudo -A "$@"\n')
            sudo.chmod(0o700)
            askpass = folder / 'askpass'
            askpass.write_text('#!/bin/sh\nprintf "::velora-phase authorizing\\n" >&2\n'
                              'exec /usr/bin/kdialog --title "Velora update" --password '
                              '"Administrator authorization is needed to install system changes. Your password is not saved by Velora."\n')
            askpass.chmod(0o700)
            environment = dict(os.environ, VELORA_GUI_UPDATE='1', SUDO_ASKPASS=str(askpass), GIT_TERMINAL_PROMPT='0',
                               PATH=str(folder) + ':/usr/local/bin:/usr/bin:/bin', PYTHONUNBUFFERED='1')
            log_path = directory() / 'gui-update.log'
            with os.fdopen(os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as log:
                process = subprocess.Popen([str(binary), 'update'], env=environment, stdin=subprocess.DEVNULL,
                                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors='replace')
                for raw in process.stdout:
                    log.write(raw)
                    log.flush()
                    line = ANSI.sub('', raw.rstrip().split('\r')[-1])
                    if line.startswith('::velora-phase '):
                        value['phase'] = line.split(' ', 1)[1]
                    elif line:
                        tail.append(line[-1000:])
                    value['tail'] = list(tail)
                    write_status(value)
                result = process.wait()
                process.stdout.close()
            value.update(status='succeeded' if result == 0 else 'failed', exit_code=result,
                         log=str(log_path), error='' if result == 0 else 'The update did not finish. You can retry it.')
    except (OSError, ValueError) as error:
        value.update(status='failed', error=str(error))
    write_status(value)
    return 0 if value['status'] == 'succeeded' else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--worker', required=True, type=Path)
    raise SystemExit(worker(parser.parse_args().worker))
