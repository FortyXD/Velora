"""Qt-backed cover scaling and production wallpaper metadata lifecycle regressions."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
BACKGROUND = PROJECT / 'dots/.config/quickshell/ii/modules/ii/background'
QT_TEST = shutil.which('qmltestrunner6') or next((str(p) for p in (
    Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner'))
    if p.is_file()), None)
QUICKSHELL = shutil.which('quickshell') or shutil.which('qs')
ENV = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software'}


class WallpaperGeometryTests(unittest.TestCase):
    @unittest.skipUnless(QT_TEST, 'Qt 6 Quick Test unavailable')
    def test_reactive_cover_geometry_in_qt(self):
        with tempfile.TemporaryDirectory(prefix='velora-wallpaper-') as directory:
            root = Path(directory)
            shutil.copy2(BACKGROUND / 'WallpaperGeometry.qml', root)
            shutil.copy2(PROJECT / 'tests/qml/tst_wallpapergeometry.qml', root)
            result = subprocess.run([QT_TEST, '-input', str(root), '-o', '-,txt'],
                                    env=ENV, text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(QUICKSHELL, 'Quickshell unavailable')
    def test_production_metadata_lifecycle_and_resize(self):
        # Exercise the actual production properties/handlers/Process, replacing only
        # the compositor window with a ShellRoot and ImageMagick with a slow fixture.
        source = (BACKGROUND / 'Background.qml').read_text()
        geometry = source[source.index('        property int wallpaperWidth:'):
                          source.index('        readonly property bool verticalParallax:')]
        lifecycle = source[source.index('        onWallpaperPathChanged:'):
                           source.index('\n        Item {', source.index('        onWallpaperPathChanged:'))]
        with tempfile.TemporaryDirectory(prefix='velora-wallpaper-process-') as directory:
            root = Path(directory)
            shutil.copy2(BACKGROUND / 'WallpaperGeometry.qml', root)
            fake_magick = root / 'magick'
            fake_magick.write_text('''#!/usr/bin/env python3
from pathlib import Path
import sys,time
with (Path(__file__).parent/'calls').open('a') as f:f.write(sys.argv[-1]+'\\n')
time.sleep(0.15)
print({'first[0]':'3840 2160','second[0]':'1080 1920','third[0]':'640 480','invalid[0]':'0 nope'}[sys.argv[-1]])
''')
            fake_magick.chmod(0o755)
            (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 id: bgRoot
 property real width: 1920
 property real height: 1080
 property real parallaxRation: 1.07
 property string wallpaperPath: "first"
''' + geometry + lifecycle + '''
 property int phase: 0
 function check(ok, message) { if (!ok) { console.error("TEST", message); Qt.exit(2); } }
 Timer { interval: 30; running: true; repeat: true
  onTriggered: {
   phase++;
   if (phase === 2) bgRoot.wallpaperPath = "second";
   if (phase === 3) bgRoot.wallpaperPath = "third";
   if (phase === 30) {
    check(bgRoot.wallpaperWidth === 640 && bgRoot.wallpaperHeight === 480, "stale image size");
    bgRoot.width = 3440; bgRoot.height = 1440;
   }
   if (phase === 31) {
    check(bgRoot.scaledWallpaperWidth >= bgRoot.width && bgRoot.scaledWallpaperHeight >= bgRoot.height, "stale viewport scale");
    bgRoot.wallpaperPath = "invalid";
   }
   if (phase === 45) {
    check(bgRoot.wallpaperWidth === 0 && bgRoot.wallpaperHeight === 0, "invalid metadata accepted");
    check(isFinite(bgRoot.scaledWallpaperWidth) && bgRoot.scaledWallpaperWidth >= bgRoot.width, "invalid fallback");
    Qt.quit();
   }
  }
 }
}
''')
            result = subprocess.run([QUICKSHELL, '-p', str(root)],
                                    env={**ENV, 'PATH': str(root) + os.pathsep + os.environ['PATH']},
                                    text=True, capture_output=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            for error in ('TEST ', 'TypeError', 'ReferenceError', 'Failed to load configuration'):
                self.assertNotIn(error, output)
            calls = (root / 'calls').read_text().splitlines()
            self.assertEqual(calls, ['first[0]', 'third[0]', 'invalid[0]'])


if __name__ == '__main__':
    unittest.main()
