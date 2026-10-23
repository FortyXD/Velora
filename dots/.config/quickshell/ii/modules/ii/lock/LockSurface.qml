import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.panels.lock

/**
 * The real lock screen on one monitor: the shared LockScene with the lock context, keeping the
 * password field focused. The wallpaper behind it is Background.qml's (blurred while locked).
 */
MouseArea {
    id: root
    required property LockContext context
    property string screenName: ""

    // Force focus on entry
    function forceFieldFocus() {
        scene.passwordBar.forceFieldFocus();
    }
    Connections {
        target: root.context
        function onShouldReFocus() {
            root.forceFieldFocus();
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => {
        root.forceFieldFocus();
    }
    onPositionChanged: mouse => {
        root.forceFieldFocus();
    }

    Component.onCompleted: {
        root.forceFieldFocus();
        Qt.callLater(root.playEntrance); // After the screen name is set
    }
    function playEntrance() {
        // The clock comes from where the desktop clock was
        const clocks = LockLayout.desktopClocks;
        const from = clocks[root.screenName] ?? clocks[Object.keys(clocks)[0]];
        scene.playEntrance(from && from.visible ? Qt.rect(from.x, from.y, from.width, from.height) : null);
    }

    // Key presses
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        root.context.noteTypedKey(event);
        if (event.key === Qt.Key_Control) {
            scene.passwordBar.ctrlHeld = true;
        }
        if (event.key === Qt.Key_Escape) { // Esc to clear
            root.context.currentText = "";
        }
        root.forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control) {
            scene.passwordBar.ctrlHeld = false;
        }
        root.forceFieldFocus();
    }

    LockScene {
        id: scene
        anchors.fill: parent
        context: root.context
        liveData: true
        startHidden: true
        exiting: GlobalStates.lockExiting
    }
}
