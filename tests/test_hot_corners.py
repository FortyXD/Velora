"""Selection gestures must not leak into hover/click/scroll hot-corner actions."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / 'dots/.config/quickshell/ii'
GUARD = SHELL / 'modules/ii/screenCorners/HotCornerActivationGuard.qml'
QT_RUNNER = shutil.which('qmltestrunner6') or next(
    (str(p) for p in (Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner')) if p.is_file()), None)
QS = shutil.which('qs')


class HotCornerTests(unittest.TestCase):
    def test_all_corner_input_paths_use_selection_guard(self):
        source = (SHELL / 'modules/ii/screenCorners/ScreenCorners.qml').read_text()
        self.assertIn('if (!activationGuard.allowed) return;', source)
        self.assertIn('activationGuard.allowed && hotWindow.options.trigger === "hover"', source)
        self.assertEqual(source.count('if (!activationGuard.allowed || !hotWindow.options.scroll) return;'), 2)
        self.assertIn('activationGuard.pointerExited()', source)
        self.assertIn('&& !GlobalStates.regionSelectorOpen', source)
        self.assertIn('activationGuard.resumeAt(x, y, valid', source)
        service = (SHELL / 'services/HotCorners.qml').read_text()
        self.assertIn('if (root.blocked) return;', service)
        self.assertIn('["timeout", "1", "hyprctl", "cursorpos", "-j"]', service)
        self.assertNotIn('Timer {', service)  # No background position polling.

    @unittest.skipUnless(QT_RUNNER, 'Qt 6 Quick Test is not installed')
    def test_production_guard_state_and_scaled_monitor_geometry(self):
        with tempfile.TemporaryDirectory(prefix='velora-corner-guard-') as directory:
            root = Path(directory)
            shutil.copy2(GUARD, root)
            window = (SHELL / 'modules/ii/screenCorners/ScreenCorners.qml').read_text()
            start = window.index('onAllowedChanged: {')
            brace = window.index('{', start)
            depth = 0
            for index in range(brace, len(window)):
                depth += (window[index] == '{') - (window[index] == '}')
                if depth == 0:
                    handler = window[start:index + 1]
                    break
            source = (ROOT / 'tests/qml/tst_hotcornerguard.qml').read_text()
            (root / 'tst_hotcornerguard.qml').write_text(source.replace('// PRODUCTION_ALLOWED_HANDLER', handler))
            result = subprocess.run([QT_RUNNER, '-input', str(root), '-o', '-,txt'],
                                    env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software'},
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(QS, 'Quickshell runtime is not installed')
    def test_real_service_suppression_stale_reply_and_cursor_failure(self):
        for mode in ('good', 'invalid', 'timeout'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='velora-corner-service-') as directory:
                root = Path(directory)
                for path in ('services', 'modules/common', 'bin'):
                    (root / path).mkdir(parents=True, exist_ok=True)
                shutil.copy2(SHELL / 'services/HotCorners.qml', root / 'services/HotCorners.qml')
                shutil.copy2(GUARD, root)
                (root / 'GlobalStates.qml').write_text(
                    'pragma Singleton\nimport Quickshell\nSingleton { property bool regionSelectorOpen: false; property bool sidebarRightOpen: false; property bool sessionOpen: false }')
                (root / 'modules/common/Config.qml').write_text(
                    'pragma Singleton\nimport Quickshell\nSingleton { property bool ready: true; property var options: ({hotCorners:{version:1}}) }')
                (root / 'services/Translation.qml').write_text(
                    'pragma Singleton\nimport Quickshell\nSingleton { function tr(text) { return text; } }')
                executable = root / 'bin/hyprctl'
                executable.write_text('''#!/usr/bin/env python3
import json, os, pathlib, time
path = pathlib.Path(os.environ['CORNER_TEST_CALLS'])
count = int(path.read_text()) + 1 if path.exists() else 1
path.write_text(str(count))
if os.environ['CORNER_TEST_MODE'] == 'timeout':
    time.sleep(2)
elif count == 1:
    time.sleep(.3)
if os.environ['CORNER_TEST_MODE'] == 'invalid':
    print('invalid cursor output')
    raise SystemExit(1)
print(json.dumps(dict(x=10 if count == 1 else 1999, y=0)))
''')
                executable.chmod(0o755)
                code = '''import QtQuick
import Quickshell
import qs
import qs.services
Scope {
    id: root
    property string failure: ""
    property int results: 0
    function check(ok, message) { if (!ok) failure += message + ";"; }
    HotCornerActivationGuard {
        id: guard
        suppressed: HotCorners.blocked
        corner: "topRight"
        screenWidth: 2000; screenHeight: 1000; size: 6
    }
    Connections {
        target: HotCorners
        function onSelectionFinished(x, y, valid) {
            root.results++;
            root.check(valid === EXPECTED_VALID, "unexpected validity");
            if (valid) root.check(x === 1999, "stale position was applied");
            guard.resumeAt(x, y, valid);
        }
    }
    Component.onCompleted: {
        GlobalStates.regionSelectorOpen = true;
        HotCorners.run("session", "");
        root.check(!GlobalStates.sessionOpen, "session action fired during selection");
    }
    Timer { interval: 20; running: true; onTriggered: GlobalStates.regionSelectorOpen = false }
    Timer { interval: 80; running: true; onTriggered: GlobalStates.regionSelectorOpen = true }
    Timer { interval: 100; running: true; onTriggered: GlobalStates.regionSelectorOpen = false }
    Timer { interval: 200; running: true; onTriggered: {
        root.check(HotCorners.blocked, "selection guard opened before position check");
        HotCorners.run("sidebarRight", "");
        root.check(!GlobalStates.sidebarRightOpen, "sidebar fired before rearm");
    } }
    Timer { interval: FINAL_CHECK_DELAY; running: true; onTriggered: {
        root.check(root.results === 1 && !HotCorners.blocked, "latest selection never completed");
        root.check(!guard.allowed, "corner under release pointer armed itself");
        guard.pointerExited();
        root.check(guard.allowed, "fresh entry cannot activate corner");
        if (guard.allowed) HotCorners.run("session", "");
        root.check(GlobalStates.sessionOpen, "normal corner action stopped working");
        console.log(root.failure ? "HOT_CORNER_FAIL:" + root.failure : "HOT_CORNER_PASS");
        Qt.quit();
    } }
}'''.replace('EXPECTED_VALID', 'true' if mode == 'good' else 'false').replace('FINAL_CHECK_DELAY', '2500' if mode == 'timeout' else '800')
                (root / 'shell.qml').write_text(code)
                calls = root / 'calls'
                result = subprocess.run([QS, '-p', str(root / 'shell.qml'), '--no-color'],
                                        env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
                                             'CORNER_TEST_CALLS': str(calls), 'CORNER_TEST_MODE': mode},
                                        capture_output=True, text=True, timeout=10)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertIn('HOT_CORNER_PASS', output)
                self.assertEqual(calls.read_text(), '2')


if __name__ == '__main__':
    unittest.main()
