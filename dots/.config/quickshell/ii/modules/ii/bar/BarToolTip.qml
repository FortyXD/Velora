import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Tooltip of a bar widget: a card beside the bar, sized like the bar's other popups (e.g. StyledPopupValueRow).
 * Put it inside the widget; it shows while `shown` is true and there's text.
 */
Item {
    id: root
    property string text: ""
    property bool shown: false
    readonly property bool containsMouse: root.shown && root.text.length > 0 // What StyledPopup follows

    anchors.fill: parent

    StyledPopup {
        hoverTarget: root

        StyledText {
            anchors.centerIn: parent
            text: root.text
            font.pixelSize: Appearance.popup.textSize
            color: Appearance.popup.colText
        }
    }
}
