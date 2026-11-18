import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common.widgets
import qs.services

FloatingWindow {
    id: root
    implicitWidth: 420
    implicitHeight: 320
    property int step: 0
    property int removedId: -1
    property double checkAfter: 0
    property var discards: []
    property var timeouts: []
    property real nextRowY: 0
    property bool rowMoved: false

    NotificationListView { id: feed; anchors.fill: parent }
    TestCase { id: input; when: false }
    Process { id: sender }

    function post(app, title, lifetime, transient = false) {
        sender.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
            app, "0", "", title, "Body", "[]", transient ? "{'transient': <true>}" : "{}", String(lifetime)];
        sender.running = true;
    }
    function fail(reason) {
        console.log("CHECK_FAIL", step, reason);
        Qt.quit();
    }
    Connections {
        target: Notifications
        function onDiscard(id) { root.discards.push(id); }
        function onTimeout(id) { root.timeouts.push(id); }
    }
    Timer {
        interval: 10
        repeat: true
        running: root.step === 4 && !root.rowMoved
        onTriggered: {
            const group = feed.itemAtIndex(0);
            if (group?.notificationCount !== 2) return;
            const next = input.findChild(group, "notificationHistory").itemAtIndex(0);
            if (!next) return;
            const y = next.mapToItem(feed, 0, 0).y;
            if (y > 2 && y < root.nextRowY - 3) root.rowMoved = true;
        }
    }
    Timer {
        interval: 40
        repeat: true
        running: true
        onTriggered: {
            if (sender.running) return;
            switch (root.step) {
            case 0:
                if (Notifications.silent) Notifications.toggleSilent();
                root.post("Chat", "Earlier", 0);
                break;
            case 1:
                if (Notifications.list.length !== 1) return;
                root.post("Chat", "Latest", 1100);
                break;
            case 2: {
                const group = feed.itemAtIndex(0);
                if (group?.notificationCount !== 2) return;
                const front = input.findChild(group, "notificationFront");
                if (!front || front.summary !== "Latest") return;
                if (!front.notificationObject.timer?.running) { root.fail("expected a pending popup timeout"); return; }
                root.removedId = front.messageId;
                group.toggleExpanded();
                input.mouseMove(front, 70, 18);
                break;
            }
            case 3: {
                const group = feed.itemAtIndex(0);
                const front = input.findChild(group, "notificationFront");
                const close = input.findChild(front, "notificationDismiss");
                const next = input.findChild(group, "notificationHistory").itemAtIndex(0);
                if (!close?.enabled || group.reveal !== 1 || !next) return;
                root.nextRowY = next.mapToItem(feed, 0, 0).y;
                input.mouseClick(close, close.width / 2, close.height / 2);
                root.checkAfter = Date.now() + 1300;
                break;
            }
            case 4: {
                if (Date.now() < root.checkAfter) return;
                if (!root.rowMoved) { root.fail("next row jumped into the vacated space"); return; }
                const group = feed.itemAtIndex(0);
                if (group?.notificationCount !== 1 || group.notifications[0].summary !== "Earlier"
                    || root.discards.length !== 1 || root.discards[0] !== root.removedId || root.timeouts.includes(root.removedId)) {
                    root.fail("unexpected state after the popup deadline " + JSON.stringify([root.discards, root.timeouts, group?.notificationCount])); return;
                }
                root.post("Calendar", "Meeting", 800);
                break;
            }
            case 5:
                if (feed.count !== 2) return;
                Notifications.discardAllNotifications();
                root.checkAfter = Date.now() + 950;
                break;
            case 6:
                if (Date.now() < root.checkAfter) return;
                if (feed.count || Notifications.list.length || root.timeouts.length || root.discards.length !== 1) {
                    root.fail("callbacks after clearing the list"); return;
                }
                root.post("Calendar", "Keep in history", 350);
                break;
            case 7: {
                if (root.timeouts.length === 0) return;
                const saved = Notifications.list[0];
                if (saved?.summary !== "Keep in history" || saved.popup || saved.timer) { root.fail("normal banner timeout"); return; }
                root.post("Calendar", "Transient", 350, true);
                break;
            }
            case 8: {
                if (root.discards.length === 1) return;
                const saved = Notifications.list[0];
                if (Notifications.list.length !== 1 || saved.summary !== "Keep in history") { root.fail("transient timeout affected its neighbour"); return; }
                sender.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                    "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.CloseNotification",
                    String(saved.notification.id)];
                sender.running = true;
                break;
            }
            case 9:
                if (feed.count) return;
                if (root.discards.length !== 3 || Notifications.list.length) { root.fail("sender withdrawal"); return; }
                console.log("DRIVER_PASS");
                Qt.quit();
                return;
            }
            root.step++;
        }
    }
    Timer { interval: 9000; running: true; onTriggered: root.fail("timeout"); }
}
