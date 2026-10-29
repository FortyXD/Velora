import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Icon at the start of a settings row. Tinted with the accent color when `active`.
 * With a `tileColor`, a white icon on a tile of that color instead, like the pages in the sidebar.
 */
Item {
    id: root
    property string icon: ""
    property bool active: false
    property real iconSize: root.tiled ? 17 : 20
    property real size: 26
    property color tileColor: "transparent"
    readonly property bool tiled: root.tileColor.a > 0

    Layout.alignment: Qt.AlignVCenter
    visible: root.icon.length > 0
    implicitWidth: root.size
    implicitHeight: root.size

    Rectangle {
        visible: root.tiled
        anchors.fill: parent
        radius: 8
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(root.tileColor, 1.12) }
            GradientStop { position: 1; color: root.tileColor }
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: root.iconSize
        fill: root.active || root.tiled ? 1 : 0
        color: root.tiled ? "white" : root.active ? Appearance.colors.colPrimary : Appearance.colors.colSubtext

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
