import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.lock

/**
 * The real lock screen in miniature (LockScene with example data), where parts can be dragged.
 * Arrow keys nudge the selected part; double-click puts it back.
 */
Item {
    id: root
    readonly property var screen: Quickshell.screens[0] ?? null
    readonly property real sceneWidth: root.screen?.width ?? 1920
    readonly property real sceneHeight: root.screen?.height ?? 1200
    readonly property real factor: root.width / root.sceneWidth
    property alias selectedId: scene.selectedId
    property real radius: Appearance.rounding.normal

    implicitHeight: Math.round(root.width * root.sceneHeight / root.sceneWidth)
    activeFocusOnTab: true

    function playEntrance() {
        scene.exiting = false;
        scene.playEntrance(null);
    }
    function playUnlock() {
        scene.exiting = true;
        replayTimer.restart();
    }
    Timer {
        id: replayTimer
        interval: 900
        onTriggered: root.playEntrance()
    }

    Keys.onPressed: event => {
        const id = scene.selectedId;
        if (id.length === 0) return;
        const step = (event.modifiers & Qt.ShiftModifier) ? 0.0025 : 0.01;
        const host = scene.host(id);
        const x = host.center.x / scene.width;
        const y = host.center.y / scene.height;
        if (event.key === Qt.Key_Left) LockLayout.move(id, x - step, y);
        else if (event.key === Qt.Key_Right) LockLayout.move(id, x + step, y);
        else if (event.key === Qt.Key_Up) LockLayout.move(id, x, y - step);
        else if (event.key === Qt.Key_Down) LockLayout.move(id, x, y + step);
        else if (event.key === Qt.Key_Escape) scene.selectElement("");
        else return;
        event.accepted = true;
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: root.radius
        color: Appearance.colors.colLayer2
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: frame.width
                height: frame.height
                radius: frame.radius
            }
        }

        LockBackdrop {
            anchors.fill: parent
        }

        Item {
            width: root.sceneWidth
            height: root.sceneHeight
            scale: root.factor
            transformOrigin: Item.TopLeft

            LockScene {
                id: scene
                anchors.fill: parent
                liveData: false
                editing: true
                editScale: root.factor
                onElementSelected: root.forceActiveFocus()
                onElementMoved: (id, x, y) => LockLayout.move(id, x, y)
                onElementReset: id => LockLayout.resetItem(id)
            }
        }
    }

    Rectangle { // Outline
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
    }
}
