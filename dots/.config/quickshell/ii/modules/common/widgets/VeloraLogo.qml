import QtQuick
import QtQuick.Shapes
import qs.modules.common

/**
 * The V of Velora, as on the banner and the Settings icon, in one color.
 */
Item {
    id: root
    property real size: 32
    property color color: Appearance.colors.colPrimary
    property real progress: 1

    implicitWidth: root.size
    implicitHeight: root.size

    Shape {
        // Drawn in a 100×100 box, scaled to the size
        width: 100
        height: 100
        transform: Scale {
            xScale: root.width / 100
            yScale: root.height / 100
        }
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: stroke
            // The two legs and the rounded corner occupy these fractions of the stroke length.
            readonly property real leftLeg: Math.min(1, root.progress / 0.45)
            readonly property real bend: Math.max(0, Math.min(1, (root.progress - 0.45) / 0.05))
            readonly property real rightLeg: Math.max(0, (root.progress - 0.5) * 2)
            strokeColor: root.color
            strokeWidth: 14
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 7
            startY: 21
            PathLine { id: left; x: 7 + 38 * stroke.leftLeg; y: 21 + 64.3 * stroke.leftLeg }
            PathQuad {
                id: corner
                controlX: left.x + 3.3 * stroke.bend; controlY: left.y + 5.6 * stroke.bend
                x: left.x + 6.6 * stroke.bend + 0.1 * stroke.bend * stroke.bend
                y: left.y + 11.2 * stroke.bend * (1 - stroke.bend)
            }
            PathLine { x: corner.x + 41.6 * stroke.rightLeg; y: corner.y - 72.2 * stroke.rightLeg }
        }
    }
}
