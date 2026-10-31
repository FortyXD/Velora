"""The setup assistant's steps and choices (modules/onboarding/OnboardingFlow.qml), with stand-ins for the shell."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
QT_TEST_RUNNER = shutil.which('qmltestrunner6') or next(
    (str(path) for path in (Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner'))
     if path.is_file()), None)
ONBOARDING = SHELL / 'modules/onboarding'


class OnboardingTests(unittest.TestCase):
    @unittest.skipUnless(QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
    def test_flow(self):
        with tempfile.TemporaryDirectory(prefix='velora-onboarding-') as directory:
            root = Path(directory)
            source = '\n'.join(line for line in (ONBOARDING / 'OnboardingFlow.qml').read_text().splitlines()
                               if not line.startswith(('import qs', 'import Quickshell')))
            (root / 'OnboardingFlow.qml').write_text(source.replace('id: job\n', 'id: job\n            objectName: "presetApply-" + request\n'))
            stubs = {
                'Quickshell': 'property var commands: []; function env(name) { return ""; } function execDetached(command) { commands = commands.concat([command]); } function shellPath(path) { return "/shell/" + path; }',
                'Config': 'property var options: ({ osk: { layout: "" }, language: { ui: "auto" }, background: { wallpaperPath: "/w.jpg", thumbnailPath: "" } }); function setNestedValue(path, value) {}',
                'Translation': 'function tr(text) { return text; }',
                'Appearance': 'property var m3colors: ({ darkmode: true })',
                'MaterialThemeLoader': 'property int reloads: 0; function reapplyTheme() { reloads++; }',
                'Directories': 'property string home: "/home/test"; property string config: "/home/test/.config"; property string wallpaperSwitchScriptPath: "/switchwall"',
                'FileUtils': 'function trimFileProtocol(path) { return path; } function isVideoPath(path) { return path.endsWith(".mp4"); }',
            }
            for name, body in stubs.items():
                (root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}\n')
            (root / 'FileView.qml').write_text(
                'import QtQuick\nQtObject { property string path; property bool printErrors; property bool blockLoading; property string written: "{}"; '
                'property string content: ""; signal loaded(); signal loadFailed(); function setText(text) { written = text; } '
                'function text() { return content; } }\n')
            (root / 'Process.qml').write_text(
                'import QtQuick\nQtObject { property bool running; property var command; property QtObject stdout; '
                'property QtObject stderr; property bool stdinEnabled; property var writes: []; '
                'signal started(); signal exited(int exitCode, int exitStatus); '
                'function write(text) { writes = writes.concat([text]); } }\n')
            (root / 'StdioCollector.qml').write_text('import QtQuick\nQtObject { property string text; signal streamFinished() }\n')
            (root / 'SplitParser.qml').write_text('import QtQuick\nQtObject { signal read(string data) }\n')
            (root / 'qmldir').write_text(''.join(f'singleton {name} 1.0 {name}.qml\n' for name in stubs)
                                         + 'OnboardingFlow 1.0 OnboardingFlow.qml\n')
            # Exercise the real view and modal focus/key handling with lightweight page visuals.
            for name in ('OnboardingView', 'PasswordDialog'):
                source = '\n'.join(line for line in (ONBOARDING / f'{name}.qml').read_text().splitlines()
                                   if not line.startswith('import qs'))
                source = source.replace('id: sheet\n', 'id: sheet\n            objectName: "sheet"\n')
                source = source.replace('id: field\n', 'id: field\n                        objectName: "passwordField"\n')
                (root / f'{name}.qml').write_text(source)
            ui_singletons = {
                'Motion': 'property bool reduced: true; property var accelerate: [0,0,1,1,1,1]; property var decelerate: [0,0,1,1,1,1]; property var emphasized: [0,0,1,1,1,1]; property var spatial: [0,0,1,1,1,1]; function ms(n) { return 0; } function travel(n) { return 0; }',
                'Hyprland': 'signal rawEvent(var event)',
                'Network': 'property bool wifi: true; property bool ethernet: false; property bool available: true; property string connectivity: "full"',
                'HyprlandSettings': 'property var reloadCommand: ["hyprctl", "reload"]',
                'Presets': 'property var presets: []; function isRemote(path) { return /^https?:/.test(path ?? ""); }',
                'ColorUtils': 'function colorWithHueOf(color, hue) { return color; } function transparentize(color, alpha) { return color; }',
            }
            for name, body in ui_singletons.items():
                (root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}\n')
            visual_sources = [ONBOARDING / name for name in ('OnboardingView.qml', 'PasswordDialog.qml', 'SelectCard.qml', 'pages/DisplayPage.qml', 'pages/AppearancePage.qml')]
            colors = {name: '#777777' for path in visual_sources
                      for name in re.findall(r'Appearance\.colors\.(\w+)', path.read_text())}
            colors.update(colLayer0='#222222', colLayer1='#333333', colPrimary='#ffa500', colOnPrimary='#000000')
            (root / 'Appearance.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { '
                'property var m3colors: ({darkmode:true,m3primary:"#ffa500"}); property var colors: (' + json.dumps(colors) + '); '
                'property var rounding: ({verylarge:24,normal:12,large:16,small:8}); property var font: ({family:{title:"Sans",main:"Sans",monospace:"Monospace"},pixelSize:{huge:24,large:18,larger:20,small:12,smaller:10}}) }')
            (root / 'HyprlandXkb.qml').write_text('\n'.join(
                line for line in (SHELL / 'services/HyprlandXkb.qml').read_text().splitlines()
                if not line.startswith(('import qs', 'import Quickshell'))).replace('Singleton {', 'Item {'))
            with (root / 'qmldir').open('a') as file:
                file.write('singleton HyprlandXkb 1.0 HyprlandXkb.qml\n')
            source = '\n'.join(line for line in (SHELL / 'services/HyprlandMonitors.qml').read_text().splitlines()
                               if not line.startswith(('import qs', 'import Quickshell'))).replace('Singleton {', 'Item {')
            for name in ('countdown', 'jsonFile', 'luaFile'):
                source = source.replace(f'id: {name}\n', f'id: {name}\n        objectName: "{name}"\n')
            (root / 'HyprlandMonitors.qml').write_text(source)
            with (root / 'qmldir').open('a') as file:
                file.write('singleton HyprlandMonitors 1.0 HyprlandMonitors.qml\n')
            widgets = {
                'StyledText': 'Text {}',
                'MaterialSymbol': 'Text { property real iconSize:20 }',
                'MaterialLoadingIndicator': 'Item { property real implicitSize; property bool loading }',
                'MaterialShapeWrappedMaterialSymbol': 'Item { property int shape; property real implicitSize; property string text; property real iconSize; property color color; property color colSymbol }',
                'MaterialShape': 'Item { enum Shape { Cookie7Sided } }',
                'StyledRectangularShadow': 'Item { property Item target }',
                'ErrorShakeAnimation': 'QtObject { property Item target; property real distance; function restart() {} }',
                'RippleButton': 'Item { property int focusPolicy; property real buttonRadius; property bool toggled; property color colBackground; property color colBackgroundHover; property color colRipple; property color colBackgroundToggled; property color colBackgroundToggledHover; property Item contentItem; signal clicked() }',
                'AccessibilityButton': 'Item { property var flow }',
                'StepIndicator': 'Item { property var flow; implicitHeight:40 }',
                'HelloPage': 'Item { property var flow; property Item startButton: Item { width:120; height:48 }; signal started() }',
            }
            widgets.update({
                'PageScaffold': 'Item { required property var flow; property string title; property string subtitle; property bool scrollable; property Item focusTarget:null; property real areaHeight:500; property int fromSide; function leave(direction) { destroy(); } }',
                'Reveal': 'Item { property int order }',
                'ChoiceDropdown': 'Item { property var options; property var currentValue; signal selected(var value) }',
                'CircularProgress': 'Item { property real implicitSize; property real lineWidth; property real value; property color colPrimary }',
            })
            for name in ('Language', 'Display', 'Network', 'Layout', 'Appearance', 'Extras', 'Install', 'Done'):
                widgets[f'{name}Page'] = ('Item { property var flow; property int fromSide; property Item focusTarget:null; '
                    'function leave(direction) { destroy(); } '
                    + ('Component.onCompleted: flow.askPassword()' if name == 'Install' else '') + ' }')
            for name, body in widgets.items():
                (root / f'{name}.qml').write_text(f'import QtQuick\n{body}\n')
            for name, path in (('DisplayPage', 'pages/DisplayPage.qml'), ('AppearancePage', 'pages/AppearancePage.qml'), ('SelectCard', 'SelectCard.qml')):
                source = '\n'.join(line for line in (ONBOARDING / path).read_text().splitlines()
                                   if not line.startswith('import qs'))
                source = source.replace('id: tile\n', 'id: tile\n                    objectName: "wallpaper-" + modelData.id\n')
                (root / f'{name}.qml').write_text(source)
            with (root / 'qmldir').open('a') as file:
                file.write(''.join(f'singleton {name} 1.0 {name}.qml\n' for name in ui_singletons))
            shutil.copy2(PROJECT / 'tests/qml/tst_onboarding.qml', root)
            result = subprocess.run(
                [QT_TEST_RUNNER, '-input', str(root), '-o', '-,txt'],
                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'generic',
                     'QT_QUICK_BACKEND': 'software', 'FONTCONFIG_FILE': '/etc/fonts/fonts.conf'},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_every_string_of_the_assistant_is_translated_to_russian(self):
        russian = json.loads((SHELL / 'translations/ru_RU.json').read_text())
        files = [*ONBOARDING.rglob('*.qml'), SHELL / 'onboarding.qml', SHELL / 'services/FirstRunExperience.qml',
                 *(SHELL / 'modules/ii/tour').glob('*.qml'), *(SHELL / 'modules/ii/windowSwitcher').glob('*.qml'),
                 *(SHELL / 'modules/ii/appLibrary').glob('*.qml'), SHELL / 'services/GestureSettings.qml',
                 SHELL / 'modules/ii/bar/widgets/TaskbarWidget.qml']
        missing = sorted({match for path in files
                          for match in re.findall(r'Translation\.tr\("((?:[^"\\]|\\.)*)"\)', path.read_text())
                          if match not in russian})
        self.assertEqual(missing, [], 'Add these to translations/ru_RU.json')

    def test_the_three_looks_come_from_presets(self):
        flow = (ONBOARDING / 'OnboardingFlow.qml').read_text()
        for look, preset_id, vertical, bottom in (('velora', 'synthwave', False, False), ('horizon', 'pastel', False, True),
                                                  ('vertical', 'autumn', True, False)):
            self.assertIn(f'"{look}": "{preset_id}"', flow)
            bar = json.loads((SHELL / f'defaults/presets/{preset_id}.json').read_text())['bar']['config']['bar']
            self.assertEqual((bar['vertical'], bar['bottom']), (vertical, bottom), preset_id)
        # Everything of the preset but its picture, and windows tiled unless chosen otherwise
        self.assertIn('"bar,theme,dockWidgets,motion"', flow)
        self.assertIn('"windows": "tiling"', flow)
        self.assertIn('"wallpaper": "autumn"', flow)


if __name__ == '__main__':
    unittest.main()
