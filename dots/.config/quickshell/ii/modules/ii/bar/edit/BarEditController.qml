import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

/**
 * Dragging in a bar window while it is edited: widgets already on the bar (move) and widgets from
 * the edit drawer's palette (add). The preview follows the pointer above the bar while the guide opens a gap.
 * A widget taken off the bar (into the drawer, say) turns red and is removed when let go.
 * Positions are scene coordinates of the bar window.
 */
Item {
    id: root

    property var view: null // BarLayoutView of this window
    property var dragState: null // { mode: "move"|"add", uid, type, host, offsetX, offsetY }
    property bool removing: false
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
        const overBar = root.view.vertical ? (p.x >= -slack && p.x <= root.view.width + slack)
            : (p.y >= -slack && p.y <= root.view.height + slack);
        if (overBar) root.view.editGuide.updateAt(sceneX, sceneY, true);
        else root.view.editGuide.clear();
        const away = slack * 2;
        root.removing = root.dragState.mode === "move" && (root.view.vertical ? (p.x < -away || p.x > root.view.width + away)
            : (p.y < -away || p.y > root.view.height + away));
    }

    function finish(sceneX, sceneY) {
        if (!root.dragState) return;
        root.update(sceneX, sceneY);
        const state = root.dragState;
        const guide = root.view.editGuide;
        const target = guide.target;
        const removing = root.removing;
        const points = guide.capture();
        const release = ghost.mapToItem(null, ghost.width / 2, ghost.height / 2);
        root.cancel();
        if (removing) {
            if (GlobalStates.barEditSelection === state.uid) GlobalStates.barEditSelection = "";
            BarLayout.remove(root.view.orientation, state.uid);
            guide.settle(points);
        } else if (target) {
            let uid = state.uid;
            if (state.mode === "move") {
                if (!target.noop) BarLayout.move(root.view.orientation, uid, target.zone, target.index);
            } else uid = BarLayout.insert(root.view.orientation, state.type, target.zone, target.index);
            GlobalStates.barEditSelection = uid;
            guide.settle(points, uid, release);
        }
    }

    function cancel() {
        if (root.dragState?.host) root.dragState.host.dragHidden = false;
        ghostImage.sourceItem = null;
        root.dragState = null;
        root.view?.editGuide?.clear();
        root.removing = false;
    }

    Item {
        id: ghost
        visible: root.dragging
        scale: root.dragging ? (root.removing ? 0.93 : 1.04) : 0.98
        Behavior on scale { NumberAnimation { duration: Appearance.scaledDuration(140); easing.type: Easing.OutCubic } }
        opacity: root.removing ? 0.75 : 0.95
        Behavior on opacity { NumberAnimation { duration: Appearance.scaledDuration(120) } }
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

        Rectangle { // Off the bar: it goes away when let go
            visible: root.removing
            anchors.fill: parent
            radius: Math.min(height / 2, Appearance.rounding.small)
            color: ColorUtils.transparentize(Appearance.colors.colErrorContainer, 0.15)
            border.width: 2
            border.color: Appearance.colors.colError
            MaterialSymbol {
                anchors.centerIn: parent
                text: "delete"
                iconSize: Math.min(parent.height - 6, 20)
                color: Appearance.colors.colOnErrorContainer
            }
        }
    }

}
