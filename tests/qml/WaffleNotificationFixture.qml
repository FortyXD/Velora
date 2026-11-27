import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.waffle.looks
import qs.modules.waffle.notificationCenter

FloatingWindow {
    id: root
    implicitWidth: 800
    implicitHeight: 440
    visible: true
    property int step: 0
    property var messages: [
        {notificationId: 17, summary: "Встреча", body: "Через десять минут", image: "", popup: true, time: Date.now(), actions: [
            {identifier: "join", text: "Присоединиться к встрече"}, {identifier: "later", text: "Напомнить позже"}]},
        {notificationId: 18, summary: "Файл сохранён", body: "Отчёт.pdf", image: "", popup: true, time: Date.now(), actions: []}
    ]
    WListView {
        id: feed
        width: 270
        height: parent.height
        model: ScriptModel { values: root.messages; objectProp: "notificationId" }
        delegate: WSingleNotification {
            required property var modelData
            width: ListView.view.width
            notification: modelData
        }
    }
    TestCase { id: input; when: false }
    Connections {
        target: Notifications
        function onDiscard(id) { root.messages = root.messages.filter(n => n.notificationId !== id); }
    }
    function button(item, label) {
        if (item.text === label && typeof item.clicked === "function") return item;
        for (const child of item.children ?? []) {
            const found = button(child, label);
            if (found) return found;
        }
        return null;
    }
    function check(ok, reason) {
        if (!ok) { console.log("CHECK_FAIL", step, reason); Qt.quit(); }
        return ok;
    }
    Timer {
        interval: 35; repeat: true; running: true
        onTriggered: {
            const front = feed.itemAtIndex(0);
            if (!Config.ready || !front) return;
            if (root.step < 2) {
                const first = root.button(front, "Присоединиться к встрече");
                const second = root.button(front, "Напомнить позже");
                if (!first || !second) return;
                if (root.step === 0) {
                    if (!root.check(second.y >= first.y + first.height && second.width >= 240, "long actions stack")) return;
                    input.mouseClick(second, second.width / 2, second.height / 2);
                    if (!root.check(Notifications.invoked === "17/later", "selected action and notification ID")) return;
                    feed.width = 700;
                } else {
                    if (!root.check(first.y === second.y && second.x >= first.x + first.width, "actions share a row when they fit")) return;
                    Config.options.appearance.animationSpeed = 0;
                    front.dismiss();
                }
            } else {
                if (!root.check(front.notification?.notificationId === 18 && front.y === 0 && feed.contentHeight === front.height,
                                "no animated gap when motion is disabled")) return;
                console.log("DRIVER_PASS"); Qt.quit();
            }
            root.step++;
        }
    }
    Timer { interval: 5000; running: true; onTriggered: root.check(false, "timeout") }
}
