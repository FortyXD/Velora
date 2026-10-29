"""Camera right-click and locale-independent section deep links; no capture or live config."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
QS = shutil.which('qs')


def block(source, marker):
    """Use the production QML functions/timer, not a second implementation."""
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError('Unclosed QML block: ' + marker)


class RecordingSettingsLinkTests(unittest.TestCase):
    def run_qml(self, root, source, env=None):
        (root / 'shell.qml').write_text(source)
        result = subprocess.run(
            [QS, '-p', str(root / 'shell.qml'), '--no-color'],
            env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', **(env or {})},
            capture_output=True, text=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('SETTINGS_LINK_PASS', result.stdout + result.stderr)

    def test_camera_wiring_and_startup_section_route(self):
        source = (SHELL / 'modules/ii/bar/widgets/UtilButton.qml').read_text()
        camera = source.split('property Component screenRecord: Component {', 1)[1].split('property Component colorPicker:', 1)[0]
        self.assertIn('onClicked: ScreenRecorder.toggle()', camera)
        self.assertIn('altAction: () => ScreenRecorder.openSettings()', camera)
        self.assertIn('Right-click for recording settings', camera)
        tools = (SHELL / 'modules/settings/ToolsConfig.qml').read_text()
        self.assertIn('objectName: "screen-recording"', tools)
        startup = block((SHELL / 'settings.qml').read_text(), 'Component.onCompleted: {\n        MaterialThemeLoader')
        self.assertIn('root.openPage(startKey, Quickshell.env("QS_SETTINGS_SECTION") ?? "")', startup)

    @unittest.skipUnless(QS, 'Quickshell runtime is not installed')
    def test_service_opens_exact_section_without_changing_recording(self):
        with tempfile.TemporaryDirectory(prefix='velora settings link ') as directory:
            root = Path(directory)
            for path in ('services', 'modules/common/functions', 'bin'):
                (root / path).mkdir(parents=True, exist_ok=True)
            shutil.copy2(SHELL / 'services/ScreenRecorder.qml', root / 'services/ScreenRecorder.qml')
            (root / 'GlobalStates.qml').write_text(
                'pragma Singleton\nimport QtQuick\nimport Quickshell\nSingleton { property bool regionSelectorOpen: false; property bool overlayOpen: false; function closeSidebars() {} }')
            (root / 'modules/common/Config.qml').write_text(
                'pragma Singleton\nimport Quickshell\nSingleton { property var options: ({screenRecord:{savePath:""}}) }')
            backend = root / 'record.sh'
            backend.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> ' + json.dumps(str(root / 'backend-calls'))
                               + '\necho \'{"state":"recording","startedAt":1}\'\n')
            backend.chmod(0o755)
            (root / 'modules/common/Directories.qml').write_text(
                'pragma Singleton\nimport Quickshell\nSingleton { property string recordScriptPath: '
                + json.dumps(str(backend)) + '; property string home: "file:///tmp"; property string videos: "file:///tmp/Videos" }')
            (root / 'services/Translation.qml').write_text(
                'pragma Singleton\nimport Quickshell\nSingleton { function tr(text) { return text; } }')
            (root / 'modules/common/functions/FileUtils.qml').write_text(
                'pragma Singleton\nimport Quickshell\nSingleton { function trimFileProtocol(text) { return text.replace("file://", ""); } }')
            launcher = root / 'bin/qs'
            launcher.write_text('#!/usr/bin/env python3\nimport json, os, pathlib, sys\n'
                                + 'pathlib.Path(' + repr(str(root / 'launch.json')) + ').write_text(json.dumps(dict('
                                + 'args=sys.argv[1:], page=os.environ.get("QS_SETTINGS_PAGE"), '
                                + 'section=os.environ.get("QS_SETTINGS_SECTION"), search=os.environ.get("QS_SETTINGS_SEARCH"))))\n')
            launcher.chmod(0o755)
            self.run_qml(root, '''import QtQuick
import Quickshell
import qs.services
Scope {
    id: root
    property bool unchanged: false
    Component.onCompleted: {
        ScreenRecorder.phase = "recording";
        ScreenRecorder.openSettings();
        unchanged = ScreenRecorder.recording;
    }
    Timer { interval: 700; running: true; onTriggered: {
        console.log(root.unchanged && ScreenRecorder.recording ? "SETTINGS_LINK_PASS" : "SETTINGS_LINK_FAIL"); Qt.quit();
    } }
}''', {'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'], 'QS_SETTINGS_SEARCH': 'inherited search'})
            launch = json.loads((root / 'launch.json').read_text())
            self.assertEqual(launch, dict(args=['-p', str(root / 'settings.qml')], page='tools', section='screen-recording', search=''))
            self.assertTrue(all(line == 'status' for line in (root / 'backend-calls').read_text().splitlines()))

    @unittest.skipUnless(QS, 'Quickshell runtime is not installed')
    def test_section_reveal_waits_for_page_and_ignores_translation(self):
        source = (SHELL / 'settings.qml').read_text()
        production = '\n'.join(block(source, marker) for marker in (
            'function openPage(', 'function findSection(', 'Timer { // Waits for the page',
            'Timer { // Corrects the position'))
        with tempfile.TemporaryDirectory(prefix='velora-settings-anchor-') as directory:
            root = Path(directory)
            self.run_qml(root, '''import QtQuick
import Quickshell
Scope {
    id: root
    property bool loaded: false
    property int current: -1
    property int reveals: 0
    property var revealedItem: null
    property string failure: ""
    function check(ok, message) { if (!ok) failure += message + ";"; }
    function pageIndex(key) { return key === "tools" ? 0 : -1; }
    function setPage(index) { root.current = index; }
    function pageItemAt(index) { return root.loaded && index === 0 ? page : null; }
    Item {
        id: page
        function revealItem(item, highlight = true) { root.revealedItem = item; root.reveals++; }
        Item { id: section; height: 100; objectName: "screen-recording"; property bool settingsSection: true; property string title: "Запись экрана" }
    }
''' + production + '''
    Component.onCompleted: root.openPage("tools", "screen-recording")
    Timer { interval: 350; running: true; onTriggered: root.loaded = true }
    Timer { interval: 720; running: true; onTriggered: {
        root.check(root.current === 0 && root.revealedItem === section, "lazy page was not revealed");
        root.check(root.findSection(page, "Запись экрана") === section, "existing title lookup regressed");
        section.title = "Screen recording";
        root.openPage("tools", "screen-recording");
    } }
    Timer { interval: 1500; running: true; onTriggered: {
        root.check(root.revealedItem === section && root.reveals >= 3, "stable anchor depends on translation");
        root.openPage("tools", "missing-section");
        revealTimer.attemptsRemaining = 2;
    } }
    Timer { interval: 2000; running: true; onTriggered: {
        root.check(!revealTimer.running && revealTimer.attemptsRemaining === 0, "missing anchor retries are unbounded");
        console.log(root.failure ? "SETTINGS_LINK_FAIL:" + root.failure : "SETTINGS_LINK_PASS"); Qt.quit();
    } }
}''')


if __name__ == '__main__':
    unittest.main()
