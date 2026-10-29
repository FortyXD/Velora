"""Exercise the real theme transition's capture acknowledgements and preset readiness."""
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


class ThemeTransitionTests(unittest.TestCase):
    @unittest.skipUnless(QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
    def test_preset_preparation_and_commit(self):
        with tempfile.TemporaryDirectory(prefix='velora-presets-') as directory:
            root = Path(directory)
            for name in ('Presets', 'ShaderWallpaper', 'WallpaperTransition'):
                source = '\n'.join(
                    line for line in (SHELL / f'services/{name}.qml').read_text().splitlines()
                    if not line.startswith(('import qs', 'import Quickshell'))).replace('Singleton {', 'Item {')
                for component in ('backupProc', 'downloadProc'):
                    source = source.replace(f'id: {component}\n', f'id: {component}\n        objectName: "{component}"\n')
                source = source.replace('id: job\n', f'id: job\n            objectName: "{"shaderColorJob" if name == "ShaderWallpaper" else "themeColorJob"}"\n')
                source = source.replace('target: "presets"', 'objectName: "presetsIpc"\n        target: "presets"')
                (root / f'{name}.qml').write_text(source)
            stubs = {
                'Appearance': 'property var m3colors: ({darkmode:true})',
                'Config': 'property int readWriteDelay:1; property var patches:[]; property QtObject options: QtObject { property QtObject appearance: QtObject { property QtObject palette: QtObject { property string accentColor:"#abcdef" } } property QtObject background: QtObject { property string wallpaperPath:"/pictures/old.jpg"; property QtObject daily: QtObject { property bool enable:false; property string source:"" }; property QtObject shaderWallpaper: QtObject { property string name:"" } } } function applyPatch(patch) { patches=patches.concat([patch]); }',
                'Directories': 'property string shellConfig:"/config"; property string state:"/state"; property string pictures:"/pictures"; property string videos:"/videos"; property string shellConfigPath:"/config/config.json"; property string wallpaperSwitchScriptPath:"/switchwall"',
                'FileUtils': 'function trimFileProtocol(path) { return path; } function isVideoPath(path) { return path.endsWith(".mp4"); }',
                'Translation': 'function tr(text) { return text; }',
                'Quickshell': 'property var detached: []; function shellPath(path) { return "/shell/"+path; } function execDetached(command) { detached = detached.concat([command]); }',
                'HyprlandSettings': 'property string jsonPath:"/overrides.json"; property var animationProfiles:[]; property bool applying:false; property var live: []; function setMany(values) {} function setLive(values) { live = live.concat([values]); } function reset(values) {}',
                'MaterialThemeLoader': 'property string pendingColors:""',
                'ThemeTransition': 'property string phase:"idle"; property bool captureInhibited:false; property int captures:0; property int runs:0; property int nextToken:0; property var holds:[]; function run(change,retain) { runs++; if(captureInhibited) { change(0); return 0; } captures++; phase="holding"; const token=++nextToken; holds=holds.concat([token]); change(token); return token; } function release(token) { holds=holds.filter(value=>value!==token); if(token && holds.length===0) phase="revealing"; }',
                'WallpaperOfTheDay': 'property bool running:false; function run() { running=true; }',
            }
            for name, body in stubs.items():
                (root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}\n')
            (root / 'Process.qml').write_text(
                'import QtQuick\nItem { property bool running; property var command; property QtObject stdout; property QtObject stderr; signal exited(int code,int status); function exec(command) { this.command=command; running=true; } }\n')
            (root / 'StdioCollector.qml').write_text('import QtQuick\nQtObject { property string text; signal streamFinished() }\n')
            (root / 'IpcHandler.qml').write_text('import QtQuick\nQtObject { property string target }\n')
            (root / 'qmldir').write_text('\n'.join(
                f'singleton {name} 1.0 {name}.qml' for name in ('Presets', 'ShaderWallpaper', 'WallpaperTransition', *stubs)) + '\n')
            shutil.copy2(PROJECT / 'tests/qml/tst_presets.qml', root)
            result = subprocess.run(
                [QT_TEST_RUNNER, '-input', str(root), '-o', '-,txt'],
                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'generic',
                     'QT_QUICK_BACKEND': 'software', 'FONTCONFIG_FILE': '/etc/fonts/fonts.conf'},
                capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
    def test_preset_transition_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix='velora-theme-transition-') as directory:
            root = Path(directory)
            (root / 'ThemeTransition.qml').write_text('\n'.join(
                line for line in (SHELL / 'services/ThemeTransition.qml').read_text().splitlines()
                if not line.startswith(('import qs.', 'import Quickshell'))).replace('Singleton {', 'Item {'))
            (root / 'Appearance.qml').write_text(
                'pragma Singleton\nimport QtQuick\nQtObject { property real animationSpeed: 1; '
                'function scaledDuration(ms) { return animationSpeed > 0 ? Math.round(ms / 8) : 0; } }\n')
            (root / 'Process.qml').write_text(
                'import QtQuick\nQtObject { property bool running; property var command; property QtObject stdout }\n')
            (root / 'StdioCollector.qml').write_text(
                'import QtQuick\nQtObject { property string text; signal streamFinished() }\n')
            (root / 'qmldir').write_text(
                'singleton ThemeTransition 1.0 ThemeTransition.qml\nsingleton Appearance 1.0 Appearance.qml\n')
            shutil.copy2(PROJECT / 'tests/qml/tst_themetransition.qml', root)
            result = subprocess.run(
                [QT_TEST_RUNNER, '-input', str(root), '-o', '-,txt'],
                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'generic',
                     'QT_QUICK_BACKEND': 'software', 'FONTCONFIG_FILE': '/etc/fonts/fonts.conf'},
                capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
