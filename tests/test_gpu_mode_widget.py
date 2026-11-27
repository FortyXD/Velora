"""Load the real GPU button and exercise both switches against a private supergfxctl."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import test_connectivity_pages as pages


DRIVER = r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.ii.bar.widgets

ShellRoot {
    id: root
    property int step: 0
    property int ticks: 0
    property bool sawPending: false
    function showsPlainIcon(name) {
        const button = gpu.item;
        return button.iconName === name && button.iconFill === 0
            && Qt.colorEqual(button.buttonColor, button.hovered ? button.colBackgroundHover : button.colBackground);
    }
    TestCase { id: pointer; name: "GpuMode"; when: false }
    FloatingWindow {
        visible: true; implicitWidth: 160; implicitHeight: 64
        TestUtilButton { id: gpu; anchors.centerIn: parent; kind: "gpuMode" }
    }
    Timer {
        interval: 30; repeat: true; running: true
        onTriggered: {
            if (++root.ticks > 250) {
                console.log("DRIVER_FAIL", root.step, Supergfxctl.mode, Supergfxctl.lastError);
                Qt.quit();
                return;
            }
            if (!gpu.item || !Supergfxctl.available) return;
            if (root.step === 0 && !Supergfxctl.busy && Supergfxctl.integrated && Supergfxctl.powerState === "active") {
                if (!root.showsPlainIcon("memory")) return;
                Supergfxctl.setModeCooldownMs = 0;
                Supergfxctl.refresh();
                Supergfxctl.refresh();
                pointer.mouseClick(gpu.item);
                pointer.mouseClick(gpu.item);
                root.step++;
            } else if (root.step === 1) {
                if (Supergfxctl.integrated && Supergfxctl.pendingMode === "Hybrid") root.sawPending = true;
                if (!root.sawPending || !Supergfxctl.hybrid || Supergfxctl.busy) return;
                if (!root.showsPlainIcon("desktop_windows")) return;
                pointer.mouseClick(gpu.item);
                root.step++;
            } else if (root.step === 2 && !Supergfxctl.busy && Supergfxctl.integrated && root.showsPlainIcon("memory")) {
                console.log("DRIVER_PASS");
                Qt.quit();
            }
        }
    }
}
'''

FAKE_SUPERGFXCTL = '''#!/usr/bin/python3
from pathlib import Path
import sys
import time

folder = Path(__file__).parent
mode = folder / "current"
if sys.argv[1] == "-g":
    time.sleep(0.12)
    print(mode.read_text())
elif sys.argv[1] == "-P":
    print("Unknown")
elif sys.argv[1] == "-S":
    print("active")
elif sys.argv[1] == "-m":
    with (folder / "changes").open("a") as log:
        print(sys.argv[2], file=log)
    mode.write_text(sys.argv[2])
else:
    raise SystemExit(1)
'''


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED,
                     "needs Quickshell, D-Bus and cargo")
class GpuModeWidgetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()

    def test_click_while_refreshing_and_switch_back(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / "current").write_text("Integrated")
            for name, source in (("supergfxctl", FAKE_SUPERGFXCTL), ("pkill", "#!/bin/sh\nexit 0\n")):
                executable = folder / name
                executable.write_text(source)
                executable.chmod(0o755)
            with patch.dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"]):
                case = pages.SettingsPagesTests()
                # Offscreen Qt has no layer-shell surface. Instantiate all real popup rows
                # and the real button, substituting just the two popup containers.
                bar = pages.SHELL / "modules/ii/bar"
                sources = {
                    "TestUtilButton.qml": (bar / "widgets/UtilButton.qml").read_text()
                        .replace("CircleUtilButton {", "TestCircleUtilButton {")
                        .replace("StyledPopup {", "TestPopup {"),
                    "TestCircleUtilButton.qml": (bar / "CircleUtilButton.qml").read_text()
                        .replace("BarToolTip {", "TestTooltip {"),
                    "TestPopup.qml": "import QtQuick\nItem { property Item hoverTarget }",
                    "TestTooltip.qml": "import QtQuick\nItem { property bool shown; property string text }",
                }
                output = case.run_driver(DRIVER, page_sources=sources)
            self.assertNotIn("Required property icon was not initialized", output)
            self.assertIn("DRIVER_PASS", output, output[-4000:])
            self.assertEqual((folder / "changes").read_text().splitlines(), ["Hybrid", "Integrated"])
            case.assert_clean(output)
