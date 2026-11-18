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

// Showing the desktop changes real windows on release. Preview its threshold under the fingers.
Scope {
    id: root
    readonly property string action: TouchpadGestures.hintAction
    readonly property real amount: Math.max(0, Math.min(1, TouchpadGestures.hintProgress / TouchpadGestures.hintAt))
    readonly property bool ready: TouchpadGestures.hintProgress >= TouchpadGestures.hintAt
    property var screen: null
    onActionChanged: if (root.action.length > 0) root.screen = Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    // Kept built: a gesture can't wait for it
    PanelWindow {
        id: window
        visible: root.action.length > 0 || pill.opacity > 0
        screen: root.screen ?? Quickshell.screens[0]
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:gestureHint"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors.bottom: true
        implicitWidth: 320
        implicitHeight: 140
        mask: Region {}

        StyledRectangularShadow {
            target: pill
            opacity: pill.opacity
            scale: pill.scale
        }
        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 56
            width: row.implicitWidth + 32
            height: 60
            radius: height / 2
            color: root.ready ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            // Comes up with the fingers, pops when it happens
            opacity: root.action.length > 0 ? Math.min(1, TouchpadGestures.hintProgress * 6) : 0
            scale: TouchpadGestures.hintDone ? 1.08 : 0.86 + 0.14 * root.amount
            Behavior on opacity {
                enabled: TouchpadGestures.activeAction !== "desktop"
                NumberAnimation { duration: Appearance.scaledDuration(180) }
            }
            Behavior on scale {
                enabled: TouchpadGestures.activeAction !== "desktop"
                NumberAnimation { duration: Appearance.scaledDuration(160); easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: Appearance.scaledDuration(160) } }

            RowLayout {
                id: row
                anchors.centerIn: parent
                spacing: 12
                Item {
                    implicitWidth: 36
                    implicitHeight: 36
                    CircularProgress {
                        anchors.centerIn: parent
                        implicitSize: 36
                        lineWidth: 3
                        value: root.amount
                        enableAnimation: false
                        colPrimary: Appearance.colors.colPrimary
                        colSecondary: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "desktop_windows"
                        iconSize: 18
                        color: root.ready ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
                    }
                }
                ColumnLayout {
                    spacing: 0
                    StyledText {
                        text: Translation.tr("Show the desktop")
                        font.weight: Font.DemiBold
                        color: root.ready ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        text: TouchpadGestures.hintDone ? "" : root.ready ? Translation.tr("Let go") : Translation.tr("Keep going")
                        visible: text.length > 0
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.ready ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
