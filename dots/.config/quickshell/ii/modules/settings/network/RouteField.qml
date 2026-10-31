import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

/** A small text field for the rows of a list in the connection editor. */
TextField {
    id: root
    placeholderTextColor: Appearance.colors.colSubtext
    color: Appearance.colors.colOnLayer2
    leftPadding: 10
    rightPadding: 10
    topPadding: 8
    bottomPadding: 8
    font.pixelSize: Appearance.font.pixelSize.smaller
    background: Rectangle {
        implicitHeight: 34
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer3
        border.width: root.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
    }
}
