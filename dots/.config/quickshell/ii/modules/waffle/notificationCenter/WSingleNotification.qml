pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks

MouseArea {
    id: root

    required property var notification
    property bool expanded: (notification?.actions.length ?? 0) > 0
    property string groupExpandControlMessage: ""

    readonly property bool isPopup: notification?.popup ?? false

    signal groupExpandToggle
    hoverEnabled: true
    enabled: !removeAnimation.running

    function dismiss() {
        const id = root.notification?.notificationId;
        if (id !== undefined) removeAnimation.dismiss([id]);
    }

    WNotificationDismissAnim {
        id: removeAnimation
        target: contentItem
    }

    implicitHeight: contentItem.implicitHeight
    implicitWidth: contentItem.implicitWidth

    Behavior on implicitHeight {
        animation: Looks.transition.enter.createObject(this)
    }

    property real dragDismissThreshold: 100
    drag {
        axis: Drag.XAxis
        target: contentItem
        minimumX: 0
        maximumX: root.width
        onActiveChanged: {
            if (drag.active)
                return;
            if (contentItem.x > root.dragDismissThreshold) {
                root.dismiss();
            } else {
                contentItem.x = 0;
            }
        }
    }

    Rectangle {
        id: contentItem
        width: parent.width
        color: root.isPopup ? Looks.colors.bg0 : Looks.colors.bgPanelBody
        radius: root.isPopup ? Looks.radius.large : Looks.radius.medium
        property real padding: 12
        implicitHeight: notificationContent.implicitHeight + padding * 2
        implicitWidth: notificationContent.implicitWidth + padding * 2
        border.width: 1
        border.color: root.isPopup ? Looks.colors.bg2Border : Looks.colors.bgPanelSeparator

        Behavior on x {
            enabled: !root.drag.active && !removeAnimation.running
            animation: Looks.transition.enter.createObject(this)
        }

        ColumnLayout {
            id: notificationContent
            anchors.fill: parent
            anchors.margins: contentItem.padding
            spacing: 19

            // Header
            SingleNotificationHeader {
                Layout.fillWidth: true
            }

            // Content
            Item {
                id: actualContent
                Layout.fillWidth: true
                Layout.fillHeight: true
                property real spacing: 16
                implicitHeight: Math.max(contentColumn.implicitHeight, imageLoader.height)
                implicitWidth: contentColumn.implicitWidth

                Loader {
                    id: imageLoader
                    anchors {
                        top: parent.top
                        left: parent.left
                    }
                    active: !!root.notification?.image
                    sourceComponent: StyledImage {
                        readonly property int size: 48
                        width: size
                        height: size
                        source: root.notification?.image ?? ""
                        fillMode: Image.PreserveAspectFit
                    }
                }

                ColumnLayout {
                    id: contentColumn
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    spacing: 3

                    SummaryText {
                        id: summaryText
                        Layout.leftMargin: imageLoader.active ? imageLoader.width + actualContent.spacing : 0
                    }
                    BodyText {
                        Layout.leftMargin: imageLoader.active ? imageLoader.width + actualContent.spacing : 0
                        // onLineLaidOut: (line) => {
                        //     if (!imageLoader.active) return;
                        //     const dodgeDistance = imageLoader.width + actualContent.spacing;
                        //     // print(line.y, dodgeDistance)
                        //     if (summaryText.height + line.y > dodgeDistance) {
                        //         line.x -= dodgeDistance;
                        //         line.width += dodgeDistance;
                        //     }
                        // }
                    }
                }
            }

            // Actions
            ActionsRow {
                Layout.fillWidth: true
            }

            // "+1 notifications" button
            GroupExpandButton {
                Layout.bottomMargin: 2
            }
        }
    }

    component SingleNotificationHeader: RowLayout {
        ExpandButton {
            Layout.topMargin: -2
        }

        Item {
            Layout.fillWidth: true
        }

        NotificationHeaderButton {
            Layout.rightMargin: 4
            opacity: (root.containsMouse || root.isPopup) ? 1 : 0
            icon.name: "dismiss"
            implicitSize: 14
            onClicked: root.dismiss()
        }
    }

    component ActionsRow: GridLayout {
        id: actions
        readonly property var entries: root.notification?.actions ?? []
        readonly property real buttonPadding: 12
        readonly property real buttonWidth: entries.reduce((widest, action) =>
            Math.max(widest, Math.ceil(metrics.advanceWidth(action.text)) + 2 * buttonPadding), 1)
        visible: root.expanded && entries.length > 0
        columns: Math.max(1, Math.min(entries.length, Math.floor((width + columnSpacing) / (buttonWidth + columnSpacing))))
        uniformCellWidths: true

        FontMetrics {
            id: metrics
            font.family: Looks.font.family.ui
            font.pixelSize: Looks.font.pixelSize.large
        }
        Repeater {
            model: actions.entries
            delegate: WBorderedButton {
                id: actionButton
                Layout.fillHeight: true
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                verticalPadding: 8
                horizontalPadding: actions.buttonPadding
                text: modelData.text
                implicitHeight: Math.max(36, actionButtonText.implicitHeight + verticalPadding * 2)
                onClicked: Notifications.attemptInvokeAction(root.notification.notificationId, modelData.identifier)
                contentItem: WText {
                    id: actionButtonText
                    text: actionButton.text
                    textFormat: Text.PlainText
                    font.pixelSize: Looks.font.pixelSize.large
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    component SummaryText: WText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.notification?.summary ?? ""
        textFormat: Text.PlainText
        font.pixelSize: Looks.font.pixelSize.large
    }

    component BodyText: WText {
        Layout.fillWidth: true
        Layout.fillHeight: true
        elide: Text.ElideRight
        verticalAlignment: Text.AlignTop
        wrapMode: Text.Wrap
        maximumLineCount: root.expanded ? 100 : 1
        text: NotificationUtils.processNotificationBody(root.notification?.body, root.notification?.appName || root.notification?.summary)
        color: Looks.colors.subfg
        textFormat: Text.StyledText
        onLinkActivated: link => {
            if (!StringUtils.parseWebUrl(link)) return;
            Qt.openUrlExternally(link);
            GlobalStates.sidebarRightOpen = false;
        }
    }

    component ExpandButton: NotificationHeaderButton {
        id: expandButton
        implicitWidth: expandButtonContent.implicitWidth
        onClicked: root.expanded = !root.expanded

        contentItem: Item {
            id: expandButtonContent
            implicitWidth: expandButtonRow.implicitWidth
            implicitHeight: expandButtonRow.implicitHeight
            RowLayout {
                id: expandButtonRow
                anchors.centerIn: parent
                spacing: 8
                WText {
                    color: expandButton.colForeground
                    text: NotificationUtils.getFriendlyNotifTimeString(root.notification?.time)
                }
                FluentIcon {
                    Layout.rightMargin: 12
                    icon: "chevron-down"
                    implicitSize: 18
                    rotation: root.expanded ? -180 : 0
                    color: expandButton.colForeground
                    Behavior on rotation {
                        animation: Looks.transition.rotate.createObject(this)
                    }
                }
            }
        }
    }

    component GroupExpandButton: AcrylicButton {
        id: groupExpandButton
        visible: root.groupExpandControlMessage !== ""
        horizontalPadding: 10
        implicitHeight: 24
        implicitWidth: expandButtonText.implicitWidth + horizontalPadding * 2
        onClicked: root.groupExpandToggle()
        contentItem: Item {
            WText {
                id: expandButtonText
                anchors.centerIn: parent
                text: root.groupExpandControlMessage
            }
        }
    }
}
