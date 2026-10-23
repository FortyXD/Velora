import QtQuick
import QtQuick.Controls
import qs.modules.common

Flickable {
    id: root
    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120
    readonly property alias wheelArea: wheelArea

    ScrollBar.vertical: StyledScrollBar {}

    ScrollWheelArea {
        id: wheelArea
        flickable: root
    }

    Behavior on contentY {
        enabled: wheelArea.gliding // Only mouse wheel notches glide; touchpad and drags follow directly
        NumberAnimation {
            id: scrollAnim
            duration: Appearance.animation.scroll.duration
            easing.type: Appearance.animation.scroll.type
            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
            onRunningChanged: if (!running) wheelArea.gliding = false
        }
    }

}
