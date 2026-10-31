"""The shell's side of velora-connectivityd, in Qt Quick Test with stand-ins for everything around it."""
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
TOOLS = PROJECT / 'tools'
QT_TEST_RUNNER = shutil.which('qmltestrunner6') or next(
    (str(path) for path in (Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner'))
     if path.is_file()), None)
REQUIRED = os.environ.get('VELORA_REQUIRE_CONNECTIVITY_TESTS') == '1'


def production(path, replacements=()):
    """A shell file without its imports of the things these tests stand in for."""
    source = '\n'.join(line for line in (SHELL / path).read_text().splitlines()
                       if not line.startswith(('import qs', 'import Quickshell')))
    for old, new in replacements:
        if old not in source:
            raise AssertionError(f'{path} no longer has: {old}')
        source = source.replace(old, new)
    return source


def write_singletons(root, singletons):
    for name, body in singletons.items():
        (root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}\n')
    with (root / 'qmldir').open('a') as file:
        file.write(''.join(f'singleton {name} 1.0 {name}.qml\n' for name in singletons))


def write_common(root):
    (root / 'Singleton.qml').write_text('import QtQuick\nQtObject { default property list<QtObject> content }\n')
    (root / 'Process.qml').write_text(
        'import QtQuick\nQtObject { property bool running; property var command; property bool stdinEnabled; '
        'property QtObject stdout; property var writes: []; signal exited(int exitCode, int exitStatus); '
        'function write(text) { writes = writes.concat([text]); } }\n')
    (root / 'SplitParser.qml').write_text('import QtQuick\nQtObject { signal read(string data) }\n')
    write_singletons(root, {
        'Quickshell': 'property var commands: []; function execDetached(command) { commands = commands.concat([command]); } function shellPath(path) { return "/shell/" + path; }',
        'Translation': 'function tr(text) { return text; }',
    })


@unittest.skipUnless(QT_TEST_RUNNER or REQUIRED, 'Qt 6 Quick Test is not installed')
class ConnectivityQmlTests(unittest.TestCase):
    def run_tests(self, root, test_file):
        shutil.copy2(PROJECT / 'tests/qml' / test_file, root)
        result = subprocess.run(
            [QT_TEST_RUNNER, '-input', str(root / test_file), '-o', '-,txt'],
            env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'generic',
                 'QT_QUICK_BACKEND': 'software', 'FONTCONFIG_FILE': '/etc/fonts/fonts.conf'},
            capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Totals:', result.stdout)
        self.assertNotIn('ReferenceError', result.stdout + result.stderr)
        self.assertNotIn('TypeError', result.stdout + result.stderr)

    def test_backend(self):
        with tempfile.TemporaryDirectory(prefix='velora-connectivity-') as directory:
            root = Path(directory)
            write_common(root)
            (root / 'ConnectivityBackend.qml').write_text(production('services/ConnectivityBackend.qml', [
                ('id: root\n', 'id: root\n    readonly property var process: daemon\n    readonly property var restarts: restartTimer\n'),
            ]))
            with (root / 'qmldir').open('a') as file:
                file.write('singleton ConnectivityBackend 1.0 ConnectivityBackend.qml\n')
            self.run_tests(root, 'tst_connectivity_backend.qml')

    def test_network_service(self):
        with tempfile.TemporaryDirectory(prefix='velora-connectivity-') as directory:
            root = Path(directory)
            write_common(root)
            write_singletons(root, {
                'ConnectivityBackend': 'property var network: ({}); property string problem: ""; property var calls: []; '
                'function call(method, params, done) { calls = calls.concat([{ method, params, done }]); }',
            })
            (root / 'Network.qml').write_text(production('services/Network.qml'))
            (root / 'WifiAccessPoint.qml').write_text(production('services/network/WifiAccessPoint.qml'))
            with (root / 'qmldir').open('a') as file:
                file.write('singleton Network 1.0 Network.qml\nWifiAccessPoint 1.0 WifiAccessPoint.qml\n')
            self.run_tests(root, 'tst_connectivity_network.qml')


    def test_profile_editor(self):
        with tempfile.TemporaryDirectory(prefix='velora-connectivity-') as directory:
            root = Path(directory)
            write_common(root)
            write_singletons(root, {
                'ConnectivityBackend': 'property var calls: []; function call(method, params, done) { calls = calls.concat([{ method, params, done }]); }',
            })
            (root / 'ProfileEditor.qml').write_text(production('services/ProfileEditor.qml'))
            with (root / 'qmldir').open('a') as file:
                file.write('singleton ProfileEditor 1.0 ProfileEditor.qml\n')
            self.run_tests(root, 'tst_connectivity_editor.qml')

    def test_bluetooth_manager_and_prompts(self):
        with tempfile.TemporaryDirectory(prefix='velora-connectivity-') as directory:
            root = Path(directory)
            write_common(root)
            write_singletons(root, {
                'ConnectivityBackend': 'property var bluetooth: ({}); property bool ready: true; property var calls: []; signal event(string name, var data); '
                'function call(method, params, done) { calls = calls.concat([{ method, params, done }]); }',
            })
            for name in ('BluetoothManager', 'ConnectivityPrompts'):
                (root / f'{name}.qml').write_text(production(f'services/{name}.qml'))
            with (root / 'qmldir').open('a') as file:
                file.write('singleton BluetoothManager 1.0 BluetoothManager.qml\nsingleton ConnectivityPrompts 1.0 ConnectivityPrompts.qml\n')
            self.run_tests(root, 'tst_connectivity_bluetooth.qml')


class ConnectivitySourceTests(unittest.TestCase):
    def shell_files(self):
        return [path for pattern in ('*.qml', '*.sh', '*.py') for path in SHELL.rglob(pattern)]

    def test_nothing_in_the_shell_calls_nmcli(self):
        offenders = [str(path.relative_to(SHELL)) for path in self.shell_files()
                     if 'nmcli' in path.read_text(errors='ignore')]
        self.assertEqual(offenders, [], 'the shell reaches NetworkManager through velora-connectivityd only')

    def test_settings_pages_lead_to_our_own_pages_not_to_kde(self):
        # The setting itself stays in Config.qml, so an existing configuration file still loads
        # Sidebar shortcuts can also open external settings with the right mouse button.
        offenders = [str(path.relative_to(SHELL)) for path in (SHELL / 'modules/settings').rglob('*.qml')
                     if path.name != 'Config.qml' and re.search(r'apps\.(network|bluetooth)|kcm_(networkmanagement|bluetooth)', path.read_text())]
        self.assertEqual(offenders, [])

    def test_every_new_string_is_in_the_russian_translation(self):
        russian = json.loads((SHELL / 'translations/ru_RU.json').read_text())
        files = ['services/Network.qml', 'services/ProfileEditor.qml', 'services/BluetoothManager.qml', 'services/ConnectivityPrompts.qml',
                 'modules/settings/WifiConfig.qml', 'modules/settings/ConnectionsConfig.qml', 'modules/settings/ConnectionEditorConfig.qml',
                 'modules/settings/BluetoothConfig.qml', 'modules/settings/BluetoothDeviceConfig.qml', 'modules/settings/BluetoothOptionsConfig.qml']
        files += [str(path.relative_to(SHELL)) for path in (SHELL / 'modules/settings/network').glob('*.qml')]
        missing = set()
        for name in files:
            source = (SHELL / name).read_text()
            missing |= {key for key in re.findall(r'Translation\.tr\("((?:[^"\\]|\\.)*)"\)', source) if key not in russian}
        self.assertEqual(sorted(missing), [])

    def test_every_message_from_the_daemon_is_in_the_russian_translation(self):
        russian = json.loads((SHELL / 'translations/ru_RU.json').read_text())
        sources = [TOOLS / 'velora-connectivityd/src/nm/reasons.rs', TOOLS / 'velora-connectivityd/src/bluez/client.rs', TOOLS / 'velora-connectivityd/src/bluez/obex.rs']
        messages = set()
        for path in sources:
            text = path.read_text().split('#[cfg(test)]')[0]
            messages |= set(re.findall(r'(?:ApiError::new\(ErrorCode::\w+, |ApiError::invalid\(|=> |ErrorCode::\w+, )"([A-Z][^"]+)"', text))
        messages |= set(re.findall(r'"([A-Z][a-zA-Z -]+)"', (TOOLS / 'velora-connectivityd/src/bluez/model.rs').read_text().split('pub fn service_name')[1].split('pub fn device_type')[0]))
        self.assertGreater(len(messages), 40)
        self.assertEqual(sorted(message for message in messages if message not in russian), [])

    def test_the_old_snapshot_script_is_gone(self):
        self.assertFalse((SHELL / 'scripts/network/wifi_snapshot.py').exists())

    def test_passwords_only_travel_through_the_backends_stdin(self):
        source = (SHELL / 'services/ConnectivityBackend.qml').read_text()
        self.assertIn('daemon.write(JSON.stringify(', source)
        self.assertNotRegex(source, r'execDetached\([^)]*(password|params)')
        self.assertNotRegex(source, r'command: \[[^\]]*(password|params)')
        network = (SHELL / 'services/Network.qml').read_text()
        self.assertNotIn('Process', network)
        self.assertNotRegex(network, r'execDetached\([^)]*password')


if __name__ == '__main__':
    unittest.main()
