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
            strokeColor: root.color
            strokeWidth: 14
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 7
            startY: 21
            PathLine { x: 45; y: 85.3 }
            PathQuad { controlX: 48.3; controlY: 90.9; x: 51.7; y: 85.3 }
            PathLine { x: 93.3; y: 13.1 }
        }
    }
}
