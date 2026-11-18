import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

FocusScope {
    id: root
    required property int index
    required property var notificationObject
    required property var group
    property bool firstInGroup: false
    property var previousNotification: null
    readonly property bool expanded: group.expanded
    readonly property bool stacked: group.stackDepth > 0
    readonly property bool menuOpen: group.actionNotificationId === notificationObject.notificationId
    readonly property Item focusedItem: Window.window?.activeFocusItem ?? null
    readonly property bool keyboardFocus: activeFocus && (focusedItem === root || !!focusedItem?.visualFocus)
    readonly property bool toolsVisible: hover.hovered || keyboardFocus || menuOpen || copyFeedback.running
    property real actionProgress: toolsVisible ? 1 : 0
    Behavior on actionProgress {
        NumberAnimation { duration: Appearance.scaledDuration(140); easing.type: Easing.OutCubic }
    }
    readonly property string appName: notificationObject.appName || group.notificationGroup?.appName || group.notificationGroup?.desktopEntry || ""
    readonly property string summary: notificationObject.summary ?? ""
    readonly property string formattedBody: NotificationUtils.processNotificationBody(notificationObject.body, appName || summary)
    // A bold first line followed by a break is how messaging clients supply a separate sender.
    readonly property var senderLine: /^\s*<(b|strong)>([^<>]+)<\/\1>\s*<br\s*\/?>\s*/i.exec(formattedBody)
    readonly property string heading: senderLine ? NotificationUtils.decodeEntities(senderLine[2]) : summary || appName || Translation.tr("Notifications")
    readonly property string body: senderLine ? formattedBody.slice(senderLine[0].length) : formattedBody
    readonly property bool showContext: !!senderLine && !!summary && summary !== heading && previousNotification?.summary !== summary
    readonly property bool critical: notificationObject.urgency === NotificationUrgency.Critical.toString()
    readonly property var closing: group.dismissals.find(d => d.id === notificationObject.notificationId) ?? null
    property real exitAmount: 0
    readonly property real exitProgress: closing ? exitAmount : 0
    onClosingChanged: {
        exitMotion.stop();
        exitAmount = 0;
        if (closing) exitMotion.start();
    }
    NumberAnimation {
        id: exitMotion
        target: root; property: "exitAmount"; from: 0; to: 1
        duration: Appearance.scaledDuration(150)
        easing.type: Easing.InOutSine
    }
    property real swipeOffset: 0
    readonly property var messageId: notificationObject.notificationId
    property var previousId
    property real arrival: 1
    onMessageIdChanged: {
        swipeOffset = 0;
        copyFeedback?.stop();
        if (firstInGroup && !group?.expanded && messageId !== undefined && group?.dismissals.some(d => d.id === previousId))
            arrivalMotion.restart();
        previousId = messageId;
    }
    NumberAnimation {
        id: arrivalMotion
        target: root; property: "arrival"; from: 0; to: 1
        duration: Appearance.scaledDuration(115); easing.type: Easing.OutCubic
    }
    readonly property bool showDisclosure: firstInGroup && (group.multipleNotifications || expanded || headline.truncated || bodyText.truncated)
    signal menuRequested(real x, real y)
    signal copyRequested()
    implicitHeight: card.implicitHeight * (firstInGroup && stacked ? 1 : 1 - exitProgress)
    clip: exitProgress > 0
    activeFocusOnTab: true
    Accessible.role: Accessible.ListItem
    Accessible.name: (appName && appName !== heading ? appName + ", " : "") + heading
    Accessible.onPressAction: activate()

    function copyText() {
        copyRequested();
        copyFeedback.restart();
    }
    function activate() {
        if (stacked) {
            group.toggleExpanded();
            return;
        }
        const action = notificationObject.actions?.find(a => a.identifier === "default");
        if (action) Notifications.attemptInvokeAction(notificationObject.notificationId, action.identifier);
        else if (!expanded && (headline.truncated || bodyText.truncated)) group.toggleExpanded();
        else menuRequested(width - 20, height / 2);
    }
    function dismiss(left = false, swiped = false) {
        group.dismissMessage(notificationObject.notificationId, left, swiped);
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) root.menuRequested(root.width - 20, root.height / 2);
        else if (event.matches(StandardKey.Copy)) root.copyText();
        else if (event.key === Qt.Key_Delete) root.dismiss();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.activate();
        else return;
        event.accepted = true;
    }
    HoverHandler { id: hover }
    Timer { id: copyFeedback; interval: 1100 }
    Rectangle {
        id: card
        readonly property real distance: root.closing?.swiped ? Math.max(0, width - Math.abs(root.swipeOffset)) : 12
        x: root.swipeOffset + (root.closing?.left ? -1 : 1) * distance * root.exitProgress
        opacity: (1 - root.exitProgress) * root.arrival
        width: root.width
        height: root.closing ? implicitHeight : root.height
        implicitHeight: Math.max(40, details.implicitHeight) + 22
        radius: Appearance.rounding.normal
        color: root.group.cardColor
        border.width: root.keyboardFocus || root.group.popup ? 1 : 0
        border.color: root.keyboardFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border

        DragManager {
            id: gesture
            anchors.fill: parent
            enabled: !root.stacked
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            property bool consumed: false
            onPressed: mouse => {
                consumed = mouse.button === Qt.RightButton;
                if (consumed) root.menuRequested(mouse.x, mouse.y);
            }
            onPressAndHold: mouse => {
                if (mouse.button === Qt.LeftButton && !consumed) {
                    consumed = true;
                    root.menuRequested(mouse.x, mouse.y);
                }
            }
            onDragDiffXChanged: {
                if (!dragging) return;
                if (Math.abs(dragDiffX) > Qt.styleHints.startDragDistance) consumed = true;
                root.swipeOffset = dragDiffX;
            }
            onDragReleased: (x, y) => {
                if (Math.abs(x) > 70) {
                    consumed = true;
                    root.dismiss(x < 0, true);
                } else root.swipeOffset = 0;
            }
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) root.dismiss();
                else if (mouse.button === Qt.LeftButton && !consumed) root.activate();
            }
        }
        NotificationAppIcon {
            id: icon
            objectName: "notificationIcon"
            anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
            implicitSize: 36
            shape: MaterialShape.Shape.Square
            imageRadius: width * 0.3
            appIconScale: 0.9
            color: showImage || showAppIcon ? Appearance.colors.colLayer3 : root.critical ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
            appName: root.appName
            desktopEntry: root.notificationObject.desktopEntry || root.group.notificationGroup?.desktopEntry || ""
            appIcon: root.notificationObject.appIcon || root.group.notificationGroup?.appIcon || ""
            summary: root.summary
            urgency: root.critical ? NotificationUrgency.Critical : NotificationUrgency.Normal
            image: root.notificationObject.image ?? ""
            HoverHandler { id: iconHover }
            StyledToolTip { text: root.appName; extraVisibleCondition: iconHover.hovered && !!root.appName; delay: 700 }
        }
        GridLayout {
            id: details
            anchors { left: icon.right; leftMargin: 11; right: parent.right; rightMargin: 13 }
            y: Math.max(11, (parent.height - implicitHeight) / 2)
            columns: 2
            rowSpacing: 2
            columnSpacing: 6
            StyledText {
                id: headline
                objectName: "notificationHeadline"
                Layout.row: 0
                Layout.column: 0
                Layout.fillWidth: true
                text: root.heading
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: root.expanded ? 2147483647 : 2
                elide: Text.ElideRight
                color: root.critical ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                font.variableAxes: Object.assign({}, Appearance.font.variableAxes.main, {wght: 680})
            }
            RowLayout {
                Layout.row: 0
                Layout.column: 1
                Layout.alignment: Qt.AlignTop | Qt.AlignRight
                spacing: 4
                Item {
                    implicitWidth: Math.max(stamp.implicitWidth, 24)
                    implicitHeight: 20
                    StyledText {
                        id: stamp
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        opacity: 1 - root.actionProgress
                        visible: opacity > 0
                        text: ((root.firstInGroup && root.group.multipleNotifications) || (root.group.popup && !root.expanded)) ? "" : NotificationUtils.getFriendlyNotifTimeString(root.notificationObject.time)
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    NotificationActionButton {
                        objectName: "notificationCopy"
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        opacity: root.actionProgress
                        visible: opacity > 0
                        enabled: root.toolsVisible
                        symbol: copyFeedback.running ? "check" : "content_copy"
                        buttonText: copyFeedback.running ? Translation.tr("Copied") : Translation.tr("Copy text")
                        onClicked: root.copyText()
                    }
                }
                NotificationGroupExpandButton {
                    objectName: "notificationDisclosure"
                    focusPolicy: Qt.TabFocus
                    visible: root.showDisclosure
                    count: root.group.notificationCount
                    expanded: root.expanded
                    Accessible.name: root.expanded ? Translation.tr("Collapse group") : Translation.tr("Expand group")
                    onClicked: root.group.toggleExpanded()
                    altAction: () => root.group.toggleExpanded()
                    StyledToolTip {
                        delay: 500
                        text: [root.appName, NotificationUtils.getFriendlyNotifTimeString(root.notificationObject.time)].filter(Boolean).join(" · ")
                    }
                }
            }
            StyledText {
                Layout.row: 1
                Layout.column: 0
                Layout.columnSpan: 2
                Layout.fillWidth: true
                visible: root.showContext
                text: root.summary
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.DemiBold
                font.variableAxes: Object.assign({}, Appearance.font.variableAxes.main, {wght: 540})
            }
            StyledText {
                id: bodyText
                objectName: "notificationMessageBody"
                Layout.row: root.showContext ? 2 : 1
                Layout.column: 0
                Layout.columnSpan: 2
                Layout.fillWidth: true
                visible: !!root.body
                text: root.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: root.expanded ? 2147483647 : 2
                elide: Text.ElideRight
                color: Appearance.m3colors.m3onSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smallie + 1
                font.weight: Font.Normal
                font.variableAxes: Object.assign({}, Appearance.font.variableAxes.main, {wght: 400})
                onLinkActivated: link => {
                    if (root.stacked) root.group.toggleExpanded();
                    else if (StringUtils.parseWebUrl(link)) { Qt.openUrlExternally(link); GlobalStates.closeSidebars(); }
                }
                PointingHandLinkHover {}
            }
        }
        NotificationActionButton {
            objectName: "notificationDismiss"
            // Both offsets locate the same point on the icon's rounded corner at every card height.
            readonly property real cornerInset: Math.round(icon.imageRadius * (1 - Math.SQRT1_2))
            anchors {
                horizontalCenter: icon.left
                verticalCenter: icon.top
                horizontalCenterOffset: cornerInset
                verticalCenterOffset: cornerInset
                alignWhenCentered: false
            }
            opacity: root.actionProgress
            scale: 0.88 + 0.12 * root.actionProgress
            visible: opacity > 0
            enabled: root.toolsVisible
            symbol: "close"
            buttonText: Translation.tr("Remove notification")
            destructive: true
            colBackground: Appearance.m3colors.m3surfaceContainerHighest
            onClicked: root.dismiss()
        }
    }
}
