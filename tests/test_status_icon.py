"""Regression coverage for upright network glyphs and independent activity rings."""
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
if not QT_TEST_RUNNER and shutil.which('qtpaths6'):
    qt_bins = subprocess.check_output(['qtpaths6', '--query', 'QT_INSTALL_BINS'], text=True).strip()
    candidate = Path(qt_bins) / 'qmltestrunner'
    if candidate.is_file():
        QT_TEST_RUNNER = str(candidate)


class StatusIconTests(unittest.TestCase):
    def test_network_surfaces_never_rotate_the_status_glyph(self):
        for relative in (
            'modules/ii/bar/widgets/NetworkIndicator.qml',
            'modules/ii/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml',
            'modules/ii/sidebarRight/wifiNetworks/WifiNetworkItem.qml',
            'modules/settings/network/ConnectionHeader.qml',
            'modules/settings/network/WifiNetworkRow.qml',
            'modules/settings/WifiConfig.qml',
        ):
            with self.subTest(file=relative):
                source = (SHELL / relative).read_text()
                self.assertIn('StatusIcon {', source)
                self.assertNotIn('RotationAnimation on rotation', source)
        source = (SHELL / 'services/Network.qml').read_text()
        self.assertIn('root.wifiConnecting ? "wifi"', source)
        indicator = (SHELL / 'modules/ii/bar/widgets/NetworkIndicator.qml').read_text()
        self.assertIn('busy: Network.wifiConnecting && !Network.ethernet', indicator)
        self.assertNotIn('wifiScanning', indicator)

    @unittest.skipUnless(QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
    def test_activity_transitions_in_qt(self):
        with tempfile.TemporaryDirectory(prefix='velora-status-icon-') as directory:
            root = Path(directory)
            shutil.copy2(SHELL / 'modules/common/widgets/StatusIcon.qml', root)
            # Isolate the actual production animation from shell singletons and
            # NetworkManager. Text has the same transform/visibility semantics.
            (root / 'MaterialSymbol.qml').write_text(
                'import QtQuick\nText { property real iconSize: 24; property real fill: 0; font.pixelSize: iconSize }\n')
            shutil.copy2(PROJECT / 'tests/qml/tst_statusicon.qml', root)
            result = subprocess.run(
                [QT_TEST_RUNNER, '-input', str(root), '-o', '-,txt'],
                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
                     'QT_LOGGING_RULES': '*.warning=true;*.critical=true', 'QT_LOGGING_TO_CONSOLE': '1'},
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
