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
    // Accumulated scroll destination so wheel deltas stack while animating
    property real scrollTargetY: 0

    ScrollBar.vertical: StyledScrollBar {}

    // Mouse wheel notches glide; a touchpad follows the fingers directly. Animating each of the many small
    // touchpad steps (the old Behavior did, for every contentY change) made scrolling lag behind and wobble.
    property bool wheelGliding: false

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheelEvent) {
            const maxY = Math.max(0, root.contentHeight - root.height);
            // Sideways scrolling, or nothing to scroll here: leave it to the flickable or the one around it
            if (Math.abs(wheelEvent.angleDelta.x) > Math.abs(wheelEvent.angleDelta.y) || maxY <= 0) {
                wheelEvent.accepted = false;
                return;
            }
            // The angleDelta.y of a mouse wheel comes in multiples of ±120; a touchpad sends small pixel steps
            const mouseWheel = wheelEvent.pixelDelta.y === 0 && Math.abs(wheelEvent.angleDelta.y) >= root.mouseScrollDeltaThreshold;
            const notches = wheelEvent.angleDelta.y / root.mouseScrollDeltaThreshold;
            const base = scrollAnim.running ? root.scrollTargetY : root.contentY;
            let step;
            if (mouseWheel) step = notches * root.mouseScrollFactor;
            else if (Config?.options.interactions.scrolling.fasterTouchpadScroll) step = notches * root.touchpadScrollFactor;
            else step = wheelEvent.pixelDelta.y !== 0 ? wheelEvent.pixelDelta.y : wheelEvent.angleDelta.y / 2;
            const targetY = Math.max(0, Math.min(base - step, maxY));
            // Already at the end: an outer flickable may scroll instead
            if (Math.abs(targetY - root.contentY) < 0.5 && !scrollAnim.running) {
                wheelEvent.accepted = false;
                return;
            }
            root.cancelFlick();
            if (!mouseWheel) scrollAnim.stop();
            root.wheelGliding = mouseWheel;
            root.scrollTargetY = targetY;
            root.contentY = targetY;
            wheelEvent.accepted = true;
        }
    }

    Behavior on contentY {
        enabled: root.wheelGliding
        NumberAnimation {
            id: scrollAnim
            duration: Appearance.animation.scroll.duration
            easing.type: Appearance.animation.scroll.type
            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
            onRunningChanged: if (!running) root.wheelGliding = false
        }
    }

    // Keep target synced when not animating (e.g., drag/flick or programmatic changes)
    onContentYChanged: {
        if (!scrollAnim.running) {
            root.scrollTargetY = root.contentY;
        }
    }

}
