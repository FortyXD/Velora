pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The card of the "Open with" chooser: suggested apps, every other app behind "More apps",
 * and "Always use this app", ticked by default.
 */
Item {
    id: root
    required property var request
    property bool expanded: false
    property string filter: ""
    property var selectedApp: null
    property bool remember: true

    signal chosen(var app, bool remember)
    signal canceled()

    readonly property var recommended: root.request?.recommended ?? []
    readonly property var others: root.request?.others ?? []
    readonly property var items: {
        const query = root.filter.trim().toLowerCase();
        const matches = app => query.length === 0 || `${app.name} ${app.comment ?? ""} ${app.id}`.toLowerCase().includes(query);
        let suggested = root.recommended.filter(matches).map(app => ({ app: app, header: "" }));
        if (!root.expanded) return suggested;
        let more = root.others.filter(matches).map(app => ({ app: app, header: "" }));
        if (suggested.length > 0) {
            suggested[0].header = Translation.tr("Suggested");
            if (more.length > 0) more[0].header = Translation.tr("More apps");
        }
        return suggested.concat(more);
    }
    readonly property string rememberText: root.request?.extension
        ? Translation.tr("Always use this app to open %1 files").arg(root.request.extension)
        : Translation.tr("Always use this app for “%1”").arg(root.request?.description ?? "")

    function reset() {
        root.expanded = root.recommended.length === 0;
        root.filter = "";
        searchField.text = "";
        root.selectedApp = root.recommended[0] ?? null;
        root.remember = true;
        card.forceActiveFocus();
    }
    onRequestChanged: root.reset()
    Component.onCompleted: root.reset()

    function open() {
        if (root.selectedApp) root.chosen(root.selectedApp, root.remember);
    }

    // A second click on the same app opens it right away
    property real lastClickTime: 0
    function clickApp(app) {
        const now = Date.now();
        const twice = root.selectedApp?.id === app.id && now - root.lastClickTime < 450;
        root.selectedApp = app;
        root.lastClickTime = now;
        if (twice) root.open();
    }

    function moveSelection(step) {
        if (root.items.length === 0) return;
        const index = root.items.findIndex(item => item.app.id === root.selectedApp?.id);
        const next = Math.max(0, Math.min(root.items.length - 1, index + step));
        root.selectedApp = root.items[next].app;
        appList.positionViewAtIndex(next, ListView.Contain);
    }

    function iconSource(icon) {
        if (!icon) return Quickshell.iconPath("application-x-executable");
        return icon.startsWith("/") ? `file://${icon}` : Quickshell.iconPath(icon, "application-x-executable");
    }

    Rectangle { // Scrim; clicking it cancels
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: root.canceled()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 460
        height: Math.min(cardColumn.implicitHeight + 24 * 2, root.height - 80)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        focus: true
        scale: 0.94
        opacity: 0
        Component.onCompleted: {
            scale = 1;
            opacity = 1;
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.canceled();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.open();
            } else if (event.key === Qt.Key_Down) {
                root.moveSelection(1);
            } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1);
            } else {
                return;
            }
            event.accepted = true;
        }

        MouseArea { // Clicks inside don't reach the scrim
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        StyledRectangularShadow {
            target: card
            z: -1
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                fill: parent
                margins: 24
            }
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("How do you want to open this file?")
                    wrapMode: Text.Wrap
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer3
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.request?.name ?? ""
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer3
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.request?.description ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            Rectangle { // Search, once every app is shown
                visible: root.expanded
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                border.width: searchField.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8
                    MaterialSymbol {
                        text: "search"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        background: null
                        padding: 0
                        placeholderText: Translation.tr("Find an app")
                        placeholderTextColor: Appearance.colors.colSubtext
                        color: Appearance.colors.colOnLayer3
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        onTextChanged: {
                            root.filter = text;
                            if (root.items.length > 0 && !root.items.some(item => item.app.id === root.selectedApp?.id))
                                root.selectedApp = root.items[0].app;
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Down) root.moveSelection(1);
                            else if (event.key === Qt.Key_Up) root.moveSelection(-1);
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.open();
                            else if (event.key === Qt.Key_Escape) root.canceled();
                            else return;
                            event.accepted = true;
                        }
                    }
                }
            }

            StyledListView {
                id: appList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Math.min(contentHeight, 120)
                implicitHeight: Math.min(contentHeight, root.expanded ? 360 : 300)
                clip: true
                spacing: 2
                model: root.items

                delegate: ColumnLayout {
                    id: appItem
                    required property var modelData
                    readonly property bool selected: root.selectedApp?.id === appItem.modelData.app.id
                    width: appList.width
                    spacing: 2

                    StyledText {
                        visible: appItem.modelData.header.length > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.topMargin: 8
                        Layout.bottomMargin: 2
                        text: appItem.modelData.header
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        buttonRadius: Appearance.rounding.normal
                        colBackground: appItem.selected ? Appearance.colors.colSecondaryContainer : "transparent"
                        colBackgroundHover: appItem.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover
                        colRipple: appItem.selected ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer3Active
                        onClicked: root.clickApp(appItem.modelData.app)

                        contentItem: RowLayout {
                            spacing: 12
                            IconImage {
                                Layout.leftMargin: 8
                                implicitSize: 32
                                source: root.iconSource(appItem.modelData.app.icon)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: appItem.modelData.app.name
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: appItem.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: appItem.modelData.app.comment ?? ""
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            MaterialSymbol {
                                Layout.rightMargin: 10
                                visible: appItem.selected
                                text: "check"
                                iconSize: 20
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: root.items.length === 0
                Layout.fillWidth: true
                text: Translation.tr("Nothing found")
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            RippleButton { // More apps
                visible: !root.expanded
                Layout.fillWidth: true
                implicitHeight: 40
                buttonRadius: Appearance.rounding.normal
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                onClicked: {
                    root.expanded = true;
                    searchField.forceActiveFocus();
                }
                contentItem: RowLayout {
                    spacing: 12
                    MaterialSymbol {
                        Layout.leftMargin: 14
                        text: "apps"
                        iconSize: 22
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("More apps")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colPrimary
                    }
                    MaterialSymbol {
                        Layout.rightMargin: 10
                        text: "expand_more"
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            RippleButton { // Always use this app
                Layout.fillWidth: true
                implicitHeight: 40
                buttonRadius: Appearance.rounding.normal
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                onClicked: root.remember = !root.remember
                contentItem: RowLayout {
                    spacing: 12
                    MaterialSymbol {
                        Layout.leftMargin: 12
                        text: root.remember ? "check_box" : "check_box_outline_blank"
                        fill: root.remember ? 1 : 0
                        iconSize: 22
                        color: root.remember ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.rememberText
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer3
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    visible: root.remember
                    text: Translation.tr("Change it later in Settings › Default Apps")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Item {
                    visible: !root.remember
                    Layout.fillWidth: true
                }
                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.canceled()
                }
                DialogButton {
                    enabled: root.selectedApp !== null
                    buttonText: Translation.tr("Open")
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    colEnabled: Appearance.colors.colOnPrimary
                    onClicked: root.open()
                }
            }
        }
    }
}
