pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

/**
 * Context menu that opens above a dock tile.
 * Entries: { text, checked?, enabled?, action } | { type: "separator" }
 */
PopupWindow {
    id: root

    property var entries: []
    readonly property real margin: Appearance.sizes.elevationMargin

    function openAt(window, centerX, bottomY, entries) {
        root.entries = entries;
        root.anchor.window = window;
        root.anchor.rect.x = centerX;
        root.anchor.rect.y = bottomY;
        root.visible = true;
        focusGrab.active = true;
    }

    function close() {
        focusGrab.active = false;
        root.visible = false;
    }

    visible: false
    color: "transparent"
    implicitWidth: menuBackground.implicitWidth + margin * 2
    implicitHeight: menuBackground.implicitHeight + margin * 2

    anchor {
        rect.width: 1
        rect.height: 1
        edges: Edges.Top
        gravity: Edges.Top
        adjustment: PopupAdjustment.SlideX
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.close()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()

        StyledRectangularShadow {
            target: menuBackground
            opacity: menuBackground.opacity
        }

        Rectangle {
            id: menuBackground
            readonly property real padding: 5
            anchors.centerIn: parent
            implicitWidth: Math.max(190, menuColumn.implicitWidth + padding * 2)
            implicitHeight: menuColumn.implicitHeight + padding * 2
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            opacity: root.visible ? 1 : 0
            scale: root.visible ? 1 : 0.92
            transformOrigin: Item.Bottom
            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                id: menuColumn
                anchors {
                    fill: parent
                    margins: menuBackground.padding
                }
                spacing: 0

                Repeater {
                    model: root.entries

                    delegate: Item {
                        id: entryItem
                        required property var modelData
                        readonly property bool isSeparator: modelData.type === "separator"
                        readonly property bool isEnabled: !isSeparator && (modelData.enabled ?? true)

                        Layout.fillWidth: true
                        implicitHeight: isSeparator ? 9 : 30
                        implicitWidth: isSeparator ? 0 : entryText.implicitWidth + 36 + 12

                        Rectangle {
                            visible: entryItem.isSeparator
                            anchors.centerIn: parent
                            width: parent.width - 16
                            height: 1
                            color: Appearance.colors.colOutlineVariant
                        }

                        Rectangle {
                            visible: !entryItem.isSeparator
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: entryMouseArea.containsMouse && entryItem.isEnabled ? Appearance.colors.colPrimary : "transparent"
                        }

                        MaterialSymbol {
                            visible: !entryItem.isSeparator && (entryItem.modelData.checked ?? false)
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: "check"
                            iconSize: Appearance.font.pixelSize.normal
                            color: entryMouseArea.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                        }

                        StyledText {
                            id: entryText
                            visible: !entryItem.isSeparator
                            anchors {
                                left: parent.left
                                leftMargin: 36
                                right: parent.right
                                rightMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            text: entryItem.modelData.text ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: !entryItem.isEnabled ? Appearance.colors.colSubtext
                                : entryMouseArea.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                        }

                        MouseArea {
                            id: entryMouseArea
                            anchors.fill: parent
                            enabled: entryItem.isEnabled
                            hoverEnabled: true
                            onClicked: {
                                const action = entryItem.modelData.action;
                                root.close();
                                if (action) action();
                            }
                        }
                    }
                }
            }
        }
    }
}
