"""Exercise the switcher's selection logic and first-frame highlight without a desktop."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
QT_TEST_RUNNER = shutil.which('qmltestrunner6') or next(
    (str(path) for path in (Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner'))
     if path.is_file()), None)


class WindowSwitcherTests(unittest.TestCase):
    @unittest.skipUnless(QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
    def test_selection_and_focus_history(self):
        with tempfile.TemporaryDirectory(prefix='velora-switcher-') as directory:
            root = Path(directory)
            # Leave the controller and timers intact; only the compositor-backed view is omitted.
            source = (SHELL / 'modules/ii/windowSwitcher/WindowSwitcher.qml').read_text()
            source = source.split('    LazyLoader {', 1)[0] + '}\n'
            source = '\n'.join(line for line in source.splitlines()
                               if not line.startswith(('import qs', 'import Quickshell')))
            (root / 'WindowSwitcher.qml').write_text(source.replace('Scope {', 'Item {', 1))
            tile = (SHELL / 'modules/ii/windowSwitcher/WindowSwitcherTile.qml').read_text()
            (root / 'WindowSwitcherTile.qml').write_text('\n'.join(
                line for line in tile.splitlines() if not line.startswith('import qs')))
            stubs = {
                'Hyprland': 'property var activeToplevel:null; property var calls:[]; signal rawEvent(var event); function dispatch(command) { calls=calls.concat([command]); }',
                'HyprlandData': 'property var windowList:[]; property var activeWorkspace: ({id:1})',
                'Appearance': 'property var rounding: ({normal:8}); property var colors: ({colPrimary:"#ffa060"})',
                'ColorUtils': 'function transparentize(color, amount) { return Qt.rgba(1,0.6,0.4,1-amount); }',
            }
            for name, body in stubs.items():
                (root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}\n')
            (root / 'qmldir').write_text('\n'.join(f'singleton {name} 1.0 {name}.qml' for name in stubs) + '\n')
            (root / 'GlobalShortcut.qml').write_text('import QtQuick\nQtObject { property string name; property string description; signal pressed() }\n')
            shutil.copy2(PROJECT / 'tests/qml/tst_windowswitcher.qml', root)
            result = subprocess.run(
                [QT_TEST_RUNNER, '-input', str(root), '-o', '-,txt'],
                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'generic',
                     'QT_QUICK_BACKEND': 'software', 'FONTCONFIG_FILE': '/etc/fonts/fonts.conf'},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
