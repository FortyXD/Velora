import QtQuick

/** A selection ending in a corner is not a fresh, intentional corner entry. */
QtObject {
    id: root
    property bool suppressed: false
    property bool waitingForExit: false
    readonly property bool allowed: !suppressed && !waitingForExit

    property string corner: "topLeft"
    property real screenX: 0
    property real screenY: 0
    property real screenWidth: 0
    property real screenHeight: 0
    property real size: 6
    property bool circular: false

    onSuppressedChanged: if (suppressed) waitingForExit = true
    Component.onCompleted: if (suppressed) waitingForExit = true

    function resumeAt(x, y, valid) {
        const left = screenX + (corner.endsWith("Left") ? 0 : screenWidth - size);
        const top = screenY + (corner.startsWith("top") ? 0 : screenHeight - size);
        const onScreen = x >= screenX && x < screenX + screenWidth
            && y >= screenY && y < screenY + screenHeight;
        const dx = x - (screenX + (corner.endsWith("Left") ? 0 : screenWidth));
        const dy = y - (screenY + (corner.startsWith("top") ? 0 : screenHeight));
        const inside = circular ? onScreen && dx * dx + dy * dy <= size * size
            : x >= left && x < left + size && y >= top && y < top + size;
        waitingForExit = !valid || screenWidth <= 0 || screenHeight <= 0 || inside;
    }

    function pointerExited() {
        // An exit caused by hiding the corner during selection must not rearm it.
        if (!suppressed) waitingForExit = false;
    }
}
