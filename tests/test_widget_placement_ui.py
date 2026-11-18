"""Real QML placement dependencies and the bar inspector's popup lifecycle."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import test_connectivity_pages as pages


@unittest.skipUnless(pages.QS and pages.CARGO and pages.DBUS, 'needs the shell runtime')
class WidgetUiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()
        cls.runner = pages.SettingsPagesTests()

    def check_output(self, output):
        self.assertIn('DRIVER_PASS', output, output[-9000:])
        self.assertNotIn('CHECK_FAIL', output, output[-9000:])
        self.runner.assert_clean(output)
        self.assertNotIn('Binding loop', output)

    def test_placement_reacts_to_neighbours_then_stops(self):
        with tempfile.TemporaryDirectory(prefix='velora-widget-test-') as directory:
            # BMP is understood by both production image backends.
            import struct
            path = Path(directory) / 'wallpaper.bmp'
            pixels = bytes([40, 50, 60]) * (900 * 600)
            path.write_bytes(b'BM' + struct.pack('<IHHI', 54 + len(pixels), 0, 0, 54)
                             + struct.pack('<IiiHHIIiiII', 40, 900, 600, 1, 24, 0, len(pixels), 0, 0, 0, 0) + pixels)
            driver = r'''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets
ShellRoot {
    id: root
    property int step: 0
    property int ticks: 0
    property var generations: []
    function check(ok, message) { if (!ok) { console.log("CHECK_FAIL " + message); Qt.quit(); } return ok; }
    function settled(item) { return item && !item.analysisJob && item.analysisResult?.generation === item.analysisGeneration; }
    function separated() {
        const a = clock.item, b = weather.item;
        return a.targetX + a.width <= b.targetX || b.targetX + b.width <= a.targetX
            || a.targetY + a.height <= b.targetY || b.targetY + b.height <= a.targetY;
    }
    FloatingWindow {
        implicitWidth: 900; implicitHeight: 600; visible: true
        WidgetCanvas {
            id: canvas; anchors.fill: parent
            FadeLoader {
                id: weather
                sourceComponent: AbstractBackgroundWidget {
                    configEntryName: "weather"; placementCanvas: canvas
                    screenWidth: 900; screenHeight: 600; scaledScreenWidth: 900; scaledScreenHeight: 600; wallpaperScale: 1
                    width: 200; height: 200
                }
            }
            FadeLoader {
                id: clock; shown: false; fade: false
                sourceComponent: AbstractBackgroundWidget {
                    configEntryName: "clock"; placementCanvas: canvas
                    screenWidth: 900; screenHeight: 600; scaledScreenWidth: 900; scaledScreenHeight: 600; wallpaperScale: 1
                    width: 230; height: 260
                }
            }
        }
    }
    Timer {
        interval: 80; running: true; repeat: true
        onTriggered: {
            if (!Config.ready) return;
            if (root.step === 0) {
                Config.options.background.wallpaperPath = WALLPAPER;
                Config.options.background.widgets.clock.placementStrategy = "leastBusy";
                Config.options.background.widgets.weather.placementStrategy = "leastBusy";
                root.step++;
            } else if (root.step === 1) {
                if (!root.settled(weather.item)) return;
                clock.shown = true; root.step++;
            } else if (root.step === 2) {
                if (!root.settled(clock.item) || !root.settled(weather.item)) return;
                if (!root.check(root.separated(), "late clock overlapped weather")) return;
                clock.item.width = 350;
                root.step++;
            } else if (root.step === 3) {
                if (!root.settled(clock.item) || !root.settled(weather.item)) return;
                if (!root.check(root.separated(), "resize overlapped weather")) return;
                Config.options.background.widgets.clock.placementStrategy = "free";
                clock.item.targetX = weather.item.targetX;
                clock.item.targetY = weather.item.targetY;
                root.step++;
            } else if (root.step === 4) {
                if (!root.settled(weather.item)) return;
                if (!root.check(root.separated(), "manual placement ignored")) return;
                clock.shown = false;
                root.step++;
            } else if (root.step === 5) {
                if (!root.settled(weather.item)) return;
                if (!root.check(weather.item.placementObstacles === "[]", "destroyed peer retained")) return;
                clock.shown = true;
                Config.options.background.widgets.clock.placementStrategy = "mostBusy";
                root.step++;
            } else if (root.step === 6) {
                if (!root.settled(clock.item) || !root.settled(weather.item)) return;
                if (!root.check(root.separated(), "mixed strategies overlapped")) return;
                root.generations = [clock.item.analysisGeneration, weather.item.analysisGeneration];
                root.step++;
            } else if (root.step === 7 && ++root.ticks > 15) {
                if (!root.check(!clock.item.analysisJob && !weather.item.analysisJob
                    && root.generations[0] === clock.item.analysisGeneration
                    && root.generations[1] === weather.item.analysisGeneration, "idle placement kept doing work")) return;
                console.log("DRIVER_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: { console.log("CHECK_FAIL placement timeout " + root.step); Qt.quit(); } }
}
'''.replace('WALLPAPER', json.dumps(str(path)))
            with patch.dict(os.environ, {'VELORA_HELPER': str(pages.TOOLS / 'target/debug/velora-helper')}):
                self.check_output(self.runner.run_driver(driver))

    def test_bar_inspector_popup_scroll_and_dismissal(self):
        self.check_output(self.runner.run_driver(r'''
import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
    id: root
    property int step: 0
    property var popup: null
    property var scrollbar: null
    property bool animated: false
    function check(ok, message) { if (!ok) { console.log("CHECK_FAIL " + message); Qt.quit(); } return ok; }
    TestCase { id: input; name: "WidgetPopup"; when: false }
    FloatingWindow {
        id: window; implicitWidth: 800; implicitHeight: 600; visible: true
        BarConfig { id: page; anchors.fill: parent }
    }
    Timer {
        interval: 16; running: root.popup?.visible ?? false; repeat: true
        onTriggered: if (root.popup.opacity > 0 && root.popup.opacity < 1 && root.popup.scale < 1) root.animated = true;
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            if (!Config.ready) return;
            if (root.step === 0) {
                Config.options.appearance.animationSpeed = 1;
                page.addWidget("resources", "end", -1);
                root.popup = input.findChild(page, "barWidgetPopup");
                if (!root.check(!!root.popup, "popup missing")) return;
                root.step++;
            } else if (root.step === 1) {
                if (!root.check(root.popup.visible && root.popup.modal && root.popup.height <= window.height - 48,
                                "popup did not fit the window")) return;
                if (!root.check(root.animated, "popup did not animate")) return;
                input.keyClick(Qt.Key_Escape);
                root.step++;
            } else if (root.step === 2) {
                if (!root.check(!root.popup.visible && page.selectedUid === "", "Escape did not dismiss")) return;
                window.implicitHeight = 400;
                page.addWidget("workspaces", "start", -1);
                root.step++;
            } else if (root.step === 3) {
                root.scrollbar = input.findChild(root.popup.contentItem, "widgetInspectorScrollBar");
                if (!root.check(root.popup.visible && root.scrollbar.policy === ScrollBar.AlwaysOn
                    && root.scrollbar.size < 1 && root.popup.height <= window.height - 48, "overflow had no visible scrollbar")) return;
                root.scrollbar.position = 0.5;
                root.step++;
            } else if (root.step === 4) {
                if (!root.check(root.scrollbar.position > 0, "scrollbar did not move")) return;
                input.mouseClick(window.contentItem, 4, 4);
                root.step++;
            } else if (root.step === 5) {
                if (!root.check(!root.popup.visible && page.selectedUid === "", "outside click did not dismiss")) return;
                page.addWidget("resources", "end", -1);
                root.step++;
            } else if (root.step === 6) {
                page.pageShown = false;
                root.step++;
            } else if (root.step === 7) {
                if (!root.check(!root.popup.visible, "hidden page retained its overlay")) return;
                console.log("DRIVER_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: { console.log("CHECK_FAIL popup timeout " + root.step); Qt.quit(); } }
}
'''))

    def test_catalog_marks_only_placed_widgets_without_duplicates(self):
        self.check_output(self.runner.run_driver(r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
    id: root
    property int step: 0
    property string powerUid: ""
    property string groupUid: ""
    function check(ok, message) { if (!ok) { console.log("CHECK_FAIL " + message); Qt.quit(); } return ok; }
    TestCase { id: input; name: "Catalog"; when: false }
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 700; visible: true
        BarConfig { id: page; anchors.fill: parent }
    }
    Timer {
        interval: 220; running: true; repeat: true
        onTriggered: {
            if (!Config.ready) return;
            if (root.step === 0) {
                Config.options.bar.vertical = false;
                Config.options.appearance.animationSpeed = 0;
                root.powerUid = BarLayout.insert(page.orientation, "session", "end", -1);
                root.groupUid = BarLayout.insert(page.orientation, "utilButtons", "end", -1);
                Config.options.bar.utilButtons.showScreenSnip = true;
                root.step++;
            } else if (root.step === 1) {
                const power = input.findChild(page, "barCatalog-session");
                const snip = input.findChild(page, "barCatalog-screenSnip");
                if (!root.check(power?.present && power.pill && !power.selected && power.border.width === 0
                    && !snip?.present && !input.findChild(page, "barCatalog-network").present
                    && input.findChild(page, "barCatalog-statusIndicators").present, "catalog confused a group with separate widgets")) return;
                const types = page.catalogTypes("buttons");
                if (!root.check(types.indexOf("session") < types.indexOf("appButton"), "existing buttons should come first")) return;
                const before = JSON.stringify(page.layout);
                power.clicked();
                if (!root.check(page.selectedUid === page.placedOfType("session").item.uid && JSON.stringify(page.layout) === before,
                                "existing power button was duplicated")) return;
                page.selectedUid = "";
                if (!root.check(input.findChild(page, "barCatalog-utilButtons").present, "group itself was not highlighted")) return;
                root.step++;
            } else if (root.step === 2) {
                const snip = input.findChild(page, "barCatalog-screenSnip");
                if (!root.check(!snip.present, "group member should remain available separately")) return;
                snip.clicked();
                if (!root.check(page.selected.item.type === "screenSnip", "absent button was not added")) return;
                page.selectedUid = "";
                root.step++;
            } else if (root.step === 3) {
                if (!root.check(input.findChild(page, "barCatalog-screenSnip").present, "added button did not highlight")) return;
                const unique = page.placedOfType("leftSidebarButton").item.uid;
                page.addWidget("leftSidebarButton", "end", -1);
                const matches = [];
                for (const zone of BarLayout.zoneNames) {
                    for (const item of page.layout.zones[zone]) if (item.type === "leftSidebarButton") matches.push(item);
                }
                if (!root.check(matches.length === 1 && matches[0].uid === unique && page.selectedUid === unique,
                                "dragging a unique widget duplicated it")) return;
                page.selectedUid = "";
                Config.options.bar.vertical = true;
                root.step++;
            } else if (root.step === 4) {
                const present = !!page.placedOfType("session");
                if (!root.check(input.findChild(page, "barCatalog-session").present === present, "highlight used the other orientation")) return;
                console.log("DRIVER_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: { console.log("CHECK_FAIL catalog timeout " + root.step); Qt.quit(); } }
}
'''))


    def test_system_extras_are_opt_in_and_network_sampling_stops(self):
        self.check_output(self.runner.run_driver(r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.ii.sidebars.parts
ShellRoot {
    id: root
    property int step: 0
    property var partOptions: ({})
    property real compactHeight: 0
    function check(ok, message) { if (!ok) { console.log("CHECK_FAIL " + message); Qt.quit(); } return ok; }
    TestCase { id: input; name: "SystemExtras"; when: false }
    FloatingWindow {
        implicitWidth: 500; implicitHeight: 400; visible: true
        Item {
            id: systemHost
            property bool active: true
            property var options: SidebarLayout.optionsOf({type: "system", options: root.partOptions})
            Loader { id: part; width: 460; sourceComponent: SystemPart { host: systemHost } }
        }
    }
    Timer {
        interval: 160; running: true; repeat: true
        onTriggered: {
            if (!Config.ready) return;
            if (root.step === 0) {
                if (!root.check(systemHost.options.graphs && ["network", "battery", "updates", "details"].every(key => systemHost.options[key] === false)
                    && !input.findChild(part.item, "systemExtras").visible && NetworkSpeed.users === 0,
                    "extras must default to off")) return;
                root.compactHeight = part.item.implicitHeight;
                root.partOptions = {network: true, details: true};
                root.step++;
            } else if (root.step === 1) {
                if (!root.check(NetworkSpeed.users === 1 && part.item.showDetails && part.item.implicitHeight > root.compactHeight,
                                "enabled extras did not appear")) return;
                systemHost.active = false; root.step++;
            } else if (root.step === 2) {
                if (!root.check(NetworkSpeed.users === 0, "hidden sidebar still samples network")) return;
                systemHost.active = true; root.step++;
            } else if (root.step === 3) {
                if (!root.check(NetworkSpeed.users === 1, "reopening duplicated subscription")) return;
                part.active = false; root.step++;
            } else if (root.step === 4) {
                if (!root.check(NetworkSpeed.users === 0, "destroyed part retained subscription")) return;
                part.active = true; root.step++;
            } else if (root.step === 5) {
                if (!root.check(NetworkSpeed.users === 1, "creation with network enabled subscribed twice")) return;
                root.partOptions = {}; root.step++;
            } else if (root.step === 6) {
                if (!root.check(NetworkSpeed.users === 0 && part.item.implicitHeight === root.compactHeight,
                                "disabled extras left polling or empty space")) return;
                console.log("DRIVER_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: { console.log("CHECK_FAIL system timeout " + root.step); Qt.quit(); } }
}
'''))


if __name__ == '__main__':
    unittest.main()
