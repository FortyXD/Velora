import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.preview

MiniScreen {
    id: root
    required property real progress
    required property bool selector
    readonly property var targets: Config.options.regionSelector.targetRegions
    readonly property bool circle: selector && Config.options.search.imageSearch.useCircleSelection
    readonly property real extent: 0.09 + 0.91 * progress
    readonly property color accent: selector ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
    readonly property color shade: Qt.rgba(0, 0, 0, 0.47)
    radius: Appearance.rounding.small
    scrim: 0.08
    wallpaperItem.source: selector ? "" : wallpaper
    wallpaperItem.sourceSize: Qt.size(880, 0)

    Rectangle {
        anchors.fill: parent
        visible: root.selector
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Appearance.colors.colLayer3Base }
            GradientStop { position: 1; color: ColorUtils.mix(root.accent, Appearance.colors.colLayer2Base, 0.18) }
        }
    }
    Rectangle {
        id: sampleWindow
        visible: root.selector
        x: root.width * 0.21; y: root.height * 0.19
        width: root.width * 0.59; height: root.height * 0.64
        radius: 8
        color: Appearance.colors.colLayer2Base
        border.width: 1
        border.color: root.targets.windows ? ColorUtils.applyAlpha(root.accent, 0.76) : Appearance.colors.colOutlineVariant

        Rectangle {
            x: 10; y: parent.height * 0.16
            width: parent.width * 0.26; height: 3; radius: 2
            color: Appearance.colors.colSubtext
        }
        Rectangle {
            id: sampleContent
            x: 10; y: parent.height * 0.34
            width: parent.width * 0.42; height: parent.height * 0.49
            radius: 4
            color: ColorUtils.mix(root.accent, Appearance.colors.colLayer2Base, 0.24)
            border.width: root.targets.content ? 1 : 0
            border.color: root.accent
            MaterialSymbol { anchors.centerIn: parent; text: "landscape"; iconSize: Math.min(29, parent.height * 0.67); color: root.accent }
        }
        Column {
            x: parent.width * 0.54; y: parent.height * 0.40; spacing: 5
            Repeater {
                model: [0.31, 0.23, 0.26]
                Rectangle {
                    required property real modelData
                    width: sampleWindow.width * modelData; height: 3; radius: 2
                    color: Appearance.colors.colOutlineVariant
                }
            }
        }
    }
    Rectangle {
        visible: root.selector
        x: root.width * 0.07; anchors.verticalCenter: parent.verticalCenter
        width: 10; height: parent.height * 0.70; radius: 5
        color: root.targets.layers ? root.accent : Appearance.colors.colOutlineVariant
    }

    Item {
        id: frame
        x: root.width * (root.selector ? 0.24 : 0.17)
        y: root.height * (root.selector ? 0.28 : 0.18)
        width: root.width * (root.selector ? 0.46 : 0.65) * root.extent
        height: root.height * (root.selector ? 0.48 : 0.63) * root.extent
    }
    Item {
        anchors.fill: parent
        visible: !root.selector
        Rectangle { width: parent.width; height: frame.y; color: root.shade }
        Rectangle { y: frame.y + frame.height; width: parent.width; height: parent.height - y; color: root.shade }
        Rectangle { y: frame.y; width: frame.x; height: frame.height; color: root.shade }
        Rectangle { x: frame.x + frame.width; y: frame.y; width: parent.width - x; height: frame.height; color: root.shade }
    }
    Item {
        anchors.fill: parent
        visible: !root.circle && Config.options.regionSelector.rect.showAimLines
        Rectangle { y: frame.y + frame.height; width: parent.width; height: 1; color: ColorUtils.applyAlpha(root.accent, 0.46) }
        Rectangle { x: frame.x + frame.width; height: parent.height; width: 1; color: ColorUtils.applyAlpha(root.accent, 0.46) }
    }
    Rectangle {
        visible: !root.circle
        x: frame.x; y: frame.y; width: frame.width; height: frame.height
        color: "transparent"; border.width: 1.5; border.color: root.accent
        Repeater {
            model: 4
            Rectangle {
                required property int index
                x: (index % 2 ? parent.width : 0) - width / 2
                y: (index >= 2 ? parent.height : 0) - height / 2
                width: 6; height: 6; radius: 2
                color: root.accent
                border.width: 1; border.color: Appearance.colors.colLayer2Base
            }
        }
    }
    Shape {
        id: ring
        anchors.fill: parent
        visible: root.circle
        preferredRendererType: Shape.CurveRenderer
        readonly property real rx: root.width * 0.22
        readonly property real ry: root.height * 0.29
        readonly property real cx: root.width * 0.48
        readonly property real cy: root.height * 0.51
        ShapePath {
            fillColor: "transparent"; strokeColor: root.accent
            strokeWidth: Math.max(1, Config.options.regionSelector.circle.strokeWidth * 0.5)
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.cx; centerY: ring.cy; radiusX: ring.rx; radiusY: ring.ry
                startAngle: -110; sweepAngle: 360 * root.progress
            }
        }
        Rectangle {
            readonly property real margin: Config.options.regionSelector.circle.padding * 0.18
            x: ring.cx - ring.rx - margin; y: ring.cy - ring.ry - margin
            width: (ring.rx + margin) * 2; height: (ring.ry + margin) * 2
            color: "transparent"; border.width: 1; radius: 3
            border.color: ColorUtils.applyAlpha(root.accent, 0.48)
            opacity: Math.max(0, (root.progress - 0.80) * 5)
        }
    }
    MaterialSymbol {
        visible: !root.circle && (root.selector || Config.options.screenSnip.showCursor || root.progress < 0.97)
        x: frame.x + frame.width - 7; y: frame.y + frame.height - 6
        text: "arrow_selector_tool"; iconSize: 20; fill: 1
        color: "white"; style: Text.Outline; styleColor: "#312d2d"
    }
}
