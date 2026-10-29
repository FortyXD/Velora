import QtQuick
import QtQuick.Layouts

/**
 * Shows its content a moment after its page arrives, rising slightly into place. Items of a page get
 * increasing `order`, so they come in one after another.
 */
Item {
    id: root
    property int order: 0
    default property alias content: holder.data
    implicitWidth: holder.childrenRect.width
    implicitHeight: holder.childrenRect.height
    Layout.fillWidth: true

    Item {
        id: holder
        width: parent.width
        height: parent.height
        opacity: 0
        y: Motion.travel(14)
    }

    SequentialAnimation {
        running: true
        PauseAnimation {
            duration: Motion.ms(140 + root.order * Motion.stagger)
        }
        ParallelAnimation {
            NumberAnimation {
                target: holder
                property: "opacity"
                to: 1
                duration: Motion.ms(320)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.effects
            }
            NumberAnimation {
                target: holder
                property: "y"
                to: 0
                duration: Motion.ms(460)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.decelerate
            }
        }
    }
}
