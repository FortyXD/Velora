import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions

/**
 * An animated wallpaper drawn by a shader (assets/shaders/<name>.frag.qsb). It's drawn at `renderScale`
 * of its size and scaled up, and time only moves while `running`, so a paused one costs nothing.
 * `colors`: four colors (three accents and the background), or empty for the theme's.
 */
Item {
    id: root
    property string name: ""
    property bool running: true
    property real speed: 1
    property int fps: 30
    property var colors: []
    property real renderScale: 0.5
    property real time: 40 + Math.random() * 100 // Somewhere along the loop, so two views differ

    readonly property var themeColors: [Appearance.m3colors.m3primary, Appearance.m3colors.m3tertiary, Appearance.m3colors.m3secondary,
        Appearance.m3colors.darkmode ? Appearance.m3colors.m3background : ColorUtils.mix(Appearance.m3colors.m3primary, "black", 0.35)]
    readonly property var usedColors: (root.colors && root.colors.length >= 4) ? root.colors : root.themeColors

    Timer {
        running: root.running && root.visible && root.name.length > 0
        repeat: true
        interval: Math.round(1000 / Math.max(5, Math.min(60, root.fps)))
        onTriggered: root.time += interval / 1000 * root.speed
    }

    Item {
        id: target
        width: Math.ceil(root.width * root.renderScale)
        height: Math.ceil(root.height * root.renderScale)
        scale: 1 / root.renderScale
        transformOrigin: Item.TopLeft
        layer.enabled: root.renderScale < 1
        layer.smooth: true

        ShaderEffect {
            anchors.fill: parent
            visible: root.name.length > 0
            fragmentShader: root.name.length > 0 ? Quickshell.shellPath(`assets/shaders/${root.name}.frag.qsb`) : ""
            property real time: root.time
            property vector2d resolution: Qt.vector2d(root.width, root.height)
            property color color1: root.usedColors[0]
            property color color2: root.usedColors[1]
            property color color3: root.usedColors[2]
            property color color4: root.usedColors[3]
        }
    }
}
