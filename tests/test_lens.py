"""Lens QML behavior, independent of the real desktop and private index."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_connectivity_qml import production, write_common, write_singletons, QT_TEST_RUNNER, SHELL, PROJECT


@unittest.skipUnless(QT_TEST_RUNNER, 'Qt Quick Test unavailable')
class LensQmlTests(unittest.TestCase):
    def test_query_lifecycle_and_lock(self):
        with tempfile.TemporaryDirectory(prefix='lens-qml-') as directory:
            root = Path(directory)
            write_common(root)
            write_singletons(root, {
                'Config': 'property bool ready: true; property var options: ({search:{lens:{enabled:true}}})',
                'GlobalStates': 'property bool screenLocked: false',
                'PowerSaving': 'property bool onBattery: true',
                'AppSearch': 'property var list: []',
                'TestLauncher': 'property var urls: []; property var apps: []; function openUrlExternally(url) { urls = urls.concat([url]); return true; }',
            })
            (root / 'IdleMonitor.qml').write_text('import QtQuick\nQtObject { property bool enabled; property real timeout; property bool isIdle: false }')
            (root / 'Lens.qml').write_text(production('services/Lens.qml', [
                ('id: root\n', 'id: root\n    readonly property var process: bridge\n    readonly property var semanticTimer: semanticDelay\n    readonly property var setupStatusProcess: setupProbe\n    readonly property var setupActionProcess: setupControl\n'),
                ('Qt.openUrlExternally(', 'TestLauncher.openUrlExternally('),
            ]))
            with (root / 'qmldir').open('a') as stream:
                stream.write('singleton Lens 1.0 Lens.qml\n')
            shutil.copy2(PROJECT / 'tests/qml/tst_lens.qml', root)
            run = subprocess.run([QT_TEST_RUNNER, '-input', str(root / 'tst_lens.qml'), '-o', '-,txt'],
                                 env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'generic', 'QT_QUICK_BACKEND': 'software'},
                                 capture_output=True, text=True, timeout=45)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertNotIn('ReferenceError', run.stdout + run.stderr)
            self.assertNotIn('TypeError', run.stdout + run.stderr)

    def test_translations(self):
        russian = json.loads((SHELL / 'translations/ru_RU.json').read_text())
        sources = ['services/Lens.qml', 'modules/settings/SearchConfig.qml', 'modules/settings/LensSettings.qml']
        missing = set()
        for path in sources:
            for text in re.findall(r'Translation\.tr\("([^"\\]*)"\)', (SHELL / path).read_text()):
                if text not in russian:
                    missing.add(text)
        self.assertEqual(sorted(missing), [])
