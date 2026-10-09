import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Icon at the start of a settings row. Tinted with the accent color when `active`.
 */
Item {
    id: root
    property string icon: ""
    property bool active: false
    property real iconSize: 20
    property real size: 26

    Layout.alignment: Qt.AlignVCenter
    visible: root.icon.length > 0
    implicitWidth: root.size
    implicitHeight: root.size

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: root.iconSize
        fill: root.active ? 1 : 0
        color: root.active ? Appearance.colors.colPrimary : Appearance.colors.colSubtext

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
