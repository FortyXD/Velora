import qs
import QtQuick

/**
 * Covers the bar while it is edited, so widgets don't react: click selects a widget, dragging
 * moves it (through the window's BarEditController), right click opens the edit menu.
 */
MouseArea {
    id: root

    required property var view
    required property var controller

    property var pressedHost: null
    property real pressX: 0
    property real pressY: 0
    property bool dragStarted: false

    anchors.fill: parent
    z: 100
    hoverEnabled: true
    preventStealing: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: dragStarted ? Qt.ClosedHandCursor : GlobalStates.barEditHovered.length > 0 ? Qt.OpenHandCursor : Qt.ArrowCursor

    function hostUnder(x, y) {
        return root.view.hostAt(x, y);
    }

    onPressed: mouse => {
        const host = root.hostUnder(mouse.x, mouse.y);
        if (mouse.button === Qt.RightButton) {
            if (host) GlobalStates.barEditSelection = host.uid;
            root.view.openEditMenu(host, mouse.x, mouse.y);
            return;
        }
        root.pressedHost = host;
        root.pressX = mouse.x;
        root.pressY = mouse.y;
        root.dragStarted = false;
    }

    onPositionChanged: mouse => {
        if (!(mouse.buttons & Qt.LeftButton) || !root.pressedHost) {
            GlobalStates.barEditHovered = root.hostUnder(mouse.x, mouse.y)?.uid ?? "";
            return;
        }
        const scene = root.mapToItem(null, mouse.x, mouse.y);
        if (!root.dragStarted) {
            if (Math.abs(mouse.x - root.pressX) + Math.abs(mouse.y - root.pressY) < 6) return;
            root.dragStarted = true;
            const offset = root.pressedHost.mapFromItem(root, root.pressX, root.pressY);
            root.controller.start({
                "mode": "move",
                "uid": root.pressedHost.uid,
                "type": root.pressedHost.type,
                "host": root.pressedHost,
                "offsetX": offset.x,
                "offsetY": offset.y
            }, scene.x, scene.y);
        }
        root.controller.update(scene.x, scene.y);
    }

    onReleased: mouse => {
        if (mouse.button !== Qt.LeftButton) return;
        if (root.dragStarted) {
            const scene = root.mapToItem(null, mouse.x, mouse.y);
            root.controller.finish(scene.x, scene.y);
        } else {
            GlobalStates.barEditSelection = root.pressedHost?.uid ?? "";
        }
        root.pressedHost = null;
        root.dragStarted = false;
    }

    onCanceled: {
        if (root.dragStarted) root.controller.cancel();
        root.pressedHost = null;
        root.dragStarted = false;
    }

    onExited: GlobalStates.barEditHovered = ""
}
