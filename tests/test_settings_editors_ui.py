"""Exercise sidebar popups and shortcut editing in the actual QML runtime, isolated from the desktop."""
from pathlib import Path
import unittest
import test_connectivity_pages as pages

HEADER = '''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
    id: root
    property int step: 0
    function check(ok, text) { if (!ok) { console.log("CHECK_FAIL " + text); Qt.quit(); } return ok; }
    TestCase { id: input; name: "Editors"; when: false }
'''

@unittest.skipUnless(pages.QS and pages.CARGO and pages.DBUS, 'needs shell runtime')
class EditorsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()
        cls.runner = pages.SettingsPagesTests()

    def run_qml(self, source):
        output = self.runner.run_driver(HEADER + source + '''
    Timer { interval: 12000; running: true; onTriggered: { console.log("CHECK_FAIL timeout " + root.step); Qt.quit(); } }
}''')
        self.assertIn('DRIVER_PASS', output, output[-10000:])
        self.assertNotIn('CHECK_FAIL', output, output[-10000:])
        self.runner.assert_clean(output)
        self.assertNotIn('Binding loop', output)

    def test_sidebar_settings_and_part_popups(self):
        self.run_qml(r'''
    property var settingsPopup: null
    property var partPopup: null
    property var inspector: null
    property bool animated: false
    FloatingWindow {
        id: window; implicitWidth: 960; implicitHeight: 360; visible: true
        SidebarsConfig { id: page; anchors.fill: parent }
    }
    Timer {
        interval: 16; running: root.partPopup?.visible ?? false; repeat: true
        onTriggered: if (root.partPopup.opacity > 0 && root.partPopup.opacity < 1 && root.partPopup.scale < 1) root.animated = true;
    }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            if (!Config.ready) return;
            if (root.step === 0) {
                Config.options.appearance.animationSpeed = 1;
                Config.options.appearance.transparency.enable = true;
                Config.options.appearance.transparency.automatic = false;
                Config.options.appearance.transparency.contentTransparency = 0.8;
                root.settingsPopup = input.findChild(page, "sidebarSettingsPopup");
                root.partPopup = input.findChild(page, "sidebarPartPopup");
                if (!root.check(!!root.settingsPopup && !!root.partPopup && !root.settingsPopup.visible && !root.partPopup.visible,
                    "editors should start closed")) return;
                input.findChild(page, "sidebarSettingsButton").clicked(); root.step++;
            } else if (root.step === 1) {
                if (!root.check(root.settingsPopup.visible && root.settingsPopup.modal && root.settingsPopup.background.color.a === 1 && root.settingsPopup.height <= window.height - 48,
                    "general popup size or modality")) return;
                input.keyClick(Qt.Key_Escape); root.step++;
            } else if (root.step === 2) {
                if (!root.check(!root.settingsPopup.visible, "Escape left settings open")) return;
                page.select(SidebarLayout.findType("header").part.uid); root.step++;
            } else if (root.step === 3) {
                if (!root.check(root.partPopup.visible && root.animated, "Top row did not animate")) return;
                root.inspector = input.findChild(root.partPopup, "sidebarPartInspector");
                if (!root.check(!!root.inspector, "part inspector missing")) return;
                SidebarLayout.setOptionKey(page.selectedUid, "buttons", ["settings"]); root.step++;
            } else if (root.step === 4) {
                if (!root.check(input.findChild(root.partPopup, "sidebarPartInspector") === root.inspector,
                    "editing rebuilt the inspector mid-interaction")) return;
                input.mouseClick(page.popupPane, 4, 4); root.step++;
            } else if (root.step === 5) {
                if (!root.check(!root.partPopup.visible && page.selectedUid === "", "outside click did not clear selection")) return;
                page.select(SidebarLayout.findType("sliders").part.uid); root.step++;
            } else if (root.step === 6) {
                const bar = input.findChild(root.partPopup, "settingsPopupScrollBar");
                if (!root.check(root.partPopup.visible && root.partPopup.height <= window.height - 48 && bar.policy === ScrollBar.AlwaysOn,
                    "Sliders did not fit or expose scrolling: " + root.partPopup.visible + " h=" + root.partPopup.height + " window=" + window.height + " policy=" + bar.policy + " size=" + bar.size)) return;
                page.pageShown = false; root.step++;
            } else if (root.step === 7) {
                if (!root.check(!root.partPopup.visible && !root.settingsPopup.visible, "overlay survived page hide")) return;
                console.log("DRIVER_PASS"); Qt.quit();
            }
        }
    }
''')

    def test_sidebar_previews_slide_past_a_single_catalog(self):
        self.run_qml(r'''
    FloatingWindow {
        id: window; implicitWidth: 960; implicitHeight: 560; visible: true
        SidebarsConfig { id: page; width: root.compact ? 475 : parent.width; height: parent.height }
    }
    property bool compact: false
    property var stage
    property var picker
    property var pane
    property var left
    property var right
    property real initialPickerX: 0
    property real scrollOffset: 0
    function clickSide(side) {
        const button = picker.children.find(child => child.modelData?.value === side);
        input.mouseClick(button, button.width / 2, button.height / 2);
    }
    function settled(side) {
        const onRight = side === "right";
        const shown = onRight ? right : left;
        const hidden = onRight ? left : right;
        return stage.rightFraction === (onRight ? 1 : 0) && shown.item?.side === side
            && shown.enabled && !hidden.active && !hidden.enabled
            && (onRight ? pane.x === 0 && shown.x + shown.width === stage.width
                        : shown.x === 0 && pane.x + pane.width === stage.width);
    }
    Timer {
        interval: 16; running: true; repeat: true
        onTriggered: {
            if (!Config.ready) return;
            switch (root.step) {
            case 0:
                Config.options.appearance.animationSpeed = 0.8;
                root.stage = input.findChild(page, "sidebarWorkspace");
                root.picker = input.findChild(page, "sidebarSidePicker");
                root.pane = input.findChild(page, "sidebarCatalogPane");
                root.left = input.findChild(page, "leftSidebarPreview");
                root.right = input.findChild(page, "rightSidebarPreview");
                if (!root.check(root.settled("right"), "initial right preview and left catalog")) return;
                root.initialPickerX = root.picker.x;
                root.pane.contentY = Math.min(45, Math.max(0, root.pane.contentHeight - root.pane.height));
                root.scrollOffset = root.pane.contentY;
                root.clickSide("left");
                break;
            case 1: {
                if (root.stage.rightFraction > 0.7) return;
                if (!root.check(root.stage.rightFraction > 0 && root.pane.x > 0
                    && root.left.x < 0 && root.left.x + root.left.width > 0
                    && root.right.x < root.stage.width && root.right.x + root.right.width > root.stage.width
                    && root.left.item?.side === "left" && root.right.item?.side === "right"
                    && !root.right.enabled && root.picker.x === root.initialPickerX, "both sides move at their own edges")) return;
                const before = root.pane.x;
                root.clickSide("right");
                if (!root.check(Math.abs(root.pane.x - before) < 2, "interrupted transition jumped")) return;
                break;
            }
            case 2:
                if (!root.settled("right")) return;
                root.clickSide("left");
                break;
            case 3:
                if (!root.settled("left")) return;
                if (!root.check(root.scrollOffset > 0 && root.pane.contentY === root.scrollOffset, "catalog scroll position changed")) return;
                root.clickSide("right");
                break;
            case 4:
                if (root.stage.rightFraction < 0.25) return;
                if (!root.check(root.stage.rightFraction < 1 && root.left.x < 0 && root.right.x < root.stage.width,
                    "left slides out to the left as right enters")) return;
                Config.options.appearance.animationSpeed = 0;
                break;
            case 5:
                if (!root.check(root.settled("right"), "turning off motion should settle immediately")) return;
                page.navigateToSection("left");
                if (!root.check(root.settled("left"), "breadcrumb navigation with motion off")) return;
                root.compact = true;
                break;
            case 6:
                if (root.stage.width > 450) return;
                stop();
                if (!root.check(root.settled("left") && root.pane.width > 230 && root.left.width > 145, "narrow left layout")) return;
                root.clickSide("right");
                if (!root.check(root.settled("right") && root.pane.x + root.pane.width < root.right.x, "narrow right layout")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            root.step++;
        }
    }
''')

    def test_sidebar_catalog_drag_to_slots_and_tabs(self):
        self.run_qml(r'''
    FloatingWindow {
        id: window; implicitWidth: 990; implicitHeight: 700; visible: true
        SidebarsConfig { id: page; anchors.fill: parent }
    }
    property var pane
    property point releaseAt
    function chip(type) {
        const item = input.findChild(page, "sidebarCatalog-" + type);
        const y = item.mapToItem(pane.contentItem, 0, 0).y;
        pane.contentY = Math.min(Math.max(0, y - 90), Math.max(0, pane.contentHeight - pane.height));
        return item;
    }
    function preview() { return input.findChild(page, page.side + "SidebarPreview").item; }
    function drag(type, target, x, y) {
        const source = chip(type);
        const start = source.mapToItem(window.contentItem, source.width / 2, source.height / 2);
        releaseAt = target.mapToItem(window.contentItem, x, y);
        input.mousePress(window.contentItem, start.x, start.y);
        input.mouseMove(window.contentItem, start.x + 10, start.y, 2, Qt.LeftButton);
        input.mouseMove(window.contentItem, releaseAt.x, releaseAt.y, 2, Qt.LeftButton);
    }
    function release() { input.mouseRelease(window.contentItem, releaseAt.x, releaseAt.y); }
    Timer {
        interval: 140; running: true; repeat: true
        onTriggered: {
            if (!Config.ready) return;
            switch (root.step) {
            case 0:
                Config.options.appearance.animationSpeed = 0;
                Config.options.sidebar.right.parts = [
                    {uid:"head-r",type:"header"}, {uid:"group",type:"tabs",tabs:[]}, {uid:"tools-r",type:"tools"}];
                Config.options.sidebar.left.parts = [{uid:"head-l",type:"header"}, {uid:"notice",type:"notifications"}];
                root.pane = input.findChild(page, "sidebarCatalogPane");
                break;
            case 1: {
                const previous = SidebarLayout.revision;
                root.drag("tools", page, 12, 12);
                if (!root.check(page.dragType === "tools" && !page.dropTarget, "catalog drag outside both previews")) return;
                root.release();
                if (!root.check(!page.dragType && !page.selectedUid && SidebarLayout.revision === previous, "outside drop changed layout or opened inspector")) return;
                const p = root.preview();
                root.drag("tools", p, p.width / 2, 3);
                if (!root.check(page.dropTarget?.index === 0 && input.findChild(p, "sidebarInsertionGuide").visible, "insertion guide in first gap")) return;
                root.release();
                if (!root.check(SidebarLayout.parts("right").length === 4 && SidebarLayout.parts("right")[0].type === "tools"
                    && !page.selectedUid, "repeatable part inserted at the top")) return;
                break;
            }
            case 2: {
                const p = root.preview();
                root.drag("header", p, p.width / 2, p.height - 3); root.release();
                const parts = SidebarLayout.parts("right");
                if (!root.check(parts[parts.length - 1].uid === "head-r" && SidebarLayout.find("head-l").side === "left",
                    "per-side part moved once, retaining its identity")) return;
                break;
            }
            case 3: {
                const p = root.preview();
                const group = SidebarLayout.find("group").part;
                root.drag("notifications", p, p.width / 2, p.padding + p.topOf("group", p.order) + p.heightOf(group) / 2);
                if (!root.check(page.dropTarget?.groupUid === "group", "empty tab group accepts compatible part")) return;
                root.release();
                if (!root.check(SidebarLayout.find("notice")?.group?.uid === "group", "shell-wide part moved into tabs")) return;
                input.keyClick(Qt.Key_Z, Qt.ControlModifier);
                if (!root.check(SidebarLayout.find("notice").side === "left" && !SidebarLayout.find("notice").group, "undo restores both sides")) return;
                page.navigateToSection("left");
                break;
            }
            case 4: {
                const p = root.preview();
                const before = SidebarLayout.revision;
                root.drag("tools", p, p.width / 2, 3);
                if (!root.check(page.dropTarget?.index === 0, "left preview accepts from the right catalog")) return;
                input.keyClick(Qt.Key_Escape); root.release();
                if (!root.check(!page.dragType && SidebarLayout.revision === before, "Escape cancels a pending drop")) return;
                root.drag("tools", p, p.width / 2, 3); root.release();
                if (!root.check(SidebarLayout.parts("left")[0].type === "tools", "left preview commits drop")) return;
                const source = root.chip("header");
                input.mouseClick(source, source.width / 2, source.height / 2);
                if (!root.check(page.selectedUid === "head-l", "click still opens the current sidebar's inspector")) return;
                page.navigateBack();
                Config.options.sidebar.left.parts = Array.from({length: 16}, (_, i) => ({uid:"tools-" + i, type:"tools"}));
                break;
            }
            case 5: {
                const p = root.preview();
                root.drag("tools", p, p.width / 2, p.height - 3);
                break;
            }
            case 6: {
                const scroller = input.findChild(root.preview(), "sidebarPreviewScroll");
                if (scroller.contentY < scroller.contentHeight - scroller.height - 1) return;
                if (!root.check(scroller.contentY > 0 && page.dropTarget?.index === 16, "holding near the edge reaches the end of a long sidebar")) return;
                root.release();
                if (!root.check(SidebarLayout.parts("left").length === 17 && SidebarLayout.parts("left")[15].uid === "tools-15", "drop into scrolled final gap")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            }
            root.step++;
        }
    }
''')

    def test_popup_bounds_and_navigation_in_the_settings_window(self):
        host = (pages.SHELL / 'settings.qml').read_text().replace('    id: root\n', '''    id: root
    SettingsPopupNavigationFixture { host: root; navigation: sidebar; viewport: pageStack }
''', 1)
        fixture = (Path(__file__).parent / 'qml/SettingsPopupNavigationFixture.qml').read_text()
        output = self.runner.run_driver(host, settings_page='bar', page_sources={'SettingsPopupNavigationFixture.qml': fixture})
        self.assertIn('DRIVER_PASS', output, output[-4000:])
        self.assertNotRegex(output, r'CHECK_FAIL|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')

    def test_shortcut_alignment_recording_and_reset(self):
        self.run_qml(r'''
    property var recordings: []
    function fixture(id, mods, key) {
        return {id: id, description: id, group: "shell", remappable: true, mods: mods, key: key, default_mods: mods, default_key: key};
    }
    FloatingWindow {
        id: window; implicitWidth: 900; implicitHeight: 550; visible: true
        ColumnLayout {
            anchors.fill: parent
            ShortcutRow { id: first; uid: "stop" }
            ShortcutRow { id: second; uid: "search" }
            ShortcutRow { id: third; uid: "layout" }
            ShortcutRecorder { id: recorder; onRecorded: (mods, key) => root.recordings = [...root.recordings, {mods: mods, key: key}] }
            Item { Layout.fillHeight: true }
        }
    }
    Timer {
        interval: 220; running: true; repeat: true
        onTriggered: {
            if (root.step === 0) {
                const binds = [root.fixture("stop", ["Ctrl", "Alt"], "Escape"), root.fixture("search", [], "Super"), root.fixture("layout", ["Alt"], "Shift")];
                HyprlandKeybinds.binds = binds;
                HyprlandKeybinds.bindMap = {stop: binds[0], search: binds[1], layout: binds[2]};
                root.step++;
            } else if (root.step === 1) {
                const rows = [first, second, third];
                const ends = rows.map(row => { const r = input.findChild(row, "shortcutRecorder"); return r.mapToItem(window.contentItem, r.width, 0).x; });
                if (!root.check(Math.max(...ends) - Math.min(...ends) < 1 && rows.every(row => Math.abs(row.height - first.height) < 1),
                    "unequal shortcut alignment/heights " + ends + " " + rows.map(r => r.height))) return;
                recorder.start(); input.keyPress(Qt.Key_Meta); input.keyRelease(Qt.Key_Meta); root.step++;
            } else if (root.step === 2) {
                if (!root.check(root.recordings[0]?.key === "Super" && !recorder.recording, "modifier-only recording")) return;
                recorder.start(); input.keyPress(Qt.Key_Alt); input.keyPress(Qt.Key_Shift, Qt.AltModifier);
                input.keyRelease(Qt.Key_Shift, Qt.AltModifier); input.keyRelease(Qt.Key_Alt); root.step++;
            } else if (root.step === 3) {
                if (!root.check(KeyUtils.comboKey(root.recordings[1]?.mods, root.recordings[1]?.key) === KeyUtils.comboKey(["Alt"], "Shift"), "modifier chord")) return;
                recorder.start(); input.keyClick(Qt.Key_K, Qt.ControlModifier); root.step++;
            } else if (root.step === 4) {
                if (!root.check(root.recordings[2]?.key === "K" && root.recordings[2]?.mods.includes("Ctrl"), "normal recording")) return;
                recorder.start(); input.mouseClick(recorder, 10, 10, Qt.RightButton, Qt.MetaModifier); root.step++;
            } else if (root.step === 5) {
                if (!root.check(root.recordings[3]?.key === "mouse:273", "mouse recording")) return;
                recorder.start(); input.keyClick(Qt.Key_Escape);
                if (!root.check(!recorder.recording && root.recordings.length === 4, "cancel recorded a shortcut")) return;
                HyprlandKeybinds.remap = {search: {mods: "Ctrl", key: "Space"}, layout: false};
                HyprlandKeybinds.custom = [{mods: "Super", key: "F3", command: "true"}];
                if (!root.check(HyprlandKeybinds.changedCount === 3, "custom not counted")) return;
                HyprlandKeybinds.resetAll(); root.step++;
            } else if (root.step === 6) {
                if (!root.check(HyprlandKeybinds.changedCount === 0 && !HyprlandKeybinds.captureWanted && !HyprlandKeybinds.activeRecorder,
                    "reset/capture cleanup")) return;
                console.log("DRIVER_PASS"); Qt.quit();
            }
        }
    }
''')

if __name__ == '__main__': unittest.main()
