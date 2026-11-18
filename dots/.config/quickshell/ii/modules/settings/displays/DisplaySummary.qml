import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

RowLayout {
    id: root
    required property string name
    required property string connector
    required property string modeText
    required property real aspect
    required property real displayScale
    Layout.fillWidth: true
    Layout.margins: 12
    spacing: 16

    Rectangle {
        id: stage
        Layout.preferredWidth: 168
        Layout.minimumWidth: 88
        implicitHeight: 108
        radius: Appearance.rounding.small
        color: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colLayer1, 0.10)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: panel.y + panel.height - 1
            width: 6; height: 8; color: Appearance.colors.colSubtext
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 6; width: 23; height: 3; radius: 2; color: parent.color }
        }
        Rectangle {
            id: panel
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height) / 2 - 4
            width: Math.min(stage.width - 20, 72 * root.aspect)
            height: width / root.aspect
            radius: 5
            color: Appearance.colors.colSurfaceContainer
            border.width: 2; border.color: Appearance.colors.colSubtext
            clip: true
            Rectangle {
                x: 3; y: 3; width: parent.width - 6; height: parent.height - 6; radius: 2
                color: Appearance.colors.colSecondaryContainer
                Rectangle {
                    x: parent.width * 0.13; y: parent.height * 0.16
                    width: Math.min(parent.width * 0.76, parent.width * 0.47 * root.displayScale)
                    height: parent.height * 0.57; radius: 3
                    color: Appearance.colors.colLayer2Base
                    Rectangle { x: 4; y: 5; width: parent.width * 0.49; height: 3; radius: 2; color: Appearance.colors.colPrimary }
                    Rectangle { x: 4; y: 11; width: parent.width * 0.67; height: 2; radius: 1; color: Appearance.colors.colOutlineVariant }
                    Behavior on width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                }
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 3; width: parent.width * 0.3; height: 4; radius: 2; color: Appearance.colors.colPrimary }
            }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 5
        StyledText { Layout.fillWidth: true; text: root.name; wrapMode: Text.Wrap; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer2 }
        StyledText { Layout.fillWidth: true; text: root.modeText; wrapMode: Text.Wrap; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer2 }
        StyledText { Layout.fillWidth: true; text: root.connector; elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
    }
}
