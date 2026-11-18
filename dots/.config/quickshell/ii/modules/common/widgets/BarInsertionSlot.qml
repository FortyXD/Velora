import QtQuick
import qs.modules.common
import qs.modules.common.functions

// The layout reserves the animated length on the chosen side of this widget.
Item {
    id: root
    property var guide
    property string uid: ""
    property bool vertical: false
    readonly property bool emptyZone: !uid
    readonly property bool targeted: !!guide?.target && guide.target.slot === root && !guide.target.noop
    property real extent: targeted ? (guide.target.after ? 1 : -1) * (guide.dragging ? 34 : 28) : 0
    readonly property real before: Math.max(0, -extent)
    readonly property real after: Math.max(0, extent)
    readonly property real amount: before + after
    Behavior on extent {
        NumberAnimation { duration: Appearance.scaledDuration(160); easing.type: Easing.OutCubic }
    }

    // Apply the release displacement to the widget without moving its layout or its pointer grab.
    property Translate placement: Translate {}
    function settle(dx, dy) {
        settleAnimation.stop();
        placement.x += dx;
        placement.y += dy;
        settleAnimation.start();
    }
    ParallelAnimation {
        id: settleAnimation
        NumberAnimation { target: root.placement; property: "x"; to: 0; duration: Appearance.scaledDuration(190); easing.type: Easing.OutCubic }
        NumberAnimation { target: root.placement; property: "y"; to: 0; duration: Appearance.scaledDuration(190); easing.type: Easing.OutCubic }
    }

    x: emptyZone || vertical ? (parent.width - width) / 2 : extent < 0 ? -before : parent.width
    y: emptyZone || !vertical ? (parent.height - height) / 2 : extent < 0 ? -before : parent.height
    width: vertical ? 24 : amount
    height: vertical ? amount : 24
    visible: amount > 0.1
    z: 2

    Loader {
        anchors.fill: parent
        active: root.visible
        opacity: Math.min(1, root.amount / 26)
        sourceComponent: Rectangle {
            radius: Math.max(0, Math.min(7, width / 2, height / 2))
            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.89)
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.52)
            clip: true
            MaterialSymbol {
                anchors.centerIn: parent
                text: "add"
                iconSize: 15
                color: Appearance.colors.colPrimary
            }
        }
    }
}
