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


def isolated_qml_env(root, **extra):
    """Never connect the offscreen test shell to the running desktop or its IPC."""
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('QS_', 'HYPRLAND_'))
           and key not in ('DISPLAY', 'WAYLAND_DISPLAY', 'SWAYSOCK', 'qsConfig')}
    for key in ('XDG_RUNTIME_DIR', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME'):
        path = root / key
        path.mkdir(mode=0o700)
        env[key] = str(path)
    return {**env, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
            'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'], **extra}


class HotCornerTests(unittest.TestCase):
    def test_all_corner_input_paths_use_selection_guard(self):
        source = (SHELL / 'modules/ii/screenCorners/ScreenCorners.qml').read_text()
        self.assertIn('if (!activationGuard.allowed) return;', source)
        self.assertIn('activationGuard.allowed && hotWindow.options.trigger === "hover"', source)
        self.assertEqual(source.count('if (!activationGuard.allowed || !hotWindow.options.scroll) return;'), 2)
        self.assertIn('activationGuard.pointerExited()', source)
        self.assertIn('&& !HotCorners.blocked', source)
        self.assertIn('activationGuard.resumeAt(x, y, valid', source)
        service = (SHELL / 'services/HotCorners.qml').read_text()
        self.assertIn('if (root.blocked) return;', service)
        self.assertIn('["timeout", "1", "hyprctl", "cursorpos", "-j"]', service)
        # Recording chooses its region too: the recorder's own selection and an external slurp
        # must hold the corners, and a killed controller must not hold them forever.
        self.assertIn('|| ScreenRecorder.regionSelecting || externalSelection', service)
        self.assertIn('function onRegionSelectingChanged()', service)
        self.assertIn('target: "hotCorners"', service)
        self.assertIn('function block(): void {', service)
        self.assertIn('function unblock(): void {', service)
        self.assertIn('root.armRearm();', service)
        self.assertRegex(service, r'Timer \{[^}]*interval: 120000')
        self.assertNotRegex(service, r'Timer \{[^}]*repeat: true')  # No background position polling.

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
                                    env=isolated_qml_env(root),
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
                (root / 'services/ScreenRecorder.qml').write_text(
                    'pragma Singleton\nimport Quickshell\nSingleton { property bool regionSelecting: false }')
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
                                        env=isolated_qml_env(root, CORNER_TEST_CALLS=str(calls), CORNER_TEST_MODE=mode),
                                        capture_output=True, text=True, timeout=10)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertIn('HOT_CORNER_PASS', output)
                self.assertEqual(calls.read_text(), '2')

    @unittest.skipUnless(QS, 'Quickshell runtime is not installed')
    def test_real_service_recording_selection_holds_the_corner(self):
        """Choosing a recording region must hold the corner, then wait for a real re-entry."""
        with tempfile.TemporaryDirectory(prefix='velora-corner-recording-') as directory:
            root = Path(directory)
            for path in ('services', 'modules/common', 'bin'):
                (root / path).mkdir(parents=True, exist_ok=True)
            shutil.copy2(SHELL / 'services/HotCorners.qml', root / 'services/HotCorners.qml')
            shutil.copy2(GUARD, root)
            (root / 'GlobalStates.qml').write_text(
                'pragma Singleton\nimport Quickshell\n'
                'Singleton { property bool regionSelectorOpen: false; property bool sidebarRightOpen: false;'
                ' property bool sessionOpen: false }')
            (root / 'modules/common/Config.qml').write_text(
                'pragma Singleton\nimport Quickshell\n'
                'Singleton { property bool ready: true; property var options: ({hotCorners:{version:1}}) }')
            (root / 'services/Translation.qml').write_text(
                'pragma Singleton\nimport Quickshell\nSingleton { function tr(text) { return text; } }')
            (root / 'services/ScreenRecorder.qml').write_text(
                'pragma Singleton\nimport Quickshell\nSingleton { property bool regionSelecting: false }')
            fake = root / 'bin/hyprctl'
            fake.write_text(
                '#!/usr/bin/env python3\n'
                'import json, os, pathlib, time\n'
                'marker = pathlib.Path(os.environ["CORNER_REC_CALLS"])\n'
                'marker.write_text(str(int(marker.read_text()) + 1) if marker.exists() else "1")\n'
                'time.sleep(.3)  # The rearm check is in flight while the handoff finishes.\n'
                'print(json.dumps(dict(x=1999, y=0)))  # Released right inside the corner.\n')
            fake.chmod(0o755)
            code = """import QtQuick
import Quickshell
import qs
import qs.services
Scope {
    id: root
    property string failure: ""
    function check(ok, message) { if (!ok) failure += message + ";"; }
    HotCornerActivationGuard {
        id: guard
        suppressed: HotCorners.blocked
        corner: "topRight"
        screenWidth: 2000; screenHeight: 1000; size: 6
    }
    Connections {
        target: HotCorners
        function onSelectionFinished(x, y, valid) { guard.resumeAt(x, y, valid); }
    }
    Component.onCompleted: {
        ScreenRecorder.regionSelecting = true;
        check(HotCorners.blocked, "recorder selection did not hold the corner");
        HotCorners.run("session", "");
        check(!GlobalStates.sessionOpen, "corner fired while choosing a recording region");
    }
    Timer { interval: 60; running: true; onTriggered: ScreenRecorder.regionSelecting = false }
    Timer { interval: 200; running: true; onTriggered: {
        check(HotCorners.blocked, "corner rearmed before the pointer was checked");
        HotCorners.run("session", "");
        check(!GlobalStates.sessionOpen, "corner fired during the recorder handoff");
    } }
    Timer { interval: 1200; running: true; onTriggered: {
        check(!HotCorners.blocked && guard.suppressed === false, "the handoff never released the guard");
        check(!guard.allowed, "corner armed with the pointer still inside it");
        guard.pointerExited();
        check(guard.allowed, "a fresh entry cannot activate the corner");
        HotCorners.run("session", "");
        check(GlobalStates.sessionOpen, "normal corner action stopped working");
        console.log(failure ? "HOT_CORNER_FAIL:" + failure : "HOT_CORNER_PASS");
        Qt.quit();
    } }
}
"""
            (root / 'shell.qml').write_text(code)
            calls = root / 'calls'
            calls.write_text('0')
            result = subprocess.run([QS, '-p', str(root / 'shell.qml'), '--no-color'],
                                    env=isolated_qml_env(root, CORNER_REC_CALLS=str(calls)),
                                    capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('HOT_CORNER_PASS', output)
            self.assertEqual(calls.read_text(), '1')  # One bounded check per finished selection.

    @unittest.skipUnless(QS, 'Quickshell runtime is not installed')
    def test_external_ipc_unblock_and_killed_controller_expiry_rearm(self):
        # Accelerate only the timer in a temporary copy; assert the production bound above.
        for mode in ('unblock', 'expiry', 'expiry-overlap'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='velora-corner-ipc-') as directory:
                root = Path(directory)
                for relative in ('services', 'modules/common', 'bin'):
                    (root / relative).mkdir(parents=True)
                service = (SHELL / 'services/HotCorners.qml').read_text()
                self.assertEqual(service.count('interval: 120000'), 1)
                (root / 'services/HotCorners.qml').write_text(service.replace('interval: 120000', 'interval: 500'))
                shutil.copy2(GUARD, root)
                (root / 'GlobalStates.qml').write_text(
                    'pragma Singleton\nimport Quickshell\nSingleton { property bool regionSelectorOpen: false; property bool sessionOpen: false }')
                (root / 'modules/common/Config.qml').write_text(
                    'pragma Singleton\nimport Quickshell\nSingleton { property bool ready: true; property var options: ({hotCorners:{version:2}}) }')
                (root / 'services/Translation.qml').write_text(
                    'pragma Singleton\nimport Quickshell\nSingleton { function tr(text) { return text; } }')
                (root / 'services/ScreenRecorder.qml').write_text(
                    'pragma Singleton\nimport Quickshell\nSingleton { property bool regionSelecting: false }')
                fake = root / 'bin/hyprctl'
                fake.write_text('#!/usr/bin/env python3\nimport os,pathlib,time\n'
                                'p=pathlib.Path(os.environ["CORNER_IPC_CALLS"])\n'
                                'p.write_text(p.read_text()+"query\\n" if p.exists() else "query\\n")\n'
                                'time.sleep(.3)\nprint(\'{"x":1999,"y":0}\')\n')
                fake.chmod(0o755)
                # The client targets this temporary shell only. SIGKILL deliberately bypasses unblock.
                client = root / 'controller.py'
                client.write_text('import os,signal,subprocess,time\n'
                                  f'cmd={[QS, "-p", str(root / "shell.qml"), "ipc", "call", "hotCorners"]!r}\n'
                                  'subprocess.run(cmd+["block"],check=True,timeout=3)\n'
                                  'print("CONTROLLER_BLOCKED",flush=True)\n'
                                  'time.sleep(.15)\n' +
                                  ('subprocess.run(cmd+["unblock"],check=True,timeout=3)\n'
                                   'subprocess.run(cmd+["unblock"],check=True,timeout=3)\n' if mode == 'unblock'
                                   else 'os.kill(os.getpid(),signal.SIGKILL)\n'))
                code = """import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
Scope {
    id: root
    property string failure: ""
    property int results: 0
    property bool testedHold: false
    function check(ok, message) { if (!ok) failure += message + ";"; }
    HotCornerActivationGuard {
        id: guard
        suppressed: HotCorners.blocked
        corner: "topRight"
        screenWidth: 2000; screenHeight: 1000; size: 12; circular: true
    }
    Connections {
        target: HotCorners
        function onExternalSelectionChanged() {
            if (!HotCorners.externalSelection) return;
            root.testedHold = true;
            root.check(HotCorners.blocked, "IPC block failed");
            HotCorners.run("session", "");
            root.check(!GlobalStates.sessionOpen, "action fired during external selection");
            guard.pointerExited();
            root.check(!guard.allowed, "hiding the corner rearmed it");
            if (OVERLAP) ScreenRecorder.regionSelecting = true;
            holdCheck.restart();
        }
        function onSelectionFinished(x, y, valid) {
            root.results++;
            root.check(valid && x === 1999, "cursor query failed");
            guard.resumeAt(x, y, valid);
        }
    }
    Timer { id: holdCheck; interval: HOLD_DELAY; onTriggered: {
        root.check(HotCorners.blocked && root.results === 0, "guard opened before cursor check");
        HotCorners.run("session", "");
        root.check(!GlobalStates.sessionOpen, "action fired during rearm");
        if (OVERLAP) {
            root.check(!HotCorners.externalSelection, "expired IPC block retained");
            ScreenRecorder.regionSelecting = false;
        }
    } }
    Process {
        command: CLIENT
        running: true
        stdout: StdioCollector { onStreamFinished: console.log(text) }
        stderr: StdioCollector { onStreamFinished: console.log(text) }
        onExited: (code, status) => root.check(code === EXPECTED_EXIT, "unexpected controller exit " + code)
    }
    Timer { interval: 1800; running: true; onTriggered: {
        root.check(root.testedHold && root.results === 1, "selection did not rearm exactly once");
        root.check(!HotCorners.externalSelection && !HotCorners.blocked, "external block stuck");
        root.check(!guard.allowed, "release inside corner armed it");
        guard.pointerExited();
        root.check(guard.allowed, "pointer exit did not rearm");
        HotCorners.run("session", "");
        root.check(GlobalStates.sessionOpen, "fresh corner action failed");
        console.log(root.failure ? "HOT_CORNER_FAIL:" + root.failure : "HOT_CORNER_PASS");
        Qt.quit();
    } }
}
""".replace('CLIENT', json.dumps([shutil.which('python3'), str(client)]))
                code = code.replace('OVERLAP', 'true' if mode == 'expiry-overlap' else 'false')
                code = code.replace('HOLD_DELAY', '650' if mode == 'expiry-overlap' else '250' if mode == 'unblock' else '600')
                code = code.replace('EXPECTED_EXIT', '0' if mode == 'unblock' else '9')
                (root / 'shell.qml').write_text(code)
                calls = root / 'calls'
                result = subprocess.run([QS, '-p', str(root / 'shell.qml'), '--no-color'],
                                        env=isolated_qml_env(root, CORNER_IPC_CALLS=str(calls)),
                                        capture_output=True, text=True, timeout=15)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertIn('CONTROLLER_BLOCKED', output)
                self.assertIn('HOT_CORNER_PASS', output)
                self.assertNotIn('HOT_CORNER_FAIL', output)
                self.assertEqual(calls.read_text().splitlines(), ['query'])

if __name__ == '__main__':
    unittest.main()
