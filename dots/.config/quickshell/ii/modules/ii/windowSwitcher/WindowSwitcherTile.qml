import QtQuick
import qs.modules.common
import qs.modules.common.functions

MouseArea {
    id: root
    required property bool selected

    // Each card owns its frame: it is ready with the card, even when the initial selection
    // was set before the Repeater created any delegates or the layout assigned their sizes.
    Rectangle {
        objectName: "selectionHighlight"
        anchors.fill: parent
        anchors.margins: -4
        z: -1
        visible: root.selected
        radius: Appearance.rounding.normal
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
        border.width: 2
        border.color: Appearance.colors.colPrimary
    }
}
