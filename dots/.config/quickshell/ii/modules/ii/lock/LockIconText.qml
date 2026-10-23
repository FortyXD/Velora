import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// An icon and a text side by side, for the lock screen toolbars
Row {
    id: pair
    required property string icon
    required property string text
    property color color: Appearance.colors.colOnSurfaceVariant

    spacing: 4
    Layout.fillHeight: true
    Layout.leftMargin: 10
    Layout.rightMargin: 10

    MaterialSymbol {
        anchors.verticalCenter: parent.verticalCenter
        fill: 1
        text: pair.icon
        iconSize: Appearance.font.pixelSize.huge
        animateChange: true
        color: pair.color
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: pair.text
        color: pair.color
    }
}
