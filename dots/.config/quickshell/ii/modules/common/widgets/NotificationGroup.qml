import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Notifications

MouseArea {
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    readonly property int notificationCount: notifications.length
    readonly property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false
    readonly property int sheetCount: Math.max(0, Math.min(notificationCount - 1, 2))
    readonly property int stackDepth: expanded ? 0 : sheetCount
    readonly property color cardColor: Appearance.colors.colLayer2Base
    readonly property var view: ListView.view
    property var actionNotificationId: null
    property bool interacted: false
    property real reveal: expanded ? 1 : 0
    readonly property bool keepHistory: expanded || reveal > 0
    readonly property var messages: keepHistory ? notifications.slice().reverse() : notifications.slice(-1)
    readonly property real viewportHeight: Math.max(100, view?.height ?? 500)
    readonly property real historyGap: multipleNotifications ? 5 * (1 - front.exitProgress) : 0
    readonly property real fullHistoryHeight: history.implicitHeight + historyGap
    // Reveal the first screen at a readable speed even when dozens of older messages follow it.
    readonly property real firstScreen: Math.min(fullHistoryHeight, viewportHeight)
    readonly property real revealedHeight: firstScreen * reveal + (fullHistoryHeight - firstScreen) * Math.pow(reveal, 5)
    implicitHeight: front.height + Math.max(sheetCount * 3 * (1 - reveal), revealedHeight)
    Behavior on reveal {
        NumberAnimation { duration: Appearance.scaledDuration(285); easing.type: Easing.InOutSine }
    }
    onNotificationsChanged: if (actionNotificationId !== null && !notifications.some(n => n.notificationId === actionNotificationId)) messageMenu.close()
    onExpandedChanged: if (!expanded && messageMenu.visible) messageMenu.close()
    hoverEnabled: true

    function toggleExpanded() { interacted = true; expanded = !expanded; }
    function updateTimeouts() {
        if (!popup) return;
        for (const n of notifications) {
            if (containsMouse || messageMenu.visible) Notifications.cancelTimeout(n.notificationId);
            else Notifications.timeoutNotification(n.notificationId);
        }
    }
    onContainsMouseChanged: updateTimeouts()

    TextEdit { id: clipboardDocument; visible: false; readOnly: true; textFormat: TextEdit.RichText }
    function copyMessage(n) {
        clipboardDocument.text = NotificationUtils.processNotificationBody(n.body, n.appName || n.summary);
        const plain = clipboardDocument.getText(0, clipboardDocument.length).replace(/[\u2028\u2029]/g, "\n");
        Quickshell.clipboardText = plain.trim() || n.summary;
        clipboardDocument.clear();
    }
    property var dismissals: []
    function dismissMessage(id, left = false, swiped = false) {
        if (id === undefined || dismissals.some(d => d.id === id)) return;
        interacted = true;
        dismissals = [...dismissals, {id, left, swiped}];
        const timer = dismissTimer.createObject(root, {notificationId: id});
        timer.start();
    }
    Component {
        id: dismissTimer
        Timer {
            required property int notificationId
            interval: Appearance.scaledDuration(150)
            onTriggered: {
                const id = notificationId;
                if (root.notifications.some(n => n.notificationId === id)) Notifications.discardNotification(id);
                root.dismissals = root.dismissals.filter(d => d.id !== id);
                destroy();
            }
        }
    }
    function openMessageMenu(item, x, y) {
        const point = item.mapToItem(root, x, y);
        root.actionNotificationId = item.notificationObject.notificationId;
        messageMenu.x = point.x;
        messageMenu.y = point.y;
        messageMenu.open();
    }
    Menu {
        id: messageMenu
        objectName: "notificationContextMenu"
        parent: root
        popupType: Popup.Window
        margins: 6
        padding: 4
        implicitWidth: 214
        readonly property var message: root.notifications.find(n => n.notificationId === root.actionNotificationId) ?? null
        readonly property var entries: {
            const n = message;
            if (!n) return [];
            const entries = (n.actions ?? []).map(a => ({text: a.text, icon: a.identifier === "default" ? "open_in_new" : "", run: () => Notifications.attemptInvokeAction(n.notificationId, a.identifier)}));
            entries.push({text: Translation.tr("Copy text"), icon: "content_copy", run: () => root.copyMessage(n)});
            entries.push({text: Translation.tr("Remove notification"), icon: "delete_outline", run: () => root.dismissMessage(n.notificationId)});
            return entries;
        }
        onVisibleChanged: root.updateTimeouts()
        onClosed: root.actionNotificationId = null
        background: Rectangle {
            radius: Appearance.popup.smallRadius
            color: Appearance.popup.colBackground
            border.width: 1
            border.color: Appearance.popup.colBorder
        }
        Instantiator {
            model: messageMenu.entries
            delegate: MenuItem {
                id: choice
                required property var modelData
                text: modelData.text
                implicitHeight: 34
                leftPadding: 10
                rightPadding: 10
                onTriggered: modelData.run()
                background: Rectangle { radius: 6; color: choice.highlighted ? Appearance.colors.colSecondaryContainer : "transparent" }
                contentItem: RowLayout {
                    spacing: 9
                    MaterialSymbol { text: choice.modelData.icon; iconSize: 17; Layout.preferredWidth: 17; color: Appearance.colors.colOnLayer2 }
                    StyledText { Layout.fillWidth: true; text: choice.text; textFormat: Text.PlainText; elide: Text.ElideRight; color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.small }
                }
            }
            onObjectAdded: (index, item) => messageMenu.insertItem(index, item)
            onObjectRemoved: (index, item) => messageMenu.removeItem(item)
        }
    }

    Item {
        id: stack
        width: root.width
        height: root.implicitHeight
        property real exitOffset: 0
        x: exitOffset || (root.view?.dragIndex === root.index ? root.view.dragDistance : 0)

        NumberAnimation {
            id: dismissStack
            target: stack
            property: "exitOffset"
            duration: Appearance.animation.elementMove.duration
            easing.type: Easing.InCubic
            property var ids: []
            onFinished: {
                for (const id of ids) if (root.notifications.some(n => n.notificationId === id)) Notifications.discardNotification(id);
                stack.exitOffset = 0;
            }
        }
        function dismiss(left) {
            if (dismissStack.running) return;
            dismissStack.ids = root.notifications.map(n => n.notificationId);
            dismissStack.from = stack.x;
            dismissStack.to = (left ? -1 : 1) * (width + 20);
            root.view?.resetDrag();
            dismissStack.start();
        }
        Repeater {
            model: root.sheetCount
            Rectangle {
                required property int index
                readonly property int depth: root.sheetCount - index
                x: 6 * depth
                y: front.height - height + depth * 3 * (1 - root.reveal)
                width: Math.max(0, parent.width - 2 * x)
                height: Math.min(front.height, 32)
                radius: Appearance.rounding.normal
                opacity: (depth === 1 ? 0.66 : 0.4) * (1 - root.reveal)
                visible: opacity > 0
                color: Appearance.colors.colLayer2Base
            }
        }
        DragManager {
            anchors.fill: parent
            enabled: root.stackDepth > 0
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            property bool consumed: false
            onPressed: mouse => {
                consumed = mouse.button === Qt.RightButton;
                if (consumed) {
                    const first = front;
                    if (first) root.openMessageMenu(first, mouse.x, mouse.y);
                }
            }
            onPressAndHold: mouse => {
                const first = front;
                if (first && mouse.button === Qt.LeftButton && !consumed) {
                    consumed = true;
                    root.openMessageMenu(first, mouse.x, mouse.y);
                }
            }
            onDragDiffXChanged: {
                if (!root.view || !dragging) return;
                if (Math.abs(dragDiffX) > Qt.styleHints.startDragDistance) consumed = true;
                root.view.dragIndex = root.index;
                root.view.dragDistance = dragDiffX;
            }
            onDragReleased: (x, y) => {
                if (Math.abs(x) > 70) {
                    consumed = true;
                    stack.dismiss(x < 0);
                } else root.view?.resetDrag();
            }
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) stack.dismiss(false);
                else if (mouse.button === Qt.LeftButton && !consumed) root.toggleExpanded();
            }
        }
        Item {
            id: historyClip
            y: front.height
            width: parent.width
            height: root.revealedHeight
            onHeightChanged: viewportUpdate.start()
            visible: height > 0
            enabled: root.expanded
            clip: true

            Column {
                id: history
                objectName: "notificationHistory"
                y: root.historyGap - 12 * (1 - root.reveal)
                width: parent.width
                opacity: root.reveal
                spacing: 5
                readonly property int count: rows.count
                function itemAtIndex(index) { return rows.itemAt(index)?.item ?? null; }
                // Leave scrolling to the outer list. Offscreen rows keep their measured space.
                readonly property real viewportStart: (root.view?.contentY ?? 0) - root.y - historyClip.y
                onViewportStartChanged: viewportUpdate.start()
                onWidthChanged: viewportUpdate.start()
                onImplicitHeightChanged: viewportUpdate.start()
                Timer {
                    id: viewportUpdate
                    interval: 0
                    onTriggered: {
                        history.forceLayout();
                        const start = history.viewportStart - 96;
                        const end = Math.min(historyClip.height, history.viewportStart + root.viewportHeight) + 96;
                        for (let i = 0; i < rows.count; i++) {
                            const holder = rows.itemAt(i);
                            if (holder) holder.active = holder.y + holder.height >= start && holder.y <= end;
                        }
                    }
                }
                Repeater {
                    id: rows
                    onItemAdded: viewportUpdate.start()
                    model: ScriptModel { values: root.messages.slice(1) }
                    delegate: Loader {
                        id: holder
                        required property int index
                        required property var modelData
                        property real measuredHeight: 74
                        width: history.width
                        height: item?.implicitHeight ?? measuredHeight
                        active: false
                        onLoaded: measuredHeight = item.implicitHeight
                        sourceComponent: NotificationItem {
                            id: row
                            index: holder.index + 1
                            group: root
                            notificationObject: holder.modelData
                            previousNotification: root.messages[holder.index]
                            onImplicitHeightChanged: if (implicitHeight > 0) holder.measuredHeight = implicitHeight
                            onMenuRequested: (x, y) => root.openMessageMenu(row, x, y)
                            onCopyRequested: root.copyMessage(notificationObject)
                        }
                    }
                }
            }
        }
        NotificationItem {
            id: front
            objectName: "notificationFront"
            index: 0
            firstInGroup: true
            width: parent.width
            visible: root.notificationCount > 0
            height: visible ? implicitHeight : 0
            clip: frontResize.running || exitProgress > 0
            Behavior on height {
                // The second row has already moved into place when it becomes the front.
                enabled: root.interacted && !front.closing && !(root.expanded && root.dismissals.length)
                NumberAnimation { id: frontResize; duration: Appearance.scaledDuration(180); easing.type: Easing.OutCubic }
            }
            group: root
            notificationObject: root.notifications[root.notificationCount - 1] ?? ({})
            onMenuRequested: (x, y) => root.openMessageMenu(front, x, y)
            onCopyRequested: root.copyMessage(notificationObject)
        }
    }
}
