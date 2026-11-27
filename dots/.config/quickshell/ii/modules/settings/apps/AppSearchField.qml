import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

TextField {
    id: root
    implicitHeight: 42
    leftPadding: 40
    rightPadding: 12
    color: Appearance.colors.colOnLayer2
    placeholderTextColor: Appearance.colors.colSubtext
    font.family: Appearance.font.family.main
    font.pixelSize: Appearance.font.pixelSize.small
    Accessible.name: placeholderText
    background: Rectangle {
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer3
        border.width: root.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
        MaterialSymbol {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: "search"
            iconSize: 19
            color: Appearance.colors.colSubtext
        }
    }
}
