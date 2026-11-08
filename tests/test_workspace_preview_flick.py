"""A flicked pointer hides the workspace preview and it must not bounce back.

The math and the open/close rules run in the real Quickshell runtime against the
production singletons. The wiring (threshold, settings key, translations) is a
contract check, because the miniature itself needs the compositor to be seen.
"""
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
QUICKSHELL = shutil.which('quickshell')
FUNCTIONS = SHELL / 'modules/common/functions'


def isolated_env(root):
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
           'QT_QPA_PLATFORMTHEME': 'generic', 'FONTCONFIG_FILE': '/etc/fonts/fonts.conf',
           'QT_LOGGING_TO_CONSOLE': '1'}
    for variable, directory in (('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'),
                                ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'xdg-state'),
                                ('XDG_DATA_HOME', 'data'), ('XDG_RUNTIME_DIR', 'runtime')):
        path = root / directory
        path.mkdir(mode=0o700, exist_ok=True)
        env[variable] = str(path)
    env.pop('WAYLAND_DISPLAY', None)
    env.pop('DISPLAY', None)
    env['DBUS_SESSION_BUS_ADDRESS'] = 'unix:path=' + str(root / 'absent-bus')
    return env


def write(root, name, text):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def run_shell(root, body):
    write(root, 'modules/common/qmldir', 'module qs.modules.common\n')
    write(root, 'modules/common/functions/qmldir', 'module qs.modules.common.functions\n'
          + '\n'.join(f'singleton {name} 1.0 {name}.qml' for name in ('PointerFlick', 'PopupHoverPolicy')) + '\n')
    write(root, 'shell.qml', 'import QtQuick\nimport Quickshell\nimport qs.modules.common.functions\n'
          'ShellRoot {\n' + body + '\n}')
    result = subprocess.run([QUICKSHELL, '-p', str(root / 'shell.qml')], env=isolated_env(root),
                            capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    assert 'TEST ' not in output, output
    for noise in ('TypeError', 'ReferenceError'):
        assert noise not in output, output
    return result, output


class WorkspacePreviewFlickTests(unittest.TestCase):
    @unittest.skipUnless(QUICKSHELL, 'Quickshell is not installed')
    def test_pointer_flick_math_in_the_real_runtime(self):
        with tempfile.TemporaryDirectory(prefix='velora-flick-') as name:
            root = Path(name)
            (root / 'modules/common/functions').mkdir(parents=True, exist_ok=True)
            for singleton in ('PointerFlick', 'PopupHoverPolicy'):
                shutil.copy2(FUNCTIONS / f'{singleton}.qml', root / 'modules/common/functions' / f'{singleton}.qml')
            result, output = run_shell(root, '''Timer { running: true; onTriggered: {
  // A careful drift towards the preview: 12 px in 60 ms = 200 px/s.
  const slow = PointerFlick.awaySpeed(10, 22, 1000, 1060, 1);
  // A flick: 90 px in 45 ms = 2000 px/s, and the bar is at the bottom (sign -1).
  const fast = PointerFlick.awaySpeed(90, 0, 1000, 1045, -1);
  // Toward the bar is never "away"; a stalled stream or no previous sample says nothing.
  const back = PointerFlick.awaySpeed(40, 12, 1000, 1040, 1);
  if (Math.abs(slow - 200) > 0.01) { console.error("TEST slow", slow); Qt.exit(2); }
  if (Math.abs(fast - 2000) > 0.01) { console.error("TEST fast", fast); Qt.exit(3); }
  if (Math.abs(back + 700) > 0.01) { console.error("TEST back", back); Qt.exit(4); }
  if (PointerFlick.awaySpeed(10, 80, 1000, 1500, 1) !== 0) { console.error("TEST stalled"); Qt.exit(5); }
  if (PointerFlick.awaySpeed(-1, 80, 0, 20, 1) !== 0) { console.error("TEST first sample"); Qt.exit(5); }
  if (PointerFlick.smooth(0, back) !== 0) { console.error("TEST smoothing floor"); Qt.exit(6); }
  // Smoothing halves a single frame: a slow approach can never reach the threshold,
  // while a real flick clears it on the very first frame.
  if (Math.abs(PointerFlick.smooth(0, fast) - 1000) > 0.01) { console.error("TEST smoothing"); Qt.exit(7); }
  if (!PointerFlick.isFlick(1000, 370) || PointerFlick.isFlick(125, 370) || PointerFlick.isFlick(2000, 0))
   { console.error("TEST threshold"); Qt.exit(8); }
  Qt.quit();
} }''')
            self.assertEqual(result.returncode, 0, output)

    @unittest.skipUnless(QUICKSHELL, 'Quickshell is not installed')
    def test_hover_policy_latches_a_flick(self):
        with tempfile.TemporaryDirectory(prefix='velora-hover-policy-') as name:
            root = Path(name)
            (root / 'modules/common/functions').mkdir(parents=True, exist_ok=True)
            for singleton in ('PointerFlick', 'PopupHoverPolicy'):
                shutil.copy2(FUNCTIONS / f'{singleton}.qml', root / 'modules/common/functions' / f'{singleton}.qml')
            result, output = run_shell(root, '''Timer { running: true; onTriggered: {
  // Unchanged behaviour: an interactive popup leaving the bar gets its grace time...
  let s = PopupHoverPolicy.next(true, false, false, false, true, true);
  if (!(s.wanted && !s.dismissed && s.startClose && s.stopOpen)) { console.error("TEST grace", JSON.stringify(s)); Qt.exit(2); }
  // ...and keeps the popup open when the pointer arrives inside it.
  s = PopupHoverPolicy.next(true, false, true, false, true, true);
  if (!(s.wanted && s.stopClose && !s.startOpen)) { console.error("TEST stay", JSON.stringify(s)); Qt.exit(3); }
  // A non-interactive popup closes the moment the pointer leaves.
  s = PopupHoverPolicy.next(true, false, false, false, false, false);
  if (!(!s.wanted && !s.startClose)) { console.error("TEST plain close", JSON.stringify(s)); Qt.exit(4); }
  // A flick closes at once and latches, even though the pointer is heading into the popup.
  s = PopupHoverPolicy.next(true, false, false, true, true, true);
  if (!(!s.wanted && s.dismissed && !s.startClose)) { console.error("TEST flick", JSON.stringify(s)); Qt.exit(5); }
  // Landing inside the popup must not reopen it, nor start the open timer.
  s = PopupHoverPolicy.next(false, true, true, true, true, true);
  if (!(!s.wanted && s.dismissed && !s.startOpen && s.stopClose)) { console.error("TEST latch", JSON.stringify(s)); Qt.exit(6); }
  if (PopupHoverPolicy.timerWanted(true, true)) { console.error("TEST timer latch"); Qt.exit(7); }
  if (!PopupHoverPolicy.timerWanted(true, false)) { console.error("TEST timer open"); Qt.exit(7); }
  // Leaving the popup clears the latch, and hovering the bar opens the preview again.
  s = PopupHoverPolicy.next(false, true, false, false, true, true);
  if (!(!s.wanted && !s.dismissed)) { console.error("TEST disarm", JSON.stringify(s)); Qt.exit(8); }
  s = PopupHoverPolicy.next(false, false, true, false, true, true);
  if (!(s.startOpen && !s.wanted)) { console.error("TEST reopen", JSON.stringify(s)); Qt.exit(9); }
  Qt.quit();
} }''')
            self.assertEqual(result.returncode, 0, output)

    def test_the_preview_captures_only_what_it_shows(self):
        popup = (SHELL / 'modules/ii/bar/WorkspacePreviewPopup.qml').read_text()
        workspaces = (SHELL / 'modules/ii/bar/Workspaces.qml').read_text()
        # Only the shown workspace is captured, and every capture is size-limited.
        self.assertIn('=== root.workspaceId)', popup)
        self.assertNotIn('firstWorkspace', popup)
        self.assertNotIn('lastWorkspace', popup)
        self.assertNotIn('firstWorkspace', workspaces)
        self.assertIn('constraintSize: windowItem.captureLimit', popup)
        limit = popup[popup.index('readonly property size captureLimit'):popup.index('readonly property size captureLimit') + 320]
        self.assertIn('Math.min(720', limit)
        self.assertIn('Math.max(48', limit)
        # Refreshing stays bounded: one frame per second, only for visible windows.
        self.assertIn('running: windowItem.visible && capture.hasContent && !PowerSaving.cutLivePreviews', popup)
        self.assertIn('live: false', popup)

    def test_the_preview_and_its_setting_are_wired_together(self):
        workspaces = (SHELL / 'modules/ii/bar/Workspaces.qml').read_text()
        popup = (SHELL / 'modules/ii/bar/WorkspacePreviewPopup.qml').read_text()
        styled = (SHELL / 'modules/ii/bar/StyledPopup.qml').read_text()
        config = (SHELL / 'modules/common/Config.qml').read_text()
        catalog = (SHELL / 'modules/common/BarWidgetCatalog.qml').read_text()

        # The gauge measures and never takes the hover away from the buttons.
        self.assertIn('HoverHandler {', workspaces)
        self.assertIn('blocking: false', workspaces)
        self.assertIn('root.previewAwaySpeed = pointerGauge.awaySpeed', workspaces)
        self.assertIn('awaySpeed: root.previewAwaySpeed', workspaces)
        # The miniature asks for the instant close; the shared popup runs the policy.
        self.assertIn('property real awaySpeed: 0', popup)
        self.assertIn('hideInstantly: Config.options.bar.workspaces.hidePreviewOnFlick'
                      ' && awaySpeed >= flickSpeed', popup)
        self.assertIn('readonly property real flickSpeed: Config.options.bar.workspaces.flickSpeed', popup)
        self.assertIn('PopupHoverPolicy.next(wanted, dismissed, pointerInside, hideInstantly', styled)
        self.assertIn('PopupHoverPolicy.timerWanted(root.pointerInside, root.dismissed)', styled)
        self.assertIn('if (targetHovered) root.dismissed = false', styled)
        # The switch and the slider, and a default strict enough that an ordinary
        # hand movement closes the miniature instead of leaving it under the cursor.
        self.assertIn('property bool hidePreviewOnFlick: true', config)
        default = int(re.search(r'property int flickSpeed: (\d+)', config).group(1))
        # Strict enough that an ordinary hand movement dismisses the miniature, loose
        # enough that a deliberate slow approach still reaches it.
        self.assertLessEqual(default, 450)
        self.assertGreaterEqual(default, 300)
        self.assertIn('"scope": "path:bar.workspaces.hidePreviewOnFlick"', catalog)
        self.assertIn('"scope": "path:bar.workspaces.flickSpeed"', catalog)
        slider = [part for part in catalog.splitlines() if 'path:bar.workspaces.flickSpeed' in part][0]
        self.assertEqual((int(re.search(r'"from": (\d+)', slider).group(1)),
                          int(re.search(r'"to": (\d+)', slider).group(1))), (100, 600))
        self.assertLessEqual(default, 600)

        example = json.loads((PROJECT / 'dots/.config/illogical-impulse/config.example.json').read_text())
        self.assertIs(example['bar']['workspaces']['hidePreviewOnFlick'], True)
        self.assertEqual(example['bar']['workspaces']['flickSpeed'], default)

        russian = json.loads((SHELL / 'translations/ru_RU.json').read_text())
        for label in ('Hide the workspace preview when the pointer flicks away',
                      'How fast the pointer must move to hide it (px/s)'):
            self.assertIn(f'Translation.tr("{label}")', catalog)
            self.assertTrue(russian.get(label, '').strip(), label)


if __name__ == '__main__':
    unittest.main()
