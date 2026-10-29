import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * One of the big actions of the session screen: a round icon with its name below. While it's the
 * highlighted one (by pointer or arrow keys) the circle turns into the action's own shape, in the primary
 * color, and slowly turns.
 */
Item {
    id: button

    property string buttonIcon
    property string buttonText
    property var selectedShape: MaterialShape.Shape.Cookie9Sided
    property bool selected: false
    readonly property bool hovered: mouseArea.containsMouse
    readonly property real size: 104

    signal clicked()

    implicitWidth: Math.max(button.size, label.implicitWidth)
    implicitHeight: button.size + 16 + label.implicitHeight

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

    Item {
        id: shapeHolder
        anchors.horizontalCenter: parent.horizontalCenter
        width: button.size
        height: button.size
        scale: mouseArea.pressed ? 0.92 : button.selected ? 1.08 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.scaledDuration(Appearance.animationCurves.expressiveFastSpatialDuration)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        MaterialShape {
            id: shape
            anchors.fill: parent
            implicitSize: button.size
            shape: button.selected ? button.selectedShape : MaterialShape.Shape.Circle
            color: button.selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            // Turns only while it has a shape to show turning; as a circle it can stop anywhere
            NumberAnimation on rotation {
                running: button.selected && Appearance.animationSpeed > 0
                from: 0
                to: 360
                duration: 16000
                loops: Animation.Infinite
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: button.buttonIcon
            iconSize: 40
            fill: button.selected ? 1 : 0
            color: button.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    StyledText {
        id: label
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: shapeHolder.bottom
            topMargin: 16
        }
        text: button.buttonText
        font.pixelSize: Appearance.font.pixelSize.normal
        font.weight: button.selected ? Font.DemiBold : Font.Normal
        color: button.selected ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
