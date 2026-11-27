import QtQuick
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    Keys.onReturnPressed: root.click()
    Keys.onEnterPressed: root.click()
    downAction: () => root.forceActiveFocus(Qt.MouseFocusReason)

    Rectangle {
        anchors.fill: parent
        z: 2
        color: "transparent"
        radius: root.buttonRadius
        border.width: 2
        border.color: Appearance.colors.colPrimary
        visible: root.visualFocus
    }
}
