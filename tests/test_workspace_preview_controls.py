"""Preview preferences, production popup timers, and real panel pointer boundaries."""
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
RUNNER = next((str(p) for p in (Path('/usr/lib/qt6/bin/qmltestrunner'),
                              Path('/usr/lib64/qt6/bin/qmltestrunner')) if p.is_file()), None)


def write(root, name, content):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def run_qt(root):
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
           'QT_QPA_PLATFORMTHEME': 'generic'}
    for key in ('XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'HOME'):
        directory = root / key
        directory.mkdir()
        env[key] = str(directory)
    result = subprocess.run([RUNNER, '-input', str(root)], env=env,
                            capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    for noise in ('TypeError', 'ReferenceError', 'Cannot assign', 'Binding loop'):
        assert noise not in output, output
    return output


class WorkspacePreviewControlsTests(unittest.TestCase):
    def test_compatible_defaults_panel_wiring_and_translations(self):
        config = (SHELL / 'modules/common/Config.qml').read_text()
        example = json.loads((PROJECT / 'dots/.config/illogical-impulse/config.example.json').read_text())
        for key, value in (('showPreviews', True), ('hidePreviewOnLeave', False)):
            self.assertIn(f'property bool {key}: {str(value).lower()}', config)
            self.assertIs(example['bar']['workspaces'][key], value)
        for path in ('modules/ii/bar/Bar.qml', 'modules/ii/verticalBar/VerticalBar.qml'):
            source = (SHELL / path).read_text()
            self.assertIn('readonly property bool panelHovered: panelPointer.hovered', source)
            self.assertRegex(source, r'id: barContent\s+HoverHandler\s*\{\s*id: panelPointer\s+blocking: false')
        workspaces = (SHELL / 'modules/ii/bar/Workspaces.qml').read_text()
        self.assertIn('panelHovered: root.QsWindow.window?.panelHovered ?? false', workspaces)
        popup = (SHELL / 'modules/ii/bar/WorkspacePreviewPopup.qml').read_text()
        for binding in ('hoverEnabled: Config.options.bar.workspaces.showPreviews',
                        'interactive: !leavePanel', 'keepOpen: leavePanel && panelHovered',
                        'closeImmediately: leavePanel && !panelHovered'):
            self.assertIn(binding, popup)
        catalog = (SHELL / 'modules/common/BarWidgetCatalog.qml').read_text()
        russian = json.loads((SHELL / 'translations/ru_RU.json').read_text())
        for source in (catalog, popup):
            for label in re.findall(r'Translation.tr\("([^"\n]+)"\)', source):
                self.assertTrue(russian.get(label), label)

    @unittest.skipUnless(shutil.which('quickshell'), 'Quickshell unavailable')
    def test_actual_config_persists_booleans_and_preserves_existing_preferences(self):
        from test_workspace_preview_flick import isolated_env
        with tempfile.TemporaryDirectory(prefix='velora-preview-persist-') as name:
            root = Path(name)
            saved = root / 'preferences.json'
            saved.write_text(json.dumps({'bar': {'workspaces': {'flickSpeed': 425, 'hidePreviewOnFlick': False}},
                                         'screenRecord': {'audio': 'silent'}}))
            write(root, 'modules/common/Directories.qml', 'pragma Singleton\nimport Quickshell\nSingleton { property string shellConfigPath: '
                  + json.dumps(str(saved)) + '; property string defaultWallpaper: "/tmp/wallpaper.jpg" }')
            write(root, 'modules/common/functions/FileUtils.qml', 'pragma Singleton\nimport Quickshell\nSingleton {}')
            write(root, 'services/Translation.qml', 'pragma Singleton\nimport Quickshell\nSingleton { function tr(s) { return s; } }')
            write(root, 'modules/common/Appearance.qml', 'pragma Singleton\nimport Quickshell\nSingleton { property var font: ({pixelSize:{smaller:12}}) }')
            write(root, 'modules/common/qmldir', 'module qs.modules.common\nsingleton Config 1.0 Config.qml\nsingleton Directories 1.0 Directories.qml\nsingleton Appearance 1.0 Appearance.qml\n')
            write(root, 'services/qmldir', 'module qs.services\nsingleton Translation 1.0 Translation.qml\n')
            write(root, 'modules/common/functions/qmldir', 'module qs.modules.common.functions\nsingleton FileUtils 1.0 FileUtils.qml\n')
            shutil.copy2(SHELL / 'modules/common/Config.qml', root / 'modules/common/Config.qml')
            for second in (False, True):
                body = '''
                const ws = Config.options.bar.workspaces;
                if (ws.flickSpeed !== 425 || ws.hidePreviewOnFlick !== false || Config.options.screenRecord.audio !== "silent") Qt.exit(2);
                '''
                if not second:
                    body += '''if (!ws.showPreviews || ws.hidePreviewOnLeave) Qt.exit(3);
                    ws.showPreviews = false; ws.hidePreviewOnLeave = true;'''
                else:
                    body += 'if (ws.showPreviews || !ws.hidePreviewOnLeave) Qt.exit(4);'
                write(root, 'shell.qml', '''import QtQuick
import Quickshell
import qs.modules.common
ShellRoot {
 Timer { interval: 100; running: Config.ready; onTriggered: { ''' + body + '''
  finish.start();
 } }
 Timer { id: finish; interval: 200; onTriggered: { console.log("PERSIST_PASS"); Qt.quit(); } }
 Timer { interval: 5000; running: true; onTriggered: Qt.exit(5) }
}
''')
                result = subprocess.run([shutil.which('quickshell'), '-p', str(root / 'shell.qml')],
                                        env=isolated_env(root), capture_output=True, text=True, timeout=15)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertIn('PERSIST_PASS', output)
                for noise in ('TypeError', 'ReferenceError', 'Failed to load'):
                    self.assertNotIn(noise, output)
            preferences = json.loads(saved.read_text())['bar']['workspaces']
            self.assertIs(preferences['showPreviews'], False)
            self.assertIs(preferences['hidePreviewOnLeave'], True)
            self.assertEqual(preferences['flickSpeed'], 425)

    @unittest.skipUnless(RUNNER, 'Qt 6 Quick Test unavailable')
    def test_production_state_timers_and_real_pointer_on_all_panel_edges(self):
        with tempfile.TemporaryDirectory(prefix='velora-preview-state-') as name:
            root = Path(name)
            source = (SHELL / 'modules/ii/bar/StyledPopup.qml').read_text()
            # Only the compositor renderer is replaced. Execute all production state,
            # policy, and timers unchanged, including the active/lingering binding.
            state = source.split('LazyLoader {', 1)[1].split('    component: PanelWindow {', 1)[0]
            write(root, 'PopupState.qml', 'import QtQuick\nItem { property bool active\n' + state + '\n}')
            policy = (SHELL / 'modules/common/functions/PopupHoverPolicy.qml').read_text()
            write(root, 'PopupHoverPolicy.qml', policy.replace('import Quickshell', 'import QtQml').replace('Singleton {', 'QtObject {'))
            write(root, 'Config.qml', 'pragma Singleton\nimport QtQuick\nQtObject { property var options: ({bar: {microAnimations: true}}) }')
            write(root, 'GlobalStates.qml', 'pragma Singleton\nimport QtQuick\nQtObject { property bool barEditing: false }')
            write(root, 'Appearance.qml', 'pragma Singleton\nimport QtQuick\nQtObject { property var animation: ({elementMoveFast: {duration: 90}}) }')
            # Support a click-presence helper if this test is run alongside that independent fix.
            presence = SHELL / 'modules/common/widgets/PopupHoverTarget.qml'
            if presence.exists():
                shutil.copy2(presence, root)
            write(root, 'qmldir', '\n'.join('singleton ' + n + ' 1.0 ' + n + '.qml'
                                           for n in ('Config', 'GlobalStates', 'Appearance', 'PopupHoverPolicy')))
            shutil.copy2(PROJECT / 'tests/qml/tst_workspacepreviewcontrols.qml', root)
            run_qt(root)

    @unittest.skipUnless(RUNNER, 'Qt 6 Quick Test unavailable')
    def test_real_options_form_progressive_disclosure_and_roundtrip(self):
        with tempfile.TemporaryDirectory(prefix='velora-preview-form-') as name:
            root = Path(name)
            # Actual catalog and actual form, with small rendering stand-ins. Store
            # booleans as booleans, preserve flick preferences through hidden modes.
            catalog = (SHELL / 'modules/common/BarWidgetCatalog.qml').read_text()
            catalog = catalog.replace('import Quickshell', 'import QtQuick').replace('import qs.services', '').replace('Singleton {', 'QtObject {')
            write(root, 'BarWidgetCatalog.qml', catalog)
            form = (SHELL / 'modules/common/widgets/BarWidgetOptionsForm.qml').read_text()
            form = re.sub(r'^import qs\..*\n', '', form, flags=re.M)
            write(root, 'BarWidgetOptionsForm.qml', form)
            write(root, 'Translation.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function tr(s) { return s; } }')
            write(root, 'Config.qml', '''pragma Singleton
import QtQuick
QtObject {
 property QtObject options: QtObject { property QtObject bar: QtObject { property QtObject workspaces: QtObject {
  property int shown: 10
  property int showNumberDelay: 0
  property bool showPreviews: true
  property bool hidePreviewOnLeave: false
  property bool hidePreviewOnFlick: true
  property int flickSpeed: 370
 } } }
 function getNestedValue(path, fallback) {
  let value = options;
  for (const key of path.split('.')) { if (value == null) return fallback; value = value[key]; }
  return value === undefined ? fallback : value;
 }
}
''')
            write(root, 'BarLayout.qml', '''pragma Singleton
import QtQuick
QtObject {
 function setOptionValue(orientation, uid, spec, value) {
  let node = Config.options;
  const keys = spec.scope.slice(5).split('.');
  for (let i=0; i<keys.length-1; i++) node = node[keys[i]];
  node[keys[keys.length-1]] = value;
 }
}
''')
            for component in ('ConfigSwitch', 'ConfigSpinBox', 'ConfigComboRow', 'ConfigTextRow'):
                write(root, component + '.qml', '''import QtQuick
Item {
 implicitHeight: 50; implicitWidth: 300
 property string text; property string description; property string buttonIcon; property string icon
 property string label; property bool autoToggle; property bool checked; property bool monospace
 property real from; property real to; property real stepSize
 property var value; property var currentValue; property var options
 signal clicked(); signal selected(var value); signal editingFinished()
}
''')
            write(root, 'qmldir', '\n'.join('singleton ' + n + ' 1.0 ' + n + '.qml'
                                           for n in ('Config', 'Translation', 'BarLayout', 'BarWidgetCatalog')))
            write(root, 'tst_form.qml', '''import QtQuick
import QtTest
Item {
 width: 600; height: 1200
 BarWidgetOptionsForm { id: form; width: 560; orientation: "horizontal"; item: ({uid:"ws",type:"workspaces"}) }
 TestCase {
  name: "PreviewOptionsForm"; when: windowShown
  function row(key) { return findChild(form, "bar-option-"+key); }
  function shown(key, expected) { tryCompare(row(key), "active", expected); compare(row(key).visible, expected); }
  function test_dependencies_and_preserved_preferences() {
   shown("showPreviews",true); shown("hidePreviewOnLeave",true);
   shown("hidePreviewOnFlick",true); shown("flickSpeed",true);
   row("flickSpeed").item.value=420;
   compare(Config.options.bar.workspaces.flickSpeed,420);
   row("hidePreviewOnFlick").item.clicked();
   shown("flickSpeed",false);
   row("hidePreviewOnFlick").item.clicked(); shown("flickSpeed",true);
   row("hidePreviewOnLeave").item.selected(true);
   compare(Config.options.bar.workspaces.hidePreviewOnLeave,true);
   shown("hidePreviewOnFlick",false); shown("flickSpeed",false);
   verify(row("hidePreviewOnLeave").item.description.indexOf("cannot enter")>=0);
   row("showPreviews").item.clicked();
   shown("hidePreviewOnLeave",false); shown("hidePreviewOnFlick",false); shown("flickSpeed",false);
   compare(Config.options.bar.workspaces.flickSpeed,420);
   row("showPreviews").item.clicked();
   shown("hidePreviewOnLeave",true); shown("hidePreviewOnFlick",false);
   compare(row("hidePreviewOnLeave").item.currentValue,true);
   row("hidePreviewOnLeave").item.selected(false);
   shown("hidePreviewOnFlick",true); shown("flickSpeed",true);
   compare(row("flickSpeed").item.value,420);
   verify(row("hidePreviewOnLeave").item.description.indexOf("select a window")>=0);
  }
 }
}
''')
            run_qt(root)


if __name__ == '__main__':
    unittest.main()
