import QtQuick
import QtQuick.Shapes

/** An upright status glyph with an independent, visibility-aware activity ring. */
Item {
    id: root

    property string text: ""
    property real iconSize: 24
    property real fill: 0
    property color color: "white"
    property bool busy: false

    implicitWidth: iconSize
    implicitHeight: iconSize

    MaterialSymbol {
        objectName: "statusGlyph"
        anchors.centerIn: parent
        text: root.text
        iconSize: root.iconSize
        fill: root.fill
        color: root.color
        opacity: root.busy ? 0.65 : 1
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Never animate the glyph: changing sync -> Wi-Fi or progress -> lock must
    // not leave the new symbol at the previous animation's arbitrary angle.
    Shape {
        id: busyRing
        objectName: "statusBusyRing"
        anchors.centerIn: parent
        width: root.iconSize + 10
        height: width
        visible: root.busy
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: 2
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: busyRing.width / 2
                centerY: busyRing.height / 2
                radiusX: (busyRing.width - 2) / 2
                radiusY: radiusX
                startAngle: -90
                sweepAngle: 270
            }
        }

        RotationAnimation on rotation {
            running: root.busy && root.visible
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 1200
            easing.type: Easing.Linear
            onStopped: busyRing.rotation = 0
        }
    }
}
