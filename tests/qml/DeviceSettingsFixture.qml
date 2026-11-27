import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

Item {
    id: root
    required property var host
    required property var search
    required property var navigation
    readonly property var page: host.currentPageItem
    property int step: 0
    property var returnRow
    TestCase { id: input; when: false }
    FileView { id: senderRegistry; path: Directories.notificationAppsPath }
    function find(node, match) {
        if (!node) return null;
        if (match(node)) return node;
        for (const child of node.children ?? []) {
            const item = find(child, match);
            if (item) return item;
        }
        return null;
    }
    function row(key) { return host.findSection(page, key); }
    function check(condition, label) {
        if (!condition) { console.log("CHECK_FAIL", step, label); Qt.quit(); }
        return condition;
    }
    Timer {
        interval: 175; running: true; repeat: true
        onTriggered: {
            if (!Config.ready || (!root.page?.pageShown && root.step !== 6)) return;
            switch (root.step) {
            case 0:
                Config.options.language.ui = "ru_RU";
                root.host.width = 760;
                GestureSettings.gestures = [
                    {id:"workspaces",fingers:4,direction:"horizontal",action:"workspace",default_action:"workspace",description:"Switch workspaces"},
                    {id:"volume",fingers:3,direction:"vertical",mods:"CTRL",action:"volume",default_action:"volume",description:"Volume"}
                ];
                break;
            case 1: {
                const pad = root.find(root.page, n => n.objectName === "pointerTestArea");
                const ruler = root.find(pad, n => n.objectName === "pointerTestList");
                input.mouseMove(pad, 30, 32);
                input.mouseMove(pad, 62, 45);
                input.mouseClick(pad, 50, 44, Qt.RightButton);
                input.mouseWheel(pad, 50, 44, 0, -120);
                if (!root.check(pad.trail.length >= 2 && pad.lastClick === Translation.tr("Right click") && ruler.wheelArea.targetY > 0, "real pointer motion, click and wheel input")) return;
                const selector = root.find(root.page, n => n.objectName === "inputDeviceSelector");
                selector.selected(true);
                if (!root.check(root.page.editingTouchpad && !pad.visible, "touchpad controls")) return;
                const touchpad = root.find(root.page, n => n.objectName === "touchpadTestArea");
                const touchScroll = root.find(touchpad, n => n.objectName === "touchpadTestScroll");
                input.mouseClick(touchpad, 60, 44, Qt.LeftButton);
                input.mouseWheel(touchpad, 60, 44, 0, -120);
                if (!root.check(touchpad.feedback === Translation.tr("Left click") && touchScroll.wheelArea.targetY > 0, "touchpad click and scrolling")) return;
                selector.selected(false);
                root.host.openPage("mouse", Translation.tr("Gestures"));
                break;
            }
            case 2:
                if (root.page.tab !== "gestures") return;
                root.row("modified").clicked();
                break;
            case 3:
                root.returnRow = root.find(root.page, n => n.modelData?.id === "volume" && n.title);
                root.returnRow.clicked();
                break;
            case 4: {
                const editor = root.find(root.page, n => n.objectName === "gestureActionPicker");
                if (!root.check(root.page.navigationTrail.map(t => t.key).join("/") === "gestures/modified/gestureAction" && editor.currentValue === "volume", "selected gesture editor")) return;
                editor.customEntered("example command");
                if (!root.check(editor.customActive && GestureSettings.overrides.volume.command === "example command", "custom action")) return;
                root.host.goBack();
                break;
            }
            case 5:
                if (!root.check(root.page.tab === "modified" && root.returnRow.activeFocus, "back to selected gesture")) return;
                root.navigation.searchText = Translation.tr("Physical right click");
                break;
            case 6: {
                const hit = root.search.results.find(r => r.title === Translation.tr("Physical right click"));
                if (!hit) return;
                root.search.resultChosen(hit.pageIndex, hit.item);
                break;
            }
            case 7:
                if (root.page.tab !== "touchpad") return;
                root.host.openPage("displays");
                break;
            case 8:
                if (root.host.currentPageData.key !== "displays") return;
                HyprlandMonitors.monitors = [{name:"eDP-1",width:1920,height:1080,scale:1,transform:0,refreshRate:60,availableModes:["1920x1080@60Hz"], focused:true}];
                break;
            case 9:
                if (!root.check(!root.row(Translation.tr("Arrangement")).visible && root.page.modeSummary.includes("1920"), "single display summary")) return;
                root.row("mode").clicked();
                break;
            case 10:
                if (!root.check(root.page.tab === "mode" && !!root.find(root.page, n => n.text === Translation.tr("Resolution")), "display mode editor")) return;
                root.host.goBack();
                HyprlandMonitors.monitors = [...HyprlandMonitors.monitors, {name:"HDMI-A-1",width:1920,height:1080,scale:1,transform:0,x:1920,y:0,refreshRate:60,availableModes:["1920x1080@60Hz"]}];
                break;
            case 11:
                if (!root.check(root.row(Translation.tr("Arrangement")).visible, "multi-display canvas")) return;
                root.host.openPage("notifications");
                break;
            case 12:
                if (root.host.currentPageData.key !== "notifications") return;
                if (!root.check(!root.find(root.page, n => n.objectName === "bannerPositionPicker" && n.shown)
                        && root.find(root.page, n => n.objectName === "notificationQuietToggle").enabled, "overview starts with quiet mode, preview stays in banner settings")) return;
                root.row("banners").clicked();
                break;
            case 13: {
                const picker = root.find(root.page, n => n.objectName === "bannerPositionPicker" && n.shown);
                const snapshot = input.grabImage(picker);
                const colors = new Set();
                for (let y = 16; y < snapshot.height - 16; y += 16)
                    for (let x = 16; x < snapshot.width - 16; x += 16) colors.add(snapshot.pixel(x, y).toString());
                if (!root.check(colors.size > 3, "desktop and sample banner are rendered")) return;
                const corner = root.find(picker, n => n.modelData?.key === "bottomLeft");
                corner.clicked();
                if (!root.check(picker.width > 100 && NotificationPreferences.corner === "bottomLeft", "corner selection")) return;
                for (const key of ["topCenter", "bottomCenter"]) {
                    const target = root.find(picker, n => n.modelData?.key === key);
                    if (!root.check(!!target && target.x === target.width, "center hit area")) return;
                    input.mouseClick(target);
                    if (!root.check(NotificationPreferences.corner === key && NotificationPreferences.centered
                            && !NotificationPreferences.left && !NotificationPreferences.right
                            && NotificationPreferences.top === (key === "topCenter"), "center banner " + key)) return;
                }
                root.host.goBack();
                root.row("quiet").clicked();
                break;
            }
            case 14:
                if (!root.check(root.row("quietDuration").options.length === 5, "duration choices")) return;
                root.host.goBack();
                Config.options.notifications.apps = {Messages:{mode:"silent"}, NeverSent:{mode:"banners",added:true}};
                senderRegistry.setText(JSON.stringify({
                    Calendar:{name:"Calendar",lastSeen:1500}, Mail:{name:"Mail",lastSeen:3000},
                    Messages:{name:"Messages",lastSeen:4000}, Music:{name:"Music",lastSeen:2000}
                }));
                break;
            case 15: {
                if (root.page.recentApps.length !== 3) return;
                if (!root.check(root.page.recentApps.map(a => a.key).join("/") === "Messages/Mail/Music"
                        && root.page.apps.some(a => a.key === "NeverSent"), "three latest sending apps, unseen rules only in the full list")) return;
                const recent = root.find(root.page, n => n.appKey === "Messages" && n.summaryOnly);
                if (!recent) return;
                recent.toggleExpanded();
                const app = root.find(root.page, n => n.appKey === "Messages" && !n.summaryOnly);
                if (!root.check(root.page.tab === "apps" && app.expanded && app.mode === "silent", "open recent sender's rule")) return;
                app.setRule({mode:"banners", bypassDnd:true});
                if (!root.check(Config.options.notifications.apps.Messages.bypassDnd, "per-app exception")) return;
                root.host.goBack();
                senderRegistry.setText(JSON.stringify({Mail:{name:"Mail",lastSeen:5000}, Messages:{name:"Messages",lastSeen:4000}}));
                break;
            }
            case 16: {
                if (root.page.recentApps.length !== 2) return;
                if (!root.check(root.page.recentApps[0].key === "Mail" && root.page.tab === "overview", "recent senders refresh when another app sends")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            }
            root.step++;
        }
    }
    Timer { interval: 22000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", root.step); Qt.quit(); } }
}
