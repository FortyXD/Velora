"""Real Quickshell Network + shared form, with an isolated JSONL peer."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / 'dots/.config/quickshell/ii'
ENV = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
       'QT_LOGGING_RULES': '*.warning=true;*.critical=true', 'QT_LOGGING_TO_CONSOLE': '1'}


def write(root, path, text):
    file = root / path
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(text)


def prepare_fixture(root):
    for file in ('services/Network.qml', 'services/network/WifiAccessPoint.qml', 'modules/settings/network/PasswordForm.qml'):
        write(root, file, (SHELL / file).read_text())
    write(root, 'services/qmldir', 'module qs.services\nsingleton Network 1.0 Network.qml\nsingleton Translation 1.0 Translation.qml\n')
    write(root, 'services/Translation.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function tr(s) { return s; } }')
    write(root, 'services/network/qmldir', 'module qs.services.network\nWifiAccessPoint 1.0 WifiAccessPoint.qml\n')
    write(root, 'modules/common/qmldir', 'module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\n')
    write(root, 'modules/common/Appearance.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var colors: ({colPrimary:'#89b4fa',colSubtext:'#777777',colSecondaryContainer:'#34344a',colOnSecondaryContainer:'#ffffff',colOnLayer3:'#ffffff',colLayer3:'#222233',colLayer3Hover:'#333344',colError:'#ff7777',colPrimaryHover:'#99ccff',colPrimaryActive:'#6699cc',colOnPrimary:'#111122'})
 property var font: ({pixelSize:{smaller:12,small:14},family:{main:'Sans Serif'}})
 property var rounding: ({small:8,full:999})
}''')
    write(root, 'modules/common/widgets/qmldir', 'module qs.modules.common.widgets\nRippleButton 1.0 RippleButton.qml\nDialogButton 1.0 DialogButton.qml\nStyledText 1.0 StyledText.qml\nMaterialSymbol 1.0 MaterialSymbol.qml\nStyledToolTip 1.0 StyledToolTip.qml\n')
    write(root, 'modules/common/widgets/RippleButton.qml', '''import QtQuick
import QtQuick.Controls
Button { property bool toggled:false; property real buttonRadius; property color colBackgroundToggled; property color colBackgroundToggledHover }
''')
    write(root, 'modules/common/widgets/DialogButton.qml', '''import QtQuick
import QtQuick.Controls
Button { property string buttonText; text:buttonText; property color colBackground; property color colBackgroundHover; property color colRipple; property color colEnabled }
''')
    write(root, 'modules/common/widgets/StyledText.qml', 'import QtQuick\nText {}')
    write(root, 'modules/common/widgets/MaterialSymbol.qml', 'import QtQuick\nText { property real iconSize; font.pixelSize:iconSize }')
    write(root, 'modules/common/widgets/StyledToolTip.qml', 'import QtQuick.Controls\nToolTip {}')
    write(root, 'scripts/network/wifi_agent.py', (ROOT / 'tests/fixtures/wifi_backend.py').read_text())
    write(root, 'scripts/network/wifi_snapshot.py', '''import json
print(json.dumps({'networks':[{'key':'offline\\npersonal','ssid':'offline','bssid':'00:00:00:00:00:01','strength':65,'frequency':2412,'active':False,'security':'WPA2','savedUuid':'','joinedBefore':False}],'saved':[],'error':''}))
''')
    # Every nmcli call, including monitor and automatic scans, stays in the fixture.
    write(root, 'bin/nmcli', '''#!/usr/bin/env python3
import sys,time
args=sys.argv[1:]
if args==['monitor']:
 time.sleep(30)
elif args==['radio','wifi']:
 print('enabled')
elif 'CONNECTIVITY' in ' '.join(args):
 print('wifi:disconnected\\nnone')
''')
    (root / 'bin/nmcli').chmod(0o755)


class WifiUiTests(unittest.TestCase):
    @unittest.skipUnless(Path('/usr/lib/qt6/bin/qmltestrunner').exists(), 'Qt Quick Test unavailable')
    def test_real_form_keyboard_reveal_and_cancel_focus(self):
        with tempfile.TemporaryDirectory(prefix='velora-wifi-form-') as name:
            root = Path(name)
            prepare_fixture(root)
            write(root, 'services/qmldir', 'module qs.services\nsingleton Translation 1.0 Translation.qml\n')
            (root / 'qs').symlink_to(root, target_is_directory=True)
            shutil.copy2(ROOT / 'tests/qml/tst_wifipassword.qml', root / 'tst_wifipassword.qml')
            result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-import', str(root), '-input', str(root / 'tst_wifipassword.qml'), '-o', '-,txt'],
                                    env=ENV, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('ReferenceError', result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which('quickshell'), 'Quickshell unavailable')
    def test_production_service_form_retry_hidden_cancel_and_restart(self):
        with tempfile.TemporaryDirectory(prefix='velora-wifi-ui-') as name:
            root = Path(name)
            prepare_fixture(root)
            shutil.copy2(ROOT / 'tests/qml/wifi_service.qml', root / 'shell.qml')
            result = subprocess.run(['quickshell', '-p', str(root)], env={**ENV, 'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH']},
                                    capture_output=True, text=True, timeout=18)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('WIFI SERVICE CHECKS PASSED', output)
            for forbidden in ('WIFI TEST', 'ReferenceError', 'TypeError', 'credential-sentinel'):
                self.assertNotIn(forbidden, output)
            records = [json.loads(line) for line in (root / 'scripts/network/protocol-checks.jsonl').read_text().splitlines()]
            self.assertEqual(sum(item.get('started', False) for item in records), 2)
            self.assertTrue(all(item.get('safe_argv', True) and item.get('safe_environment', True) and item.get('secret_ok', True) for item in records))
            self.assertTrue(any(item.get('hidden') and item.get('security') == 'sae' for item in records))
            self.assertEqual(sum(item.get('cancelled', False) for item in records), 2)


if __name__ == '__main__':
    unittest.main()
