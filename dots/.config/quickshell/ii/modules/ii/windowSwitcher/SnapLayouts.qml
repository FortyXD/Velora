pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Snap layouts (Super+Z, free windows): small pictures of ways to split the screen; clicking a part
 * puts the active window there (hyprland/modes/floating.lua). Esc or a click elsewhere closes it.
 */
Scope {
    id: root
    property bool open: false
    property var screen: null
    // Where it opened, kept while it's open
    onOpenChanged: root.screen = open ? Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] : null

    GlobalShortcut {
        name: "snapLayoutsToggle"
        description: "Snap layouts for the active window"
        onPressed: root.open = !root.open && FreeWindows.enabled
    }

    LazyLoader {
        active: root.open && root.screen !== null

        component: PanelWindow {
            id: window
            screen: root.screen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:snapLayouts"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // A click beside the card closes it
            MouseArea {
                anchors.fill: parent
                onClicked: root.open = false
            }

            StyledRectangularShadow {
                target: card
            }
            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.12
                width: layoutsRow.implicitWidth + 28
                height: column.implicitHeight + 28
                radius: Appearance.rounding.windowRounding
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                focus: true
                Keys.onEscapePressed: root.open = false

                opacity: 0
                scale: 0.95
                transformOrigin: Item.Top
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                MouseArea { // Keeps clicks on the card from closing it
                    anchors.fill: parent
                }

                ColumnLayout {
                    id: column
                    anchors.centerIn: parent
                    spacing: 10

                    StyledText {
                        text: Translation.tr("Snap the window")
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                    RowLayout {
                        id: layoutsRow
                        spacing: 10

                        Repeater {
                            model: FreeWindows.layouts

                            delegate: Rectangle {
                                id: layout
                                required property var modelData
                                implicitWidth: 120
                                implicitHeight: 76
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer1

                                Repeater {
                                    model: layout.modelData

                                    delegate: Rectangle {
                                        id: zone
                                        required property var modelData
                                        readonly property real inset: 3
                                        x: inset + (layout.width - inset * 2) * modelData[1] + 2
                                        y: inset + (layout.height - inset * 2) * modelData[2] + 2
                                        width: (layout.width - inset * 2) * modelData[3] - 4
                                        height: (layout.height - inset * 2) * modelData[4] - 4
                                        radius: 4
                                        color: zoneArea.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                        Behavior on color {
                                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                        }
                                        MouseArea {
                                            id: zoneArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.open = false;
                                                FreeWindows.snap(zone.modelData[0]);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
