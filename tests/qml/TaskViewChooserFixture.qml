import QtQuick
import QtTest
import Quickshell
import qs.modules.waffle.taskView
import qs.services

ShellRoot {
    id: root
    TestCase { id: input; when: false }
    FloatingWindow {
        visible: true
        implicitWidth: 960
        implicitHeight: 640
        TaskViewContent { id: page; anchors.fill: parent; workspaceId: 2 }
        TaskViewWindow {
            id: preview
            visible: false
            toplevel: null
            maxWidth: 180
            maxHeight: 120
            hyprlandClient: ({ address: "0xabc", title: "Editor", class: "editor", size: [180, 120] })
            onMoveRequested: page.chooseDesktop(address)
        }
    }

    function find(item, predicate) {
        if (predicate(item)) return item;
        for (const child of item.children ?? []) {
            const result = find(child, predicate);
            if (result) return result;
        }
        return null;
    }

    function check(value, message) {
        if (!value) console.log("CHECK_FAIL", message);
    }

    Timer {
        interval: 250
        running: true
        onTriggered: {
            const windows = root.find(page, item => item.orientation === ListView.Vertical);
            const desktops = root.find(page, item => item.orientation === ListView.Horizontal);
            const button = root.find(page, item => typeof item.clicked === "function" && item.icon?.name === "desktop");
            root.check(windows.visible && !desktops.visible && desktops.count === 0, "initial windows page");
            input.mouseClick(button, button.width / 2, button.height / 2);
            root.check(!windows.visible && desktops.visible && desktops.count === 5, "separate desktop page");
            root.check(desktops.currentIndex === 1, "current monitor desktop selected");
            input.keyClick(Qt.Key_Right);
            input.keyClick(Qt.Key_Return);
            root.check(TouchpadGestures.command === "hl.dsp.focus({ workspace = 3 })", "keyboard selection");
            page.backToWindows();

            TouchpadGestures.command = "";
            preview.visible = true;
            input.mouseClick(preview, preview.width / 2, preview.height / 2, Qt.RightButton);
            const menu = input.findChild(preview, "taskWindowMenu");
            input.tryCompare(menu, "opened", true);
            const move = menu.itemAt(0);
            input.mouseClick(move, move.width / 2, move.height / 2);
            root.check(page.choosingDesktop && page.windowToMove === "0xabc", "destination opened from window");
            preview.visible = false;
            input.tryCompare(menu, "visible", false);
            input.keyClick(Qt.Key_Right);
            input.keyClick(Qt.Key_Return);
            root.check(TouchpadGestures.command === 'hl.dsp.window.move({ workspace = 3, follow = false, window = "address:0xabc" })', "keyboard move from window menu");
            TouchpadGestures.command = "";
            page.selectDesktop(2);
            root.check(!page.choosingDesktop && !TouchpadGestures.command, "same desktop cancels move");
            page.chooseDesktop("0xabc");
            page.selectDesktop(5);
            root.check(TouchpadGestures.command === 'hl.dsp.window.move({ workspace = 5, follow = false, window = "address:0xabc" })', "move window to new desktop");
            TouchpadGestures.command = "";
            HyprlandData.windowByAddress = ({});
            page.selectDesktop(1);
            root.check(!page.choosingDesktop && !TouchpadGestures.command, "closed window cancels move");
            console.log("DRIVER_PASS");
            Qt.quit();
        }
    }
}
