import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Dragging in a bar window while it is edited: widgets already on the bar (move) and widgets from
 * the edit drawer's palette (add). Draws the dragged picture and the drop marker above everything.
 * Positions are scene coordinates of the bar window.
 */
Item {
    id: root

    property var view: null // BarLayoutView of this window
    property var dragState: null // { mode: "move"|"add", uid, type, host, offsetX, offsetY }
    property var target: null // { zone, index, x } from view.dropTargetAt
    readonly property bool dragging: dragState !== null

    anchors.fill: parent
    z: 1000

    function start(state, sceneX, sceneY) {
        root.dragState = state;
        if (state.host) {
            ghostImage.sourceItem = state.host;
            ghostImage.scheduleUpdate();
            state.host.dragHidden = true;
        }
        root.update(sceneX, sceneY);
    }

    function update(sceneX, sceneY) {
        if (!root.dragState) return;
        const local = root.mapFromItem(null, sceneX, sceneY);
        ghost.x = local.x - root.dragState.offsetX;
        ghost.y = local.y - root.dragState.offsetY;
        const p = root.view.mapFromItem(null, sceneX, sceneY);
        const slack = 24; // Dropping a bit off the bar still counts
        const overBar = p.y >= -slack && p.y <= root.view.height + slack;
        root.target = overBar ? root.view.dropTargetAt(p.x, p.y, root.dragState.mode === "move" ? root.dragState.uid : "") : null;
    }

    function finish(sceneX, sceneY) {
        if (!root.dragState) return;
        root.update(sceneX, sceneY);
        const state = root.dragState;
        const target = root.target;
        ghostImage.sourceItem = null;
        root.dragState = null;
        root.target = null;
        if (!target) {
            if (state.host) state.host.dragHidden = false;
            return;
        }
        // The host may be rebuilt by the change; it is no longer referenced after this
        if (state.mode === "move") {
            BarLayout.move(root.view.orientation, state.uid, target.zone, target.index);
            if (state.host) state.host.dragHidden = false;
            GlobalStates.barEditSelection = state.uid;
        } else {
            GlobalStates.barEditSelection = BarLayout.insert(root.view.orientation, state.type, target.zone, target.index);
        }
    }

    function cancel() {
        if (root.dragState?.host) root.dragState.host.dragHidden = false;
        ghostImage.sourceItem = null;
        root.dragState = null;
        root.target = null;
    }

    Item {
        id: ghost
        visible: root.dragging
        opacity: 0.9
        implicitWidth: root.dragState?.mode === "add" ? chip.implicitWidth : ghostImage.width
        implicitHeight: root.dragState?.mode === "add" ? chip.implicitHeight : ghostImage.height

        ShaderEffectSource {
            id: ghostImage
            visible: root.dragState?.mode === "move"
            live: false
            width: sourceItem?.width ?? 0
            height: sourceItem?.height ?? 0
        }

        Rectangle {
            id: chip
            readonly property var meta: BarWidgetCatalog.get(root.dragState?.type ?? "")
            visible: root.dragState?.mode === "add"
            implicitWidth: chipRow.implicitWidth + 20
            implicitHeight: 32
            radius: height / 2
            color: Appearance.colors.colPrimaryContainer
            border.width: 1
            border.color: Appearance.colors.colPrimary
            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.meta?.icon ?? "help"
                    iconSize: 18
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.meta?.name ?? ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }

    Rectangle { // Where the widget will land
        visible: root.target !== null && root.view !== null
        readonly property point origin: root.view ? root.view.mapToItem(root, root.target?.x ?? 0, 0) : Qt.point(0, 0)
        x: origin.x - width / 2
        y: origin.y + 6
        width: 3
        height: (root.view?.height ?? 12) - 12
        radius: 2
        color: Appearance.colors.colPrimary
    }
}
