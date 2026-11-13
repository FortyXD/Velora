"""Capture policy and window-close lifecycle, without a compositor or real windows."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from PIL import Image

from test_connectivity_qml import production, write_common, write_singletons, QT_TEST_RUNNER, PROJECT


@unittest.skipUnless(QT_TEST_RUNNER, 'Qt Quick Test unavailable')
class WindowThumbnailTests(unittest.TestCase):
    def test_capture_policy_and_close_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix='velora-thumbnails-') as directory:
            root = Path(directory)
            write_common(root)
            Image.new('RGB', (280, 140), 'red').save(root / 'frame-red.png')
            Image.new('RGB', (280, 140), 'blue').save(root / 'frame-blue.png')
            write_singletons(root, {
                'Quickshell': 'function iconPath(name, fallback) { return ""; } function shellPath(path) { return "/shell/" + path; }',
                'Appearance': 'property var colors: ({colLayer1:"#222222"})',
                'GlobalStates': 'property bool screenLocked: false',
                'HyprlandData': 'property string identifier: ""; function clientForToplevel(toplevel) { return {stableId: identifier}; }',
                'ToplevelManager': 'property QtObject toplevels: QtObject { property var values: [] }',
            })
            (root / 'StdioCollector.qml').write_text('import QtQuick\nQtObject { property string text; signal streamFinished() }')
            (root / 'WindowPreviewPolicy.qml').write_text(production('services/WindowPreviewPolicy.qml'))
            (root / 'WindowPreviews.qml').write_text(production('services/WindowPreviews.qml'))
            with (root / 'qmldir').open('a') as stream:
                stream.write('singleton WindowPreviewPolicy 1.0 WindowPreviewPolicy.qml\n')
                stream.write('singleton WindowPreviews 1.0 WindowPreviews.qml\n')
            (root / 'WindowThumbnail.qml').write_text(production('modules/common/widgets/WindowThumbnail.qml'))
            (root / 'WindowPreviewPool.qml').write_text(production('modules/common/widgets/WindowPreviewPool.qml'))
            (root / 'ScreencopyView.qml').write_text('''import QtQuick
Item {
    objectName: "captureBackend"
    property var captureSource: null
    property bool live: false
    property bool paintCursor: false
    property size constraintSize: Qt.size(0, 0)
    readonly property size sourceSize: Qt.size(640, 360)
    readonly property bool hasContent: !!captureSource
    property int requests: 0
    implicitWidth: 160; implicitHeight: 90
    onCaptureSourceChanged: { if (captureSource) requests++; }
    function captureFrame() { if (captureSource) requests++; }
}
''')
            shutil.copy2(PROJECT / 'tests/qml/tst_window_thumbnails.qml', root)
            result = subprocess.run([QT_TEST_RUNNER, '-input', str(root / 'tst_window_thumbnails.qml'), '-o', '-,txt'],
                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'generic', 'QT_QUICK_BACKEND': 'software'},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('ReferenceError', result.stdout + result.stderr)
            self.assertNotIn('TypeError', result.stdout + result.stderr)
