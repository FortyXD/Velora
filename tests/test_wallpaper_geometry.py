"""Qt-backed cover scaling regressions for independent wallpaper layers."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
WIDGETS = PROJECT / 'dots/.config/quickshell/ii/modules/common/widgets'
QT_TEST = shutil.which('qmltestrunner6') or next((str(p) for p in (
    Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner'))
    if p.is_file()), None)
ENV = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software', 'QT_QPA_PLATFORMTHEME': 'generic',
       'FONTCONFIG_FILE': '/etc/fonts/fonts.conf'}


class WallpaperGeometryTests(unittest.TestCase):
    @unittest.skipUnless(QT_TEST, 'Qt 6 Quick Test unavailable')
    def test_reactive_cover_geometry_in_qt(self):
        with tempfile.TemporaryDirectory(prefix='velora-wallpaper-') as directory:
            root = Path(directory)
            shutil.copy2(WIDGETS / 'WallpaperGeometry.qml', root)
            shutil.copy2(PROJECT / 'tests/qml/tst_wallpapergeometry.qml', root)
            result = subprocess.run([QT_TEST, '-input', str(root), '-o', '-,txt'],
                                    env=ENV, text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
