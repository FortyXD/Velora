import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * A bar widget shown as a chip in the layout editor. Click selects it; dragging past a few pixels
 * reports scene positions so the page can move it between zones.
 * Pill members are drawn as capsules, standalone widgets as outlined chips.
 */
Rectangle {
    id: root

    property string label
    property string icon
    property bool selected: false
    property bool pill: false
    property bool unknown: false
    property int hideAt: 0
    property bool dimmed: false
    property bool compact: false
    property bool removing: false // Dragged off the bar: goes away when let go
    readonly property bool hovered: mouseArea.containsMouse && !mouseArea.dragging

    signal clicked()
    signal dragStarted(real sceneX, real sceneY, real offsetX, real offsetY)
    signal dragMoved(real sceneX, real sceneY)
    signal dragEnded(real sceneX, real sceneY)

    readonly property color contentColor: root.unknown || root.removing ? Appearance.colors.colOnErrorContainer
        : root.selected ? Appearance.colors.colOnPrimaryContainer
        : root.pill ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2

    implicitWidth: row.implicitWidth + (root.compact ? 16 : 24)
    implicitHeight: root.compact ? 30 : 36
    radius: root.pill ? height / 2 : Appearance.rounding.small
    opacity: root.dimmed ? 0.35 : 1
    color: root.unknown || root.removing ? Appearance.colors.colErrorContainer
        : root.selected ? Appearance.colors.colPrimaryContainer
        : root.pill ? Appearance.colors.colSecondaryContainer
        : mouseArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    border.width: root.selected ? 2 : root.pill ? 0 : 1
    border.color: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        MaterialSymbol {
            text: root.removing ? "delete" : root.unknown ? "error" : root.icon
            iconSize: root.compact ? 16 : 18
            fill: root.selected ? 1 : 0
            color: root.contentColor
        }
        StyledText {
            text: root.label
            font.pixelSize: root.compact ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
            color: root.contentColor
        }
        MaterialSymbol {
            visible: root.hideAt > 0
            text: "compress"
            iconSize: 14
            color: ColorUtils.transparentize(root.contentColor, 0.35)
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.hideAt > 0
        text: root.hideAt === 1 ? Translation.tr("Hidden on narrow screens") : Translation.tr("Hidden on very narrow screens")
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property bool dragging: false
        property real pressX
        property real pressY

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            dragging = false;
        }
        onPositionChanged: mouse => {
            if (!pressed) return;
            const scene = mapToItem(null, mouse.x, mouse.y);
            if (!dragging) {
                if (Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) < 6) return;
                dragging = true;
                root.dragStarted(scene.x, scene.y, pressX, pressY);
            }
            root.dragMoved(scene.x, scene.y);
        }
        onReleased: mouse => {
            const scene = mapToItem(null, mouse.x, mouse.y);
            if (dragging) {
                dragging = false;
                root.dragEnded(scene.x, scene.y);
            } else {
                root.clicked();
            }
        }
        onCanceled: {
            if (dragging) {
                dragging = false;
                root.dragEnded(-1, -1);
            }
        }
    }
}
