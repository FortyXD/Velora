import QtQuick
import QtQuick.Window
import qs.modules.common
import qs.services

Item {
    id: root
    property bool active: false
    property color accent: Appearance.colors.colPrimary
    readonly property bool animating: active && visible && (Window.window?.visible ?? false) && Appearance.animationSpeed > 0
    visible: active
    implicitWidth: 26
    implicitHeight: 26
    Accessible.role: Accessible.StaticText
    Accessible.name: Translation.tr("AI is thinking")
    MaterialSymbol {
        anchors.centerIn: parent
        text: "auto_awesome"
        iconSize: 22
        color: root.accent
        SequentialAnimation on scale {
            running: root.animating
            loops: Animation.Infinite
            NumberAnimation { from: 0.78; to: 1.08; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.08; to: 0.78; duration: 600; easing.type: Easing.InOutSine }
        }
    }
}
