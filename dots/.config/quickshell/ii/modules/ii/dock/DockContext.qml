import qs.modules.common
import QtQuick

/**
 * State shared by everything in one dock: sizes, magnification and the hovered tile.
 * Positions are in row coordinates, where tiles keep their unmagnified size.
 *
 * Magnification treats the row as a strip that stretches under the cursor by
 * a smooth bump. Each point moves by the integral of that stretch, so a tile
 * only needs its own resting center to know where to draw itself.
 */
Item {
    id: root
    visible: false

    readonly property real barHeight: Config.options?.dock.height ?? 60
    readonly property real topPadding: Math.round(barHeight * 0.1)
    readonly property real bottomPadding: Math.round(barHeight * 0.17) // Room for the running indicator
    readonly property real iconSize: barHeight - topPadding - bottomPadding
    readonly property real gap: Math.round(iconSize * 0.14)
    readonly property real slotWidth: iconSize + gap
    readonly property real separatorWidth: gap * 2 + 1
    readonly property real sidePadding: Math.max(0, topPadding - gap / 2)
    readonly property real bounceHeight: Math.round(iconSize * 0.45)

    readonly property real maxScale: (Config.options?.dock.magnification ?? true)
        ? Math.max(1, Math.min(2, Config.options?.dock.magnificationScale ?? 1.6)) : 1
    readonly property real range: slotWidth * 2.6
    readonly property real headroom: iconSize * (maxScale - 1) + bounceHeight + 48

    property bool magnifying: false
    property real pointerX: 0
    property real rowWidth: 0
    property real amount: magnifying ? 1 : 0
    Behavior on amount {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    readonly property real strength: (maxScale - 1) * amount
    // How much wider the row is drawn than it is laid out
    readonly property real growth: strength * range * (integral((rowWidth - pointerX) / range) - integral(-pointerX / range))

    property Item hoveredTile: null
    property bool menuOpen: false
    property bool previewsOpen: false

    signal appMenuRequested(Item tile)
    signal dockMenuRequested(Item tile)
    signal tileActivated(Item tile)

    function bump(u) {
        return Math.abs(u) >= 1 ? 0 : (1 + Math.cos(Math.PI * u)) / 2;
    }

    function integral(u) { // Of bump from -1 to u
        if (u <= -1) return 0;
        if (u >= 1) return 1;
        return (u + 1) / 2 + Math.sin(Math.PI * u) / (2 * Math.PI);
    }

    function scaleAt(center) {
        return 1 + root.strength * root.bump((center - root.pointerX) / root.range);
    }

    function shiftAt(center) {
        if (root.strength === 0) return 0;
        const middle = (root.integral(-root.pointerX / root.range) + root.integral((root.rowWidth - root.pointerX) / root.range)) / 2;
        return root.strength * root.range * (root.integral((center - root.pointerX) / root.range) - middle);
    }
}
