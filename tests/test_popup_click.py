"""Real Qt pointer regression for click-opened bar popups (no desktop changes)."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
RUNNER = next((str(p) for p in (Path('/usr/lib/qt6/bin/qmltestrunner'),
                              Path('/usr/lib64/qt6/bin/qmltestrunner')) if p.is_file()), None)


class PopupClickTests(unittest.TestCase):
    @unittest.skipUnless(RUNNER, 'Qt6 Quick Test is not installed')
    def test_real_pointer_press_release_and_leave(self):
        with tempfile.TemporaryDirectory(prefix='velora-popup-click-') as name:
            root = Path(name)
            shutil.copy2(SHELL / 'modules/common/widgets/PopupHoverTarget.qml', root)
            (root / 'tst_click.qml').write_text('''import QtQuick
import QtTest

Item {
    width: 400; height: 240
    MouseArea {
        id: target
        x: 20; y: 20; width: 100; height: 50
        hoverEnabled: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property int presses: 0
        property int clicks: 0
        onPressed: presses++
        onClicked: clicks++
    }
    MouseArea { id: other; x: 180; y: 20; width: 100; height: 50; hoverEnabled: false }
    Item { id: synthetic; property bool containsMouse: false }
    PopupHoverTarget { id: presence; target: target }
    TestCase {
        name: "PopupClickPointer"; when: windowShown
        function init() {
            mouseMove(target, 150, 150);
            target.hoverEnabled = false;
            target.enabled = true;
            presence.target = target;
            presence.enabled = true;
            synthetic.containsMouse = false;
            target.presses = 0; target.clicks = 0;
            wait(20);
        }
        function test_click_release_stays_until_real_leave() {
            mouseMove(target, 20, 20);
            compare(presence.containsMouse, false); // hover alone must not open
            mousePress(target, 20, 20);
            compare(target.containsMouse, true);
            compare(presence.containsMouse, true);
            mouseRelease(target, 20, 20);
            compare(target.containsMouse, false); // the old popup closed right here
            compare(presence.containsMouse, true);
            wait(450); // longer than the popup's grace timer and exit animation
            compare(presence.containsMouse, true);
            compare(target.presses, 1); compare(target.clicks, 1);
            mouseMove(target, 150, 100);
            tryCompare(presence, "containsMouse", false);
            mouseMove(target, 20, 20);
            compare(presence.containsMouse, false); // another click required
        }
        function test_right_click_action_is_not_stolen() {
            mouseMove(target, 20, 20);
            mousePress(target, 20, 20, Qt.RightButton);
            mouseRelease(target, 20, 20, Qt.RightButton);
            compare(target.presses, 1); compare(target.clicks, 1);
            compare(presence.containsMouse, true);
        }
        function test_press_drag_out_and_cancel() {
            mouseMove(target, 20, 20);
            mousePress(target, 20, 20);
            mouseMove(target, 150, 100);
            tryCompare(presence, "containsMouse", false); // close even while still held
            mouseRelease(target, 150, 100);
            tryCompare(presence, "containsMouse", false);
            mouseMove(target, 20, 20);
            compare(presence.containsMouse, false);
        }
        function test_normal_hover_is_unchanged() {
            target.hoverEnabled = true;
            mouseMove(target, 20, 20);
            tryCompare(presence, "containsMouse", true);
            mouseMove(target, 150, 100);
            tryCompare(presence, "containsMouse", false);
        }
        function test_editing_and_mode_changes_disarm() {
            mouseMove(target, 20, 20);
            mouseClick(target, 20, 20);
            compare(presence.containsMouse, true);
            presence.enabled = false;
            compare(presence.containsMouse, false);
            presence.enabled = true;
            compare(presence.containsMouse, false);
            target.hoverEnabled = true;
            mouseMove(target, 150, 100);
            mouseMove(target, 21, 21); // Re-enter after changing Qt's hover subscription
            tryCompare(presence, "containsMouse", true);
            target.hoverEnabled = false;
            compare(presence.containsMouse, false);
        }
        function test_disabled_target_disarms() {
            mouseMove(target, 20, 20);
            mouseClick(target, 20, 20);
            compare(presence.containsMouse, true);
            target.enabled = false;
            compare(presence.containsMouse, false);
            target.enabled = true;
            compare(presence.containsMouse, false);
        }
        function test_target_change_and_synthetic_anchor() {
            mouseMove(target, 20, 20);
            mouseClick(target, 20, 20);
            compare(presence.containsMouse, true);
            presence.target = other;
            compare(presence.containsMouse, false);
            presence.target = synthetic;
            synthetic.containsMouse = true;
            compare(presence.containsMouse, true);
            synthetic.containsMouse = false;
            compare(presence.containsMouse, false);
        }
    }
}
''')
            env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
                   'QT_QPA_PLATFORMTHEME': 'generic'}
            result = subprocess.run([RUNNER, '-input', str(root)], env=env,
                                    capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            for noise in ('TypeError', 'ReferenceError', 'Cannot assign', 'Binding loop'):
                self.assertNotIn(noise, output)

    @unittest.skipUnless(RUNNER, 'Qt6 Quick Test is not installed')
    def test_production_popup_state_and_timers(self):
        with tempfile.TemporaryDirectory(prefix='velora-popup-state-') as name:
            root = Path(name)
            # Execute the actual StyledPopup state/timer block, replacing only the
            # compositor-specific LazyLoader/PanelWindow rendering with a Qt Item.
            source = (SHELL / 'modules/ii/bar/StyledPopup.qml').read_text()
            state = source.split('LazyLoader {', 1)[1].split('    component: PanelWindow {', 1)[0]
            # `active` is a LazyLoader property; declare it on the rendering stand-in.
            (root / 'PopupState.qml').write_text('import QtQuick\nItem { property bool active\n'
                                                + state + '\n}')
            shutil.copy2(SHELL / 'modules/common/widgets/PopupHoverTarget.qml', root)
            policy_path = SHELL / 'modules/common/functions/PopupHoverPolicy.qml'
            policy = policy_path.read_text() if policy_path.exists() else 'pragma Singleton\nimport Quickshell\nSingleton {}'
            (root / 'PopupHoverPolicy.qml').write_text(policy.replace('import Quickshell', 'import QtQml').replace('Singleton {', 'QtObject {'))
            (root / 'Config.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var options: ({bar: {microAnimations: true}}) }')
            (root / 'GlobalStates.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool barEditing: false }')
            (root / 'Appearance.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var animation: ({elementMoveFast: {duration: 40}}) }')
            (root / 'qmldir').write_text('\n'.join('singleton ' + n + ' 1.0 ' + n + '.qml'
                                                    for n in ('Config', 'GlobalStates', 'Appearance', 'PopupHoverPolicy')))
            (root / 'tst_state.qml').write_text('''import QtQuick
import QtTest
Item {
 width: 400; height: 240
 MouseArea { id: target; x:20; y:20; width:100; height:50; hoverEnabled:false }
 PopupState { id: popup; hoverTarget: target; Component.onCompleted: closeTimer.interval = 70 }
 Item { id: synthetic; property bool containsMouse: false }
 TestCase {
  name: "ProductionPopupState"; when: windowShown
  function init() {
   mouseMove(target, 150, 100);
   popup.hoverControlled = false;
   popup.hoverTarget = target;
   popup.interactive = false;
   popup.popupHovered = false; popup.openDelay = 0;
   target.hoverEnabled = false; synthetic.containsMouse = false;
   GlobalStates.barEditing = false;
   popup.hoverControlled = true;
   wait(100);
  }
  function test_click_release_does_not_close_after_grace() {
   mouseMove(target,20,20); compare(popup.active,false);
   mousePress(target,20,20); compare(popup.wanted,true);
   mouseRelease(target,20,20); wait(150);
   compare(popup.wanted,true); compare(popup.active,true);
   mouseMove(target,150,100); wait(100); compare(popup.active,false);
   mouseMove(target,20,20); compare(popup.active,false);
  }
  function test_interactive_crossing_and_leaving() {
   popup.interactive=true;
   mouseMove(target,20,20); mouseClick(target,20,20);
   mouseMove(target,150,100); compare(popup.wanted,true);
   popup.popupHovered=true; wait(120); compare(popup.wanted,true);
   popup.popupHovered=false; wait(120); compare(popup.active,false);
  }
  function test_owner_does_not_run_hover_timers() {
   popup.hoverControlled=false; popup.active=true;
   mouseMove(target,20,20); mouseClick(target,20,20);
   mouseMove(target,150,100); wait(150);
   compare(popup.wanted,false); compare(popup.openTimer.running,false);
   compare(popup.closeTimer.running,false); compare(popup.active,true);
   popup.active=false;
   popup.active=Qt.binding(() => popup.wanted || popup.lingering);
  }
  function test_synthetic_anchor_hover_delay() {
   popup.hoverTarget=synthetic; popup.interactive=true; popup.openDelay=30;
   synthetic.containsMouse=true; compare(popup.wanted,false);
   wait(50); compare(popup.wanted,true);
   synthetic.containsMouse=false; wait(120); compare(popup.active,false);
  }
 }
}''')
            env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
                   'QT_QPA_PLATFORMTHEME': 'generic'}
            result = subprocess.run([RUNNER, '-input', str(root)], env=env,
                                    capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            for noise in ('TypeError', 'ReferenceError', 'Cannot assign', 'Binding loop'):
                self.assertNotIn(noise, output)

    def test_shared_popup_uses_presence_without_overriding_owner(self):
        text = (SHELL / 'modules/ii/bar/StyledPopup.qml').read_text()
        self.assertIn('property PopupHoverTarget targetPresence:', text)
        self.assertIn('enabled: root.hoverControlled && !GlobalStates.barEditing', text)
        self.assertIn('readonly property bool targetHovered: targetPresence.containsMouse', text)
        self.assertIn('if (!hoverControlled) return;', text)
        self.assertEqual(text.count('onTriggered: if (root.hoverControlled) root.wanted'), 2)
        self.assertIn('active: wanted || lingering', text)
        tray = (SHELL / 'modules/ii/bar/SysTray.qml').read_text()
        self.assertIn('hoverControlled: false', tray)
        self.assertIn('active: root.trayOverflowOpen && root.unpinnedItems.length > 0', tray)


if __name__ == '__main__':
    unittest.main()
