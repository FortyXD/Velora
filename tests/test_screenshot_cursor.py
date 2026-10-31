"""Screenshot cursor preference: capture arguments, cancellation, QML and persistence."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
CAPTURE = SHELL / 'scripts/images/screenshot.sh'
QS = shutil.which('qs') or shutil.which('quickshell')


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


@unittest.skipUnless(shutil.which('jq'), 'jq is not installed')
class ScreenshotCursorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="velora capture ' ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'config/illogical-impulse/config.json'
        self.env = {**os.environ, 'XDG_CONFIG_HOME': str(self.root / 'config'),
                    'XDG_RUNTIME_DIR': str(self.root), 'CAPTURE_TEST_ROOT': str(self.root),
                    'PATH': str(self.root / 'bin') + os.pathsep + os.environ['PATH']}
        self.env.pop('VELORA_SCREENSHOT_CURSOR', None)
        self.env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        write(self.root / 'bin/grim', '''#!/usr/bin/env python3
import json,os,pathlib,sys,time
root=pathlib.Path(os.environ['CAPTURE_TEST_ROOT'])
if os.environ.get('CAPTURE_TEST_CHECK_FDS'):
 for fd in pathlib.Path('/proc/self/fd').iterdir():
  try: target=os.readlink(fd)
  except FileNotFoundError: continue
  if target.endswith('velora-screenshot-cursor.lock'): sys.exit(8)
with (root/'grim.jsonl').open('a') as log: log.write(json.dumps(sys.argv[1:])+'\\n')
if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')=='test':
 ident=os.environ.get('CAPTURE_TEST_ID','capture')
 with (root/'capture-modes.jsonl').open('a') as log: log.write(json.dumps({'id':ident,'mode':(root/'cursor-mode').read_text()})+'\\n')
 (root/('started-'+ident)).touch()
 time.sleep(float(os.environ.get('CAPTURE_TEST_DELAY','0')))
if os.environ.get('CAPTURE_TEST_FAIL'): sys.exit(7)
if sys.argv[-1]=='-': sys.stdout.buffer.write(b'PNG fixture')
else: pathlib.Path(sys.argv[-1]).write_bytes(b'PNG fixture')
''')
        write(self.root / 'bin/wl-copy', '''#!/usr/bin/env python3
import os,pathlib,sys
if os.environ.get('CAPTURE_TEST_CHECK_FDS'):
 for fd in pathlib.Path('/proc/self/fd').iterdir():
  try: target=os.readlink(fd)
  except FileNotFoundError: continue
  if target.endswith('velora-screenshot-cursor.lock'): sys.exit(8)
pathlib.Path(os.environ['CAPTURE_TEST_ROOT'],'clipboard').write_bytes(sys.stdin.buffer.read())
''')
        write(self.root / 'bin/slurp', '''#!/usr/bin/env python3
import os,sys
if os.environ.get('CAPTURE_TEST_CANCEL'): sys.exit(130)
print(os.environ.get('CAPTURE_TEST_REGION','10,20 30x40'))
''')
        write(self.root / 'bin/hyprctl', '''#!/usr/bin/env python3
import json,os,pathlib,re,sys
root=pathlib.Path(os.environ['CAPTURE_TEST_ROOT'])
assert os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')=='test'
if sys.argv[1]=='getoption': print(json.dumps({'int':int((root/'cursor-mode').read_text())}))
else:
 mode=re.search(r'no_hardware_cursors=(\\d+)',sys.argv[2]).group(1)
 (root/'cursor-mode').write_text(mode)
 with (root/'cursor-events').open('a') as log: log.write(mode+'\\n')
 print('ok')
''')
        for path in (self.root / 'bin').iterdir():
            path.chmod(0o755)

    def capture(self, *args, env=None):
        return subprocess.run(['bash', str(CAPTURE), *args], env={**self.env, **(env or {})},
                              capture_output=True, timeout=10)

    def calls(self):
        path = self.root / 'grim.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_config_preference_is_strict_boolean_and_backwards_compatible(self):
        for value in (None, False, True, 'true', 1):
            with self.subTest(value=value):
                write(self.config, json.dumps({'screenSnip': {} if value is None else {'showCursor': value}}))
                result = self.capture('-o', 'HDMI-A-1', '-')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.calls()[-1], (['-c'] if value is True else []) + ['-o', 'HDMI-A-1', '-'])
                self.assertEqual(result.stdout, b'PNG fixture')

    def test_missing_or_invalid_config_keeps_cursor_hidden(self):
        for contents in (None, '{broken', '[]'):
            with self.subTest(contents=contents):
                if contents is not None:
                    write(self.config, contents)
                result = self.capture('-')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.calls()[-1], ['-'])

    def test_runtime_override_and_argument_safety(self):
        output = self.root / "screen ' ; $HOME.png"
        for saved, override in ((False, 'true'), (True, 'false')):
            with self.subTest(override=override):
                write(self.config, json.dumps({'screenSnip': {'showCursor': saved}}))
                result = self.capture('-o', "monitor ' ; $HOME", str(output), env={'VELORA_SCREENSHOT_CURSOR': override})
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = (['-c'] if override == 'true' else []) + ['-o', "monitor ' ; $HOME", str(output)]
                self.assertEqual(self.calls()[-1], expected)
                self.assertEqual(output.read_bytes(), b'PNG fixture')
        count = len(self.calls())
        result = self.capture('-', env={'VELORA_SCREENSHOT_CURSOR': 'not-a-boolean'})
        self.assertEqual(result.returncode, 2)
        self.assertEqual(len(self.calls()), count)

    def test_shell_off_region_capture_and_private_temp_cleanup(self):
        for enabled in (False, True):
            with self.subTest(enabled=enabled):
                write(self.config, json.dumps({'screenSnip': {'showCursor': enabled}}))
                result = self.capture('--select-region')
                self.assertEqual(result.returncode, 0, result.stderr)
                args = self.calls()[-1]
                self.assertEqual(args[:-1], (['-c'] if enabled else []) + ['-g', '10,20 30x40'])
                self.assertEqual((self.root / 'clipboard').read_bytes(), b'PNG fixture')
                self.assertFalse(Path(args[-1]).exists())
                self.assertFalse(list(self.root.glob('velora-screenshot.*')))

    def test_cancel_or_capture_failure_does_not_replace_clipboard(self):
        for env in ({'CAPTURE_TEST_CANCEL': '1'}, {'CAPTURE_TEST_REGION': ''}, {'CAPTURE_TEST_FAIL': '1'}):
            with self.subTest(env=env):
                (self.root / 'clipboard').write_bytes(b'previous clipboard')
                result = self.capture('--select-region', env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((self.root / 'clipboard').read_bytes(), b'previous clipboard')
                self.assertFalse(list(self.root.glob('velora-screenshot.*')))
        self.assertEqual(self.capture('-', env={'CAPTURE_TEST_FAIL': '1'}).returncode, 7)

    def test_full_capture_failure_preserves_clipboard(self):
        (self.root / 'clipboard').write_bytes(b'previous clipboard')
        result = self.capture('--clipboard', '-o', 'HDMI-A-1', env={'CAPTURE_TEST_FAIL': '1'})
        self.assertEqual(result.returncode, 7)
        self.assertEqual((self.root / 'clipboard').read_bytes(), b'previous clipboard')
        self.assertFalse(list(self.root.glob('velora-screenshot.*')))
        result = self.capture('--clipboard', '-o', 'HDMI-A-1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'clipboard').read_bytes(), b'PNG fixture')

    @unittest.skipUnless(shutil.which('flock'), 'flock is not installed')
    def test_software_cursor_override_is_restored_after_success_and_failure(self):
        for mode, show, fail in ((1, False, False), (2, False, False), (0, False, False),
                                 (1, True, False), (1, False, True)):
            with self.subTest(mode=mode, show=show, fail=fail):
                (self.root / 'cursor-mode').write_text(str(mode))
                (self.root / 'cursor-events').unlink(missing_ok=True)
                env = {'HYPRLAND_INSTANCE_SIGNATURE': 'test', 'VELORA_SCREENSHOT_CURSOR': str(show).lower()}
                if fail:
                    env['CAPTURE_TEST_FAIL'] = '1'
                result = self.capture('-', env=env)
                self.assertEqual(result.returncode, 7 if fail else 0, result.stderr)
                self.assertEqual((self.root / 'cursor-mode').read_text(), str(mode))
                events = self.root / 'cursor-events'
                actual = events.read_text().splitlines() if events.exists() else []
                self.assertEqual(actual, ['0', str(mode)] if mode > 0 and not show else [])

    @unittest.skipUnless(shutil.which('flock'), 'flock is not installed')
    def test_temp_cleanup_failure_cannot_skip_cursor_restoration(self):
        (self.root / 'cursor-mode').write_text('1')
        write(self.root / 'bin/rm', '#!/bin/sh\nexit 9\n')
        (self.root / 'bin/rm').chmod(0o755)
        result = self.capture('--clipboard', env={'HYPRLAND_INSTANCE_SIGNATURE': 'test',
                                                'VELORA_SCREENSHOT_CURSOR': 'false'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'cursor-mode').read_text(), '1')
        self.assertEqual((self.root / 'clipboard').read_bytes(), b'PNG fixture')

    @unittest.skipUnless(shutil.which('flock'), 'flock is not installed')
    def test_capture_and_clipboard_tools_cannot_inherit_cursor_lock(self):
        (self.root / 'cursor-mode').write_text('1')
        result = self.capture('--clipboard', env={'HYPRLAND_INSTANCE_SIGNATURE': 'test',
                                                'VELORA_SCREENSHOT_CURSOR': 'false',
                                                'CAPTURE_TEST_CHECK_FDS': '1'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'cursor-mode').read_text(), '1')
        self.assertEqual((self.root / 'clipboard').read_bytes(), b'PNG fixture')

    def wait_for_capture(self, ident, process):
        deadline = time.monotonic() + 5
        while not (self.root / ('started-' + ident)).exists():
            self.assertIsNone(process.poll(), 'Capture exited before grim started')
            self.assertLess(time.monotonic(), deadline, 'Capture did not start')
            time.sleep(0.01)

    def start_capture(self, ident, show):
        return subprocess.Popen(['bash', str(CAPTURE), '-'], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True, env={**self.env, 'HYPRLAND_INSTANCE_SIGNATURE': 'test',
                                'VELORA_SCREENSHOT_CURSOR': str(show).lower(), 'CAPTURE_TEST_ID': ident,
                                'CAPTURE_TEST_DELAY': '0.2'})

    @unittest.skipUnless(shutil.which('flock'), 'flock is not installed')
    def test_simultaneous_capture_waits_for_cursor_restoration(self):
        (self.root / 'cursor-mode').write_text('1')
        hidden = self.start_capture('hidden', False)
        self.addCleanup(lambda: hidden.poll() is None and hidden.kill())
        self.wait_for_capture('hidden', hidden)
        shown = self.start_capture('shown', True)
        self.addCleanup(lambda: shown.poll() is None and shown.kill())
        for process in (hidden, shown):
            out, err = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, err)
        modes = [json.loads(line) for line in (self.root / 'capture-modes.jsonl').read_text().splitlines()]
        self.assertEqual(modes, [{'id': 'hidden', 'mode': '0'}, {'id': 'shown', 'mode': '1'}])
        self.assertEqual((self.root / 'cursor-mode').read_text(), '1')

    @unittest.skipUnless(shutil.which('flock'), 'flock is not installed')
    def test_termination_restores_cursor_mode(self):
        (self.root / 'cursor-mode').write_text('1')
        process = self.start_capture('terminated', False)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        self.wait_for_capture('terminated', process)
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate(timeout=10)
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual((self.root / 'cursor-mode').read_text(), '1')

    def run_qml(self, root, source):
        write(root / 'shell.qml', source)
        result = subprocess.run([QS, '-p', str(root), '--no-color'],
                                env={**self.env, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software'},
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('CURSOR_TEST_PASS', output)
        for error in ('TypeError', 'ReferenceError', 'CURSOR_TEST_FAIL', 'Failed to load configuration'):
            self.assertNotIn(error, output)

    @unittest.skipUnless(QS, 'Quickshell is not installed')
    def test_production_temp_capture_passes_live_preference(self):
        root = self.root / 'qml'
        root.mkdir()
        shutil.copy2(SHELL / 'modules/common/utils/TempScreenshotProcess.qml', root)
        write(root / 'modules/common/Directories.qml', 'pragma Singleton\nimport Quickshell\nSingleton { property string scriptPath: '
              + json.dumps(str(SHELL / 'scripts')) + '; property string screenshotTemp: '
              + json.dumps(str(self.root / "snap ' shots")) + ' }')
        functions = root / 'modules/common/functions'
        functions.mkdir(parents=True)
        shutil.copy2(SHELL / 'modules/common/functions/StringUtils.qml', functions)
        self.run_qml(root, '''import QtQuick
import Quickshell
ShellRoot {
 id: root
 property bool cursor: false
 TempScreenshotProcess {
  id: capture
  running: false
  screen: Quickshell.screens[0]
  includeCursor: root.cursor
  onExited: (code, status) => {
   if (code !== 0) { console.error("CURSOR_TEST_FAIL", code); Qt.exit(2); return; }
   if (!root.cursor) { root.cursor = true; Qt.callLater(() => capture.running = true); }
   else { console.log("CURSOR_TEST_PASS"); Qt.quit(); }
  }
 }
 Component.onCompleted: capture.running = true
}
''')
        calls = self.calls()
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][0], '-o')
        self.assertEqual(calls[1], ['-c', *calls[0]])
        self.assertTrue(calls[0][-1].startswith(str(self.root / "snap ' shots")))

    @unittest.skipUnless(QS, 'Quickshell is not installed')
    def test_production_setting_persists_without_affecting_video_options(self):
        root = self.root / 'qml'
        write(root / 'modules/common/Directories.qml', 'pragma Singleton\nimport Quickshell\nSingleton { property string shellConfigPath: '
              + json.dumps(str(self.config)) + ' }')
        shutil.copy2(SHELL / 'modules/common/Config.qml', root / 'modules/common/Config.qml')
        write(root / 'modules/common/Appearance.qml', 'pragma Singleton\nimport Quickshell\nSingleton { property var font: ({pixelSize:{smaller:12}}) }')
        write(root / 'modules/common/functions/FileUtils.qml', 'pragma Singleton\nimport Quickshell\nSingleton {}')
        write(root / 'services/Translation.qml', 'pragma Singleton\nimport Quickshell\nSingleton { function tr(s) { return s; } }')
        # The production switch block owns the binding/write behavior; the visual
        # control is isolated from the theme and rendered page for this test.
        write(root / 'ConfigSwitch.qml', '''import QtQuick
Item { property string buttonIcon; property string text; property string description
 property bool autoToggle; property bool checked; signal clicked() }
''')
        source = (SHELL / 'modules/settings/ToolsConfig.qml').read_text()
        switch = source.split('objectName: "screenshotShowCursor"', 1)[1].split('\n        }', 1)[0]
        write(self.config, json.dumps({'screenSnip': {'savePath': '/tmp/keep-screenshots'}, 'screenRecord': {'audio': 'silent'}}))
        qml = '''import QtQuick
import Quickshell
import qs.modules.common
import qs.services
ShellRoot {
 id: root
 property int phase: 0
 ConfigSwitch { id: row
''' + switch + '''
 }
 function check(ok) { if (!ok) { console.error("CURSOR_TEST_FAIL"); Qt.exit(2); } }
 Timer { interval: 100; repeat: true; running: Config.ready
  onTriggered: {
   phase++;
   if (phase === 1) { root.check(!row.checked); row.clicked(); }
   if (phase === 2) { root.check(row.checked && Config.options.screenSnip.showCursor); row.clicked(); }
   if (phase === 3) { root.check(!row.checked && !Config.options.screenSnip.showCursor); row.clicked(); }
   if (phase === 5) { console.log("CURSOR_TEST_PASS"); Qt.quit(); }
  }
 }
}
'''
        self.run_qml(root, qml)
        saved = json.loads(self.config.read_text())
        self.assertTrue(saved['screenSnip']['showCursor'])
        self.assertEqual(saved['screenSnip']['savePath'], '/tmp/keep-screenshots')
        self.assertEqual(saved['screenRecord']['audio'], 'silent')
        # A second process loads the saved preference rather than the default.
        self.run_qml(root, '''import QtQuick
import Quickshell
import qs.modules.common
ShellRoot { Timer { interval: 100; running: Config.ready; onTriggered: {
 console.log(Config.options.screenSnip.showCursor ? "CURSOR_TEST_PASS" : "CURSOR_TEST_FAIL"); Qt.quit();
} } }
''')

    @unittest.skipUnless(shutil.which('lua'), 'Lua is not installed')
    def test_custom_shell_config_name_is_expanded_in_shortcuts(self):
        source = (PROJECT / 'dots/.config/hypr/hyprland/keybinds.lua').read_text()
        command = source.split('local screenshot = [=[', 1)[1].split(']=]', 1)[0]
        helper = PROJECT / 'dots/.config/hypr/hyprland/helpers.lua'
        script = 'package.preload["custom.variables"] = function() return {qsConfig="custom-shell"} end\n'
        script += 'local helpers = dofile(' + json.dumps(str(helper)) + ')\n'
        script += 'print(helpers.expand(' + json.dumps(command) + '))\n'
        result = subprocess.run(['lua', '-'], input=script, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('/quickshell/custom-shell/scripts/images/screenshot.sh', result.stdout)
        self.assertNotIn('$qsConfig', result.stdout)

    def test_capture_entrypoints_and_defaults(self):
        options = json.loads((PROJECT / 'dots/.config/illogical-impulse/config.example.json').read_text())
        self.assertIs(options['screenSnip']['showCursor'], False)
        for name in ('modules/ii/regionSelector/RegionSelection.qml', 'modules/waffle/screenSnip/WRegionSelectionPanel.qml'):
            self.assertIn('includeCursor: Config.options.screenSnip.showCursor', (SHELL / name).read_text())
        self.assertIn('property bool includeCursor: false', (SHELL / 'modules/common/utils/TempScreenshotProcess.qml').read_text())
        overlay = (SHELL / 'modules/ii/overlay/recorder/Recorder.qml').read_text()
        self.assertIn('VELORA_SCREENSHOT_CURSOR=${Config.options.screenSnip.showCursor}', overlay)
        self.assertIn('scripts/images/screenshot.sh', overlay)
        bindings = (PROJECT / 'dots/.config/hypr/hyprland/keybinds.lua').read_text()
        self.assertIn('scripts/images/screenshot.sh', bindings)
        self.assertEqual(bindings.count('exec(screenshot ..'), 2)
        self.assertIn('.. screenshot ..', bindings)
        translations = json.loads((SHELL / 'translations/ru_RU.json').read_text())
        self.assertEqual(translations['Show cursor in screenshots'], 'Показывать курсор на скриншотах')


if __name__ == '__main__':
    unittest.main()
