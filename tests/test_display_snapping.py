"""Arrangement snapping: the rules come from the tools people already judge usable.

The math runs as the real singleton inside Quickshell, driven by synthetic display
rectangles. The canvas wiring is checked as a contract, because committing a layout needs a
compositor.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
SNAPPING = SHELL / 'modules/common/functions/DisplaySnapping.qml'
QUICKSHELL = shutil.which('quickshell')

BOXES = [
    {"name": "HDMI-A-1", "x": 0, "y": 0, "width": 2560, "height": 1440},
    {"name": "eDP-1", "x": 0, "y": 1440, "width": 1512, "height": 1008},
]
MOVING = {"width": 1512, "height": 1008}

QML = """import QtQuick
import Quickshell
import qs.modules.common.functions
ShellRoot {
 readonly property var boxes: __BOXES__
 readonly property var moving: __MOVING__
 readonly property var bounds: ({ x: 0, y: 0, width: 2560, height: 2448 })
 function fail(code, label) { console.error("TEST " + label); Qt.exit(code); }
 function has(list, value) { return list.indexOf(value) >= 0; }
 Timer { running: true; onTriggered: {
  const t = DisplaySnapping.targets(boxes, "eDP-1", moving, bounds);
  // Flush on either side of the neighbour, plus the middle of it: three points per side.
  if (!has(t.x, 0) || !has(t.x, 2560) || !has(t.x, 2560 - 1512) || !has(t.x, -1512)
      || !has(t.x, Math.round(2560 / 2 - 1512 / 2))) fail(2, "x targets " + JSON.stringify(t.x));
  if (!has(t.y, 1440) || !has(t.y, 1440 - 1008) || !has(t.y, 0)
      || !has(t.y, Math.round(1440 / 2 - 1008 / 2))) fail(3, "y targets " + JSON.stringify(t.y));

  // Each axis snaps on its own, so a shorter display can slide along a taller one.
  const side = DisplaySnapping.suggest(boxes, "eDP-1", moving, 2558, 1700, 6, bounds);
  if (side.x !== 2560 || side.y !== 1700) fail(4, "per-axis " + JSON.stringify(side));
  if (!side.guide || side.guide.x !== 2560 || side.guide.y !== null) fail(5, "guide " + JSON.stringify(side.guide));

  // The nearest target wins, and a value outside the tolerance stays free.
  const near = DisplaySnapping.suggest(boxes, "eDP-1", moving, 4, 4, 6, bounds);
  if (near.x !== 0 || near.y !== 0) fail(6, "nearest " + JSON.stringify(near));
  const far = DisplaySnapping.suggest(boxes, "eDP-1", moving, 40, 40, 6, bounds);
  if (far.x !== 40 || far.y !== 40 || far.aligned) fail(11, "far " + JSON.stringify(far));

  // Unequal heights can be centred on the neighbour (the complaint about Windows).
  const centre = DisplaySnapping.suggest(boxes, "eDP-1", moving, 2560, 218, 6, bounds);
  if (centre.y !== Math.round(1440 / 2 - 1008 / 2)) fail(7, "centre " + JSON.stringify(centre));

  // Alt (tolerance 0) drops it exactly where the pointer was.
  const exact = DisplaySnapping.suggest(boxes, "eDP-1", moving, 1234, 567, 0, bounds);
  if (exact.x !== 1234 || exact.y !== 567 || exact.aligned) fail(8, "exact " + JSON.stringify(exact));

  // Nothing to snap to: a lone display stays free.
  const alone = DisplaySnapping.suggest([boxes[0]], "HDMI-A-1",
      { width: 1000, height: 800 }, 500, 500, 6, null);
  if (alone.x !== 500 || alone.y !== 500) fail(9, "alone " + JSON.stringify(alone));

  // The tolerance is stated in widget pixels, not desktop pixels.
  if (!(DisplaySnapping.widgetTolerance >= 4 && DisplaySnapping.widgetTolerance <= 12))
   fail(10, "tolerance " + DisplaySnapping.widgetTolerance);
  Qt.quit();
 } }
}
"""


def isolated_env(root):
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
           'QT_QPA_PLATFORMTHEME': 'generic', 'QT_LOGGING_TO_CONSOLE': '1',
           'QT_LOGGING_RULES': '*.warning=true;*.critical=true'}
    for variable, directory in (('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'),
                                ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'state'),
                                ('XDG_DATA_HOME', 'data'), ('XDG_RUNTIME_DIR', 'runtime')):
        path = root / directory
        path.mkdir(mode=0o700, exist_ok=True)
        env[variable] = str(path)
    env.pop('WAYLAND_DISPLAY', None)
    env.pop('DISPLAY', None)
    env['DBUS_SESSION_BUS_ADDRESS'] = 'unix:path=' + str(root / 'absent-bus')
    return env


class DisplaySnappingTests(unittest.TestCase):
    @unittest.skipUnless(QUICKSHELL, 'Quickshell is not installed')
    def test_snap_targets_and_rules_in_the_real_runtime(self):
        with tempfile.TemporaryDirectory(prefix='velora-snapping-') as name:
            root = Path(name)
            (root / 'modules/common/functions').mkdir(parents=True)
            shutil.copy2(SNAPPING, root / 'modules/common/functions/DisplaySnapping.qml')
            (root / 'modules/common/qmldir').write_text('module qs.modules.common\n')
            (root / 'modules/common/functions/qmldir').write_text(
                'module qs.modules.common.functions\nsingleton DisplaySnapping 1.0 DisplaySnapping.qml\n')
            (root / 'shell.qml').write_text(QML.replace('__BOXES__', json.dumps(BOXES))
                                            .replace('__MOVING__', json.dumps(MOVING)))
            result = subprocess.run([QUICKSHELL, '-p', str(root / 'shell.qml')], env=isolated_env(root),
                                    capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertNotIn('TEST ', output, output)
            self.assertEqual(result.returncode, 0, output)
            for noise in ('TypeError', 'ReferenceError'):
                self.assertNotIn(noise, output, output)

    def test_canvas_uses_the_shared_rules(self):
        canvas = (SHELL / 'modules/settings/DisplaysConfig.qml').read_text()
        self.assertIn('DisplaySnapping.suggest(', canvas)
        self.assertIn('DisplaySnapping.targets(', canvas)
        self.assertIn('readonly property real snapPx: DisplaySnapping.widgetTolerance', canvas)
        # Tolerance is converted from widget pixels through the zoom, so the feel is
        # the same on a small canvas and a huge desktop.
        self.assertIn('exact ? 0 : snapPx / zoom', canvas)
        self.assertIn('(mouse.modifiers & Qt.AltModifier) !== 0', canvas)
        self.assertIn('function commit(name, x, y)', canvas)
        self.assertNotIn('function drop(', canvas)
        # Pixel-precise placement, which KDE users ask for and the canvas could not do.
        self.assertIn('Keys.onPressed: (event) => {', canvas)
        self.assertIn('arrangement.applyNudge()', canvas)
        self.assertIn('interval: 350', canvas)
        # Feedback: the line it will land on is drawn while dragging.
        self.assertIn('arrangement.drag?.guide?.x', canvas)

    def test_snapping_is_documented_and_translated(self):
        canvas = (SHELL / 'modules/settings/DisplaysConfig.qml').read_text()
        label = ("A display snaps to a neighbour's edge or middle. Hold Alt to drop it exactly "
                 "where you let go, and use the arrow keys (Shift for 10 px) to line one up "
                 "pixel by pixel.")
        self.assertIn(f'Translation.tr("{label}")', canvas)
        russian = json.loads((SHELL / 'translations/ru_RU.json').read_text())
        self.assertTrue(russian.get(label, '').strip())


if __name__ == '__main__':
    unittest.main()
