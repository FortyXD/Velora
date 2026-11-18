import QtQuick
import QtQuick.Controls
import qs.modules.common

Item {
    id: root
    required property Slider control
    required property real value
    property real leftInset: control.leftPadding
    property real rightInset: control.rightPadding
    property color ink: Appearance.colors.colOnLayer2
    property color outline: Appearance.colors.colLayer2
    readonly property bool valid: Number.isFinite(value) && control.to !== control.from
        && value >= Math.min(control.from, control.to) && value <= Math.max(control.from, control.to)
    readonly property real position: valid ? (value - control.from) / (control.to - control.from) : 0
    readonly property bool hovered: hover.hovered
    objectName: "sliderDefaultMark"
    visible: valid
    width: 12
    x: leftInset + (control.mirrored ? 1 - position : position) * (control.width - leftInset - rightInset) - width / 2
    anchors.verticalCenter: parent.verticalCenter

    Rectangle {
        anchors.centerIn: parent
        width: 2; height: parent.height; radius: 1
        color: root.ink
        border.width: 0.5
        border.color: root.outline
    }
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        width: 7; height: 2; radius: 1
        color: root.ink
    }
    HoverHandler { id: hover; enabled: root.valid }
}
