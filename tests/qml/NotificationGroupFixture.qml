import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

FloatingWindow {
    id: root
    title: "Notification group"
    implicitWidth: 420
    implicitHeight: Math.round(feed.contentHeight + 24)
    color: Appearance.colors.colLayer1
    readonly property string pictureName: Quickshell.env("VELORA_NOTIFICATION_PICTURE") ?? ""
    readonly property bool picture: !!pictureName
    readonly property double now: Date.now()
    property real heightBeforeActions: 0
    property real bodyWidth: 0
    property int stage: 0
    property var messages: [
        {notificationId: 18, summary: "Встреча", body: "Начало в 15:00.", actions: [], image: "", time: now-240000},
        {notificationId: 19, summary: "Команда", body: "<b>Алексей</b><br/>Добавил пару примеров.", actions: [], image: "", time: now-120000},
        {notificationId: 20, summary: "Команда", body: "<b>Анна</b><br/>Макеты готовы к просмотру.", actions: [{identifier:"default", text:"Открыть"}, {identifier:"read", text:"Прочитано"}], image: "", time: now}
    ]
    readonly property var systemMessages: [
        {notificationId: 25, summary: "Энергосбережение выключено", body: "Ноутбук подключён к сети.", appIcon: "battery-good-charging-symbolic", actions: [], time: now-1200000},
        {notificationId: 26, summary: "Микрофон снова подключён", body: "Если звук в приложении пропал, выключите и снова включите в нём микрофон.", appIcon: "audio-input-microphone", actions: [], time: now-360000}
    ]
    function find(node, predicate) {
        if (!node) return null;
        if (predicate(node)) return node;
        for (const child of node.children ?? []) {
            const result = find(child, predicate);
            if (result) return result;
        }
        return null;
    }
    function entry(id) { return find(feed, n => n.notificationObject?.notificationId === id); }
    function part(item, name) { return find(item, n => n.objectName === name); }
    function closeAligned(item) {
        const close = part(item, "notificationDismiss"), icon = part(item, "notificationIcon");
        const center = close.mapToItem(icon, close.width / 2, close.height / 2);
        return Math.abs(center.x - center.y) < 0.1 && Math.abs(center.x - 0.09 * icon.width) < 1;
    }
    function check(ok, reason) {
        if (!ok) { console.log("CHECK_FAIL", stage, reason); Qt.quit(); }
        return ok;
    }
    Connections {
        target: Notifications
        function onDiscard(id) { if (!root.picture) root.messages = root.messages.filter(n => n.notificationId !== id); }
    }
    Component.onCompleted: if (picture) MaterialThemeLoader.reapplyTheme(true)
    StyledListView {
        id: feed
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12
        model: root.picture ? 2 : 1
        delegate: NotificationGroup {
            required property int index
            width: ListView.view.width
            expanded: !root.picture || (root.pictureName === "chat" ? index === 0 : root.pictureName === "system" && index === 1)
            notificationGroup: index === 0 ? {appName:"Telegram Desktop", appIcon:"org.telegram.desktop", desktopEntry:"org.telegram.desktop", notifications:root.messages, time:root.now}
                : {appName:"Система", notifications:root.systemMessages, time:root.now-360000}
        }
    }
    Timer {
        interval: 240; running: !root.picture; repeat: true
        onTriggered: {
            const group = feed.itemAtIndex(0);
            const a = root.entry(20), b = root.entry(19), c = root.entry(18);
            if (!group || (root.stage < 4 && (!a || !b || !c))) return;
            switch (root.stage) {
            case 0: {
                if (!root.check(a.heading === "Анна" && a.showContext && b.heading === "Алексей" && !b.showContext && c.heading === "Встреча" && !c.showContext && c.body === "Начало в 15:00.", "sender, conversation and normal title")) return;
                const head = root.part(b, "notificationHeadline"), body = root.part(b, "notificationMessageBody");
                const titlePos = head.mapToItem(b, 0, 0), bodyPos = body.mapToItem(b, 0, 0);
                if (!root.check(head.font.pixelSize > body.font.pixelSize && head.font.weight > body.font.weight && bodyPos.y >= titlePos.y + head.height && titlePos.x === bodyPos.x, "title and body hierarchy")) return;
                if (!root.check(a.height !== b.height && root.closeAligned(a) && root.closeAligned(b), "close stays on the same icon corner at different heights")) return;
                root.heightBeforeActions = b.height;
                root.bodyWidth = body.width;
                b.forceActiveFocus();
                break;
            }
            case 1: {
                const copy = root.part(b, "notificationCopy");
                if (!root.check(b.toolsVisible && copy.visible && b.height === root.heightBeforeActions && root.part(b, "notificationMessageBody").width === root.bodyWidth, "direct actions without layout shift")) return;
                copy.clicked();
                if (!root.check(Quickshell.clipboardText === "Алексей\nДобавил пару примеров.", "copy readable text " + JSON.stringify(Quickshell.clipboardText))) return;
                a.menuRequested(24, 16);
                break;
            }
            case 2: {
                const menu = group.data.find(n => n.objectName === "notificationContextMenu");
                if (!root.check(menu?.visible && group.actionNotificationId === 20 && menu.count === 4, "native and local actions in menu")) return;
                root.messages = [...root.messages, {notificationId:21, summary:"Команда", body:"<strong>Олег</strong>\nЕщё один пример", actions:[], image:"", time:root.now}];
                break;
            }
            case 3: {
                const menu = group.data.find(n => n.objectName === "notificationContextMenu");
                if (!root.check(a.menuOpen && !a.showContext && a.heading === "Анна" && !root.entry(21).menuOpen, "insertion keeps the correct owner")) return;
                menu.itemAt(1).triggered();
                menu.close();
                if (!root.check(Notifications.invoked === "20/read", "action delivered to its source")) return;
                b.forceActiveFocus();
                root.part(b, "notificationDismiss").clicked();
                break;
            }
            case 4:
                if (Notifications.dismissed !== 19) return;
                group.toggleExpanded();
                if (!root.check(group.stackDepth === 2 && group.actionNotificationId === null, "collapsed stack")) return;
                break;
            case 5: {
                const first = root.entry(21);
                if (!root.check(first?.stacked && first.heading === "Олег" && first.body === "Ещё один пример", "compact preview")) return;
                first.activate();
                if (!root.check(group.expanded && group.messages.length === 3, "open whole stack")) return;
                Config.options.appearance.animationSpeed = 0;
                break;
            }
            case 6: {
                group.toggleExpanded();
                break;
            }
            case 7: {
                const first = root.entry(21);
                if (!root.check(group.stackDepth === 2 && Math.abs(group.implicitHeight - first.height - group.sheetCount * 3) < 1, "reduced motion settles to the compact height")) return;
                Config.options.appearance.animationSpeed = 1;
                first.dismiss();
                root.messages = [...root.messages,{notificationId:22,summary:"Новое",body:"Пришло во время удаления",actions:[],time:root.now}];
                break;
            }
            case 8: {
                const first = root.entry(22);
                if (!root.check(Notifications.dismissed === 21 && !root.entry(21) && first?.exitProgress === 0 && first.swipeOffset === 0, "new arrival inherited the previous dismissal")) return;
                first.dismiss();
                break;
            }
            case 9: {
                const first = root.entry(20);
                if (!root.check(Notifications.dismissed === 22 && first?.notificationObject.notificationId === 20 && first.exitProgress === 0 && first.width > 0, "replacement state "+[Notifications.dismissed,first?.messageId,first?.exitProgress,first?.width,group.messages.map(n=>n.notificationId)])) return;
                Notifications.discardNotification(18);
                first.dismiss();
                break;
            }
            case 10: {
                if (!root.check(Notifications.dismissed === 20 && root.messages.length === 0, "last notification survived dismissal")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            }
            root.stage++;
        }
    }
    Timer { interval: 9000; running: !root.picture; onTriggered: { console.log("CHECK_FAIL timeout", root.stage); Qt.quit(); } }
}
