pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * Three small windows opening one after another: overlapping where they were put (free), or sharing
 * the screen (tiling). Plays again whenever the choice changes.
 */
Rectangle {
    id: root
    property bool free: true
    implicitWidth: 240
    implicitHeight: 140
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    clip: true

    // x, y, width, height as fractions, per mode
    readonly property var freePlaces: [[0.05, 0.1, 0.5, 0.56], [0.28, 0.26, 0.5, 0.56], [0.5, 0.4, 0.44, 0.5]]
    readonly property var tiledPlaces: [[0.03, 0.05, 0.47, 0.9], [0.52, 0.05, 0.45, 0.43], [0.52, 0.52, 0.45, 0.43]]
    property int opened: 0

    onFreeChanged: replay()
    Component.onCompleted: replay()
    function replay() {
        root.opened = 0;
        openTimer.restart();
    }
    Timer {
        id: openTimer
        interval: Motion.ms(220)
        repeat: true
        onTriggered: {
            root.opened++;
            if (root.opened >= 3) stop();
        }
    }

    Repeater {
        model: 3
        delegate: Rectangle {
            id: window
            required property int index
            readonly property var place: (root.free ? root.freePlaces : root.tiledPlaces)[index]
            readonly property bool open: index < root.opened
            x: place[0] * root.width
            y: place[1] * root.height
            width: place[2] * root.width
            height: place[3] * root.height
            radius: 6
            color: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1, index * 0.25)
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.85)
            opacity: open ? 1 : 0
            scale: open ? 1 : 0.85
            z: index
            Behavior on x { NumberAnimation { duration: Motion.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial } }
            Behavior on y { NumberAnimation { duration: Motion.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial } }
            Behavior on width { NumberAnimation { duration: Motion.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial } }
            Behavior on height { NumberAnimation { duration: Motion.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial } }
            Behavior on opacity { NumberAnimation { duration: Motion.ms(200) } }
            Behavior on scale { NumberAnimation { duration: Motion.ms(320); easing.type: Easing.OutBack } }

            // A title strip, so they read as windows
            Rectangle {
                width: parent.width
                height: 8
                radius: 6
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.88)
            }
        }
    }
}
