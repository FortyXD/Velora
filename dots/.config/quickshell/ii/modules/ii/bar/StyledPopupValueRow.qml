import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: root
    required property string icon
    required property string label
    required property string value
    spacing: 4

    MaterialSymbol {
        text: root.icon
        color: Appearance.popup.colText
        iconSize: Appearance.popup.iconSize
    }
    StyledText {
        text: root.label
        font.pixelSize: Appearance.popup.textSize
        color: Appearance.popup.colText
    }
    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        visible: root.value !== ""
        font.pixelSize: Appearance.popup.textSize
        color: Appearance.popup.colText
        text: root.value
    }
}
