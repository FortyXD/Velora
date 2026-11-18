"""Free windows (hyprland/modes/floating.lua) and the mode switch, run against a stand-in for Hyprland."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import test_connectivity_qml as qml
import test_connectivity_pages as pages

PROJECT = Path(__file__).resolve().parents[1]
HYPR = PROJECT / 'dots/.config/hypr'
LUA = shutil.which('lua5.4') or shutil.which('lua')


@unittest.skipUnless(LUA, 'Lua 5.4 is not installed')
class WindowModeTests(unittest.TestCase):
    def lua(self, script=None, env=None, code=None):
        command = [LUA, '-e', f'package.path="{HYPR}/?.lua;"..package.path']
        command += ['-e', code] if code else [script]
        return subprocess.run(command, env={**os.environ, **(env or {})}, capture_output=True, text=True, timeout=20)

    def test_free_windows_snap_minimize_and_remember(self):
        with tempfile.TemporaryDirectory(prefix='velora-free-') as state:
            result = self.lua(str(PROJECT / 'tests/lua/floating_spec.lua'), {'VELORA_TEST_STATE': state})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_gestures_keep_the_old_ones_and_follow_overrides(self):
        with tempfile.TemporaryDirectory(prefix='velora-gestures-') as runtime:
            result = self.lua(str(PROJECT / 'tests/lua/gestures_spec.lua'), {'VELORA_TEST_STATE': runtime})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_mode_comes_from_the_settings_file(self):
        with tempfile.TemporaryDirectory(prefix='velora-mode-') as config:
            custom = Path(config) / 'hypr/custom'
            custom.mkdir(parents=True)
            probe = 'print(require("hyprland.window_mode").current())'
            self.assertEqual(self.lua(env={'XDG_CONFIG_HOME': config}, code=probe).stdout.strip(), 'tiling')
            (custom / 'shell_settings.json').write_text(json.dumps({'general:layout': 'dwindle', 'shell:windowMode': 'floating'}, indent=4))
            self.assertEqual(self.lua(env={'XDG_CONFIG_HOME': config}, code=probe).stdout.strip(), 'floating')
            (custom / 'shell_settings.json').write_text(json.dumps({'shell:windowMode': 'canvas'}))
            self.assertEqual(self.lua(env={'XDG_CONFIG_HOME': config}, code=probe).stdout.strip(), 'canvas')
            (custom / 'shell_settings.json').write_text(json.dumps({'shell:windowMode': 'tiling'}))
            self.assertEqual(self.lua(env={'XDG_CONFIG_HOME': config}, code=probe).stdout.strip(), 'tiling')


@unittest.skipUnless(qml.QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
class GestureMotionTests(unittest.TestCase):
    def test_interactive_panels(self):
        with tempfile.TemporaryDirectory(prefix='velora-gesture-motion-') as directory:
            root = Path(directory)
            qml.write_common(root)
            qml.write_singletons(root, {
                'Appearance': 'property bool animate: true; function scaledDuration(ms) { return animate ? Math.round(ms) : 0; }',
                'Hyprland': 'signal rawEvent(var event); signal focusedWorkspaceChanged(); '
                            'property var commands: []; function dispatch(command) { commands = commands.concat([command]); }',
                'GlobalStates': 'property bool overviewOpen: false; property bool appLibraryOpen: false',
                'FreeWindows': 'property int calls: 0; function showDesktop() { calls++; }',
            })
            (root / 'GestureReveal.qml').write_text(qml.production('services/GestureReveal.qml'))
            (root / 'TouchpadGestures.qml').write_text(qml.production('services/TouchpadGestures.qml'))
            with (root / 'qmldir').open('a') as stream:
                stream.write('singleton TouchpadGestures 1.0 TouchpadGestures.qml\n')
            qml.ConnectivityQmlTests().run_tests(root, 'tst_touchpad_gestures.qml')


@unittest.skipUnless(pages.QS and pages.CARGO and pages.DBUS, 'needs the isolated Quickshell runtime')
class DesktopChooserTests(unittest.TestCase):
    def test_windows_and_desktop_destinations(self):
        pages.SettingsPagesTests.setUpClass()
        driver = (PROJECT / 'tests/qml/TaskViewChooserFixture.qml').read_text()
        output = pages.SettingsPagesTests().run_driver(driver, service_overrides={
            'HyprlandData.qml': '''pragma Singleton
import Quickshell
Singleton {
    property var workspaceIds: [1, 2, 4]
    property var windowByAddress: ({ "0xabc": { workspace: {id: 2} } })
    function clientForToplevel(item) { return null; }
    function toplevelsForWorkspace(id) { return []; }
}''',
            'TouchpadGestures.qml': '''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property QtObject overview: QtObject { property real progress: 1 }
    property string command: ""
    function leaveOverview(value) { command = value; }
}''',
        })
        self.assertIn('DRIVER_PASS', output, output[-4000:])
        issues = [line for line in output.splitlines() if 'CHECK_FAIL' in line or
                  ('TaskView' in line and pages.PROBLEMS.search(line))]
        self.assertEqual(issues, [])


if __name__ == '__main__':
    unittest.main()
