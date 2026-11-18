import qs.modules.common
import QtQuick

QtObject {
    id: surface
    required property bool open
    required property bool tracking
    property real progress: 0
    readonly property bool presenting: open || tracking || progress > 0
    property point hiddenDirection: Qt.point(0, 1)
    property real hiddenScale: 0.96
    readonly property real scale: 1 + (hiddenScale - 1) * (1 - progress)
    readonly property real offsetX: hiddenDirection.x * (1 - progress)
    readonly property real offsetY: hiddenDirection.y * (1 - progress)

    function take(direction, opening) {
        motion.stop();
        const dx = direction === "left" ? -1 : direction === "right" ? 1 : 0;
        const dy = direction === "up" ? -1 : direction === "down" ? 1 : 0;
        // Catch the current frame. Movement toward its hidden edge closes it, away opens it.
        if (progress > 0 && progress < 1) {
            const alongPath = dx * hiddenDirection.x + dy * hiddenDirection.y;
            if (alongPath) return alongPath < 0;
            if (!dx && !dy && !hiddenDirection.x && !hiddenDirection.y)
                return (direction === "pinchin") === (hiddenScale > 1);
            return opening;
        }
        const sign = opening ? -1 : 1;
        hiddenDirection = Qt.point(sign * dx, sign * dy);
        hiddenScale = dx || dy ? 0.96 : ((direction === "pinchin") === opening ? 1.18 : 0.82);
        return opening;
    }

    function settle() {
        motion.stop();
        const end = open ? 1 : 0;
        const distance = Math.abs(end - progress);
        const duration = Appearance.scaledDuration(260 * Math.sqrt(distance));
        if (duration === 0 || distance < 0.001) {
            progress = end;
            return;
        }
        motion.from = progress;
        motion.to = end;
        motion.duration = duration;
        motion.start();
    }

    readonly property NumberAnimation motion: NumberAnimation {
        target: surface
        property: "progress"
        easing.type: Easing.OutCubic
    }
}
