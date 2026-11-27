import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

ShellRoot {
    id: root
    readonly property var prefs: NotificationPreferences
    readonly property var notifications: Notifications
    property int step: 0
    property double timerDeadline: 0
    function check(ok, label) {
        if (!ok) { console.log("CHECK_FAIL", step, label); Qt.quit(); }
        return ok;
    }
    function send(app) {
        client.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
            app, "0", "", "Example", "Body", "[]", "{}", "0"];
        client.running = true;
    }
    function ipc(method, args = []) {
        client.command = ["qs", "-p", Quickshell.shellPath("shell.qml"), "ipc", "call", "notifications", method, ...args];
        client.running = true;
    }
    Process { id: client }
    Timer {
        interval: 80; running: true; repeat: true
        onTriggered: {
            if (!Config.ready || !Persistent.ready || client.running) return;
            const stamp = (day, hour) => new Date(2025, 9, day, hour, 0).getTime();
            switch (root.step) {
            case 0:
                if (!root.check(prefs.endOfWindow(stamp(12,23), "22:00", "07:00") === stamp(13,7)
                    && prefs.endOfWindow(stamp(13,2), "22:00", "07:00") === stamp(13,7)
                    && !prefs.endOfWindow(stamp(13,7), "22:00", "07:00")
                    && prefs.endOfWindow(stamp(13,9), "09:00", "11:00") === stamp(13,11)
                    && !prefs.endOfWindow(stamp(13,9), "09:00", "09:00"), "daily and overnight boundaries")) return;
                if (!root.check(prefs.corner === "topRight", "default Velora corner")) return;
                Config.options.panelFamily = "waffle";
                if (!root.check(prefs.corner === "bottomRight", "default waffle corner")) return;
                Config.options.panelFamily = "velora";
                prefs.schedule.from = Qt.formatTime(new Date(Date.now() - 3600000), "HH:mm");
                prefs.schedule.to = Qt.formatTime(new Date(Date.now() + 3600000), "HH:mm");
                prefs.schedule.enabled = true;
                break;
            case 1:
                if (!root.check(notifications.silent, "scheduled quiet hours")) return;
                root.ipc("toggleSilent");
                break;
            case 2:
                if (!root.check(!notifications.silent && prefs.state.skippedScheduleEnd === prefs.scheduledEnd, "manual override for this schedule")) return;
                prefs.schedule.enabled = false;
                root.ipc("silenceFor", ["30"]);
                break;
            case 3:
                if (!root.check(notifications.silent && !prefs.state.silent && prefs.state.quietUntil > Date.now(), "timed IPC pause")) return;
                Config.options.notifications.apps = {Calls:{mode:"banners",bypassDnd:true}, Quiet:{mode:"silent",bypassDnd:true}, Blocked:{mode:"off"}};
                root.send("Mail");
                break;
            case 4:
                if (!root.check(notifications.list.length === 1 && !notifications.popupList.length && notifications.unread === 1, "quiet delivery")) return;
                root.send("Calls");
                break;
            case 5:
                if (!root.check(notifications.popupList.length === 1 && notifications.unread === 2, "allowed caller")) return;
                root.send("Quiet");
                break;
            case 6:
                if (!root.check(notifications.list.length === 3 && notifications.popupList.length === 1, "list-only rule during pause")) return;
                root.send("Blocked");
                break;
            case 7:
                if (!root.check(notifications.list.length === 3 && notifications.unread === 3, "blocked sender")) return;
                Config.options.notifications.timeout = 350;
                root.ipc("previewBanner");
                break;
            case 8:
                if (!root.check(notifications.preview && notifications.popupList.length === 2 && notifications.list.length === 3
                    && notifications.unread === 3 && !notifications.seenApps[notifications.preview.appName], "preview outside history and sender registry")) return;
                if (!root.check(notifications.showPreview() && notifications.popupList.length === 2, "repeat replaces the sample")) return;
                root.timerDeadline = Date.now() + 430;
                break;
            case 9:
                if (Date.now() < root.timerDeadline) return;
                if (!root.check(!notifications.preview && notifications.popupList.length === 1, "preview timeout")) return;
                notifications.showPreview();
                GlobalStates.screenLocked = true;
                if (!root.check(!notifications.preview && !notifications.showPreview(), "locked desktop")) return;
                GlobalStates.screenLocked = false;
                prefs.state.quietUntil = Date.now() - 120000;
                if (!root.check(!notifications.silent, "expired timer")) return;
                root.ipc("setSilent", ["true"]);
                break;
            case 10:
                if (!root.check(notifications.silent && prefs.state.silent && !prefs.state.quietUntil, "old manual IPC")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            root.step++;
        }
    }
    Timer { interval: 12000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", root.step); Qt.quit(); } }
}
