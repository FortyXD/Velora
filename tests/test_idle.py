"""Exercise keep-awake restoration and helper lifetime in a private Quickshell."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

from test_power_ui import isolated_env, write

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
QS = shutil.which('qs') or shutil.which('quickshell')


@unittest.skipUnless(QS, 'Quickshell unavailable')
class IdleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='velora-idle-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.env = isolated_env(self.root)
        self.env['QS_NO_RELOAD_POPUP'] = '1'
        self.env['HYPRLAND_INSTANCE_SIGNATURE'] = 'test-session'
        self.env['PATH'] = str(self.root / 'bin') + os.pathsep + os.environ['PATH']
        self.process = None
        self.log = (self.root / 'shell.log').open('w+')
        self.addCleanup(self.log.close)
        self.addCleanup(self.stop)
        write(self.root, 'services/qmldir', 'module qs.services\nsingleton Idle 1.0 Idle.qml\n')
        shutil.copy2(SHELL / 'services/Idle.qml', self.root / 'services/Idle.qml')
        write(self.root, 'modules/common/qmldir', 'module qs.modules.common\nsingleton Persistent 1.0 Persistent.qml\nsingleton Directories 1.0 Directories.qml\n')
        shutil.copy2(SHELL / 'modules/common/Persistent.qml', self.root / 'modules/common/Persistent.qml')
        write(self.root, 'modules/common/Directories.qml', 'pragma Singleton\nimport QtQuick\nQtObject { property string state: ' + json.dumps(str(self.root / 'state')) + ' }\n')
        # Replace only the OS boundary. The real QML Process, pipes and readiness
        # acknowledgement still run; no test acquires an inhibitor on the host.
        write(self.root, 'bin/systemd-inhibit', '''#!/usr/bin/python3
import json, os, pathlib, sys
root = pathlib.Path(__file__).resolve().parents[1]
assert '--what=idle' in sys.argv and '--mode=block' in sys.argv
with (root / 'starts.jsonl').open('a') as log:
    log.write(json.dumps({'pid': os.getpid(), 'args': sys.argv[1:]}) + '\\n')
if (root / 'fail-once').exists():
    (root / 'fail-once').unlink()
    sys.exit(1)
command = sys.argv[sys.argv.index('--') + 1:]
os.execvp(command[0], command)
''')
        (self.root / 'bin/systemd-inhibit').chmod(0o755)

    def start(self, *, saved=True, previous='test-session', delay=0, owner=True, pending=False):
        if not (self.root / 'state/states.json').exists():
            write(self.root, 'state/states.json', json.dumps({
                'idle': {'inhibit': saved}, 'hyprlandInstanceSignature': previous}))
        if pending:
            write(self.root, 'modules/common/Persistent.qml', '''pragma Singleton
import QtQuick
QtObject {
 property bool ready: false
 property bool isNewHyprlandInstance: false
 property QtObject states: QtObject { property QtObject idle: QtObject { property bool inhibit: false } }
}'''.replace('property bool inhibit: false', 'property bool inhibit: ' + str(saved).lower()))
        write(self.root, 'shell.qml', '''import QtQuick
import Quickshell
import Quickshell.Io
import "modules/common"
import "services"
ShellRoot {
 property var storage: Persistent
 Timer { interval: DELAY; running: OWNER; onTriggered: Idle.load() }
 IpcHandler {
  target: "test"
  function status(): string {
   return JSON.stringify({requested: Idle.inhibit, active: Idle.active,
       restored: Idle.restored, ready: Persistent.ready, saved: Persistent.states.idle.inhibit});
  }
  function set(enabled: bool): void { Idle.toggleInhibit(enabled); }
  function rapidToggle(): void { Idle.toggleInhibit(false); Idle.toggleInhibit(true); }
  function ready(): void { Persistent.ready = true; }
  function reload(): void { Quickshell.reload(false); }
 }
}'''.replace('DELAY', str(max(1, delay))).replace('OWNER', str(owner).lower()))
        self.process = subprocess.Popen([QS, '-p', str(self.root)], env=self.env,
                                        stdout=self.log, stderr=subprocess.STDOUT)
        self.wait_for(lambda: self.status() is not None)

    def stop(self):
        if self.process is not None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
            self.process = None

    def ipc(self, method, *args):
        return subprocess.run([QS, '-p', str(self.root), 'ipc', 'call', 'test', method, *args],
                              env=self.env, capture_output=True, text=True, timeout=5)

    def status(self):
        result = self.ipc('status')
        if result.returncode or not result.stdout.strip() or result.stdout.strip() == 'Not ready to accept queries yet.':
            return None
        return json.loads(result.stdout)

    def wait_for(self, predicate, timeout=6):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            if self.process is not None and self.process.poll() is not None:
                break
            time.sleep(0.04)
        self.log.flush()
        self.fail('Condition timed out:\n' + (self.root / 'shell.log').read_text())

    def is_active(self):
        return (self.status() or {}).get('active') is True

    def starts(self):
        path = self.root / 'starts.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def saved(self):
        return json.loads((self.root / 'state/states.json').read_text())['idle']['inhibit']

    @staticmethod
    def alive(pid):
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    def test_restore_when_storage_is_already_ready(self):
        self.start(delay=300)
        self.wait_for(self.is_active)
        self.assertTrue(self.status()['requested'])
        self.assertEqual(len(self.starts()), 1)

    def test_toggle_persists_across_shell_restart(self):
        self.start(saved=False)
        self.wait_for(lambda: self.status()['restored'])
        self.assertFalse(self.is_active())
        self.assertEqual(self.ipc('set', 'true').returncode, 0)
        self.wait_for(self.is_active)
        self.wait_for(self.saved)
        pid = self.starts()[-1]['pid']
        self.stop()
        self.wait_for(lambda: not self.alive(pid))
        self.start()
        self.wait_for(self.is_active)
        self.assertEqual(self.ipc('set', 'false').returncode, 0)
        self.wait_for(lambda: not self.saved())
        self.wait_for(lambda: all(not self.alive(s['pid']) for s in self.starts()))
        self.stop()
        self.start()
        self.wait_for(lambda: self.status()['restored'])
        self.assertFalse(self.is_active())
        self.assertEqual(len(self.starts()), 2)

    def test_new_compositor_session_resets_the_choice(self):
        self.start(previous='previous-session')
        self.wait_for(lambda: self.status()['restored'])
        self.assertFalse(self.status()['requested'])
        self.wait_for(lambda: not self.saved())
        self.assertEqual(self.starts(), [])

    def test_shell_reload_restores_without_leaking_a_helper(self):
        self.start()
        self.wait_for(self.is_active)
        pid = self.starts()[-1]['pid']
        self.assertEqual(self.ipc('reload').returncode, 0)
        self.wait_for(lambda: len(self.starts()) == 2 and self.is_active())
        self.wait_for(lambda: not self.alive(pid))
        self.assertTrue(self.status()['requested'])

    def test_preview_does_not_inhibit_or_overwrite_state(self):
        self.start(owner=False)
        self.wait_for(lambda: self.status()['ready'])
        self.assertFalse(self.is_active())
        self.assertTrue(self.saved())
        self.assertEqual(self.starts(), [])

    def test_restore_after_delayed_storage_load(self):
        self.start(pending=True)
        self.assertFalse(self.status()['restored'])
        self.ipc('ready')
        self.wait_for(lambda: self.status()['restored'])
        self.wait_for(self.is_active)
        self.assertTrue(self.status()['requested'])

    def test_click_before_storage_ready_wins(self):
        self.start(pending=True, saved=False)
        self.ipc('set', 'true')
        self.wait_for(self.is_active)
        self.ipc('ready')
        self.wait_for(lambda: self.status()['restored'])
        self.assertTrue(self.status()['requested'])
        self.assertTrue(self.status()['saved'])

    def test_failed_acquisition_and_helper_crash_retry(self):
        (self.root / 'fail-once').touch()
        self.start()
        self.wait_for(lambda: len(self.starts()) == 1)
        self.assertTrue(self.status()['requested'])
        self.assertFalse(self.is_active())
        self.wait_for(self.is_active)
        self.assertEqual(len(self.starts()), 2)
        os.kill(self.starts()[-1]['pid'], signal.SIGKILL)
        self.wait_for(lambda: not self.is_active())
        self.assertTrue(self.status()['requested'])
        self.wait_for(self.is_active)
        self.assertEqual(len(self.starts()), 3)

    def test_quick_off_on_waits_for_the_previous_helper(self):
        self.start()
        self.wait_for(self.is_active)
        pid = self.starts()[-1]['pid']
        self.ipc('rapidToggle')
        self.wait_for(lambda: len(self.starts()) == 2 and self.is_active())
        self.assertFalse(self.alive(pid))
        self.assertTrue(self.status()['requested'])


if __name__ == '__main__':
    unittest.main()
