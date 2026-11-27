import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets

PanelWindow {
    id: popupWindow
    required property var owner
    color: "transparent"

    // Slides out of the bar edge it is attached to
    property bool revealed: false
    Component.onCompleted: revealed = Qt.binding(() => !popupWindow.owner.hoverControlled || popupWindow.owner.wanted)
    readonly property real slideDistance: popupWindow.owner.animate && !revealed ? 6 : 0

    anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
    anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
    anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
    anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

    implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + popupWindow.owner.popupBackgroundMargin
    implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + popupWindow.owner.popupBackgroundMargin

    mask: Region {
        item: popupBackground
    }

    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    // Centered on the target, but kept inside the bar's window (which spans the screen edge).
    // The card sits elevationMargin inside the window (room for its shadow), so the window starts that much earlier
    readonly property var barWindow: popupWindow.owner.QsWindow?.window
    function clamp(value, size, available) {
        return Math.max(0, Math.min(value, available - size));
    }
    // mapFromItem needs the target inside a window already; during a hotplug or the
    // popup's own creation it is not, and Qt logged "Cannot call mapFromItem before
    // item is a member of a window". Fall back to the edge padding instead.
    function centeredOnTarget(axis, targetSize, popupSize, barSize, margin) {
        if (!popupWindow.owner.hoverTarget || !popupWindow.owner.hoverTarget.QsWindow?.window || !popupWindow.owner.QsWindow?.window || barSize === undefined) return undefined;
        return popupWindow.clamp(popupWindow.owner.QsWindow.mapFromItem(popupWindow.owner.hoverTarget,
            axis === 'x' ? (targetSize - popupSize) / 2 : 0,
            axis === 'x' ? 0 : (targetSize - popupSize) / 2)[axis] - margin, popupSize, barSize);
    }
    margins {
        left: {
            if (!Config.options.bar.vertical) {
                const placed = popupWindow.centeredOnTarget('x', popupWindow.owner.hoverTarget?.width ?? 0,
                    popupBackground.implicitWidth, popupWindow.barWindow?.width, Appearance.sizes.elevationMargin);
                return placed !== undefined ? placed : Appearance.sizes.elevationMargin;
            }
            return Appearance.sizes.verticalBarWidth
        }
        top: {
            if (!Config.options.bar.vertical) return Appearance.sizes.barHeight;
            const placed = popupWindow.centeredOnTarget('y', popupWindow.owner.hoverTarget?.height ?? 0,
                popupBackground.implicitHeight, popupWindow.barWindow?.height, Appearance.sizes.elevationMargin);
            return placed !== undefined ? placed : Appearance.sizes.elevationMargin;
        }
        right: Appearance.sizes.verticalBarWidth
        bottom: Appearance.sizes.barHeight
    }
    WlrLayershell.namespace: "quickshell:popup"
    WlrLayershell.layer: WlrLayer.Overlay

    Item {
        anchors.fill: parent
        opacity: popupWindow.revealed || !popupWindow.owner.animate ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        transform: Translate {
            x: !Config.options.bar.vertical ? 0 : Config.options.bar.bottom ? popupWindow.slideDistance : -popupWindow.slideDistance
            y: Config.options.bar.vertical ? 0 : Config.options.bar.bottom ? popupWindow.slideDistance : -popupWindow.slideDistance
            Behavior on x {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on y {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        StyledRectangularShadow {
            target: popupBackground
        }

        Rectangle {
            id: popupBackground
            readonly property real margin: Appearance.popup.padding

            HoverHandler {
                enabled: popupWindow.owner.interactive
                onHoveredChanged: popupWindow.owner.popupHovered = hovered
            }
            Component.onDestruction: popupWindow.owner.popupHovered = false
            anchors {
                fill: parent
                leftMargin: Appearance.sizes.elevationMargin + popupWindow.owner.popupBackgroundMargin * (!popupWindow.anchors.left)
                rightMargin: Appearance.sizes.elevationMargin + popupWindow.owner.popupBackgroundMargin * (!popupWindow.anchors.right)
                topMargin: Appearance.sizes.elevationMargin + popupWindow.owner.popupBackgroundMargin * (!popupWindow.anchors.top)
                bottomMargin: Appearance.sizes.elevationMargin + popupWindow.owner.popupBackgroundMargin * (!popupWindow.anchors.bottom)
            }
            implicitWidth: popupWindow.owner.contentItem.implicitWidth + margin * 2
            implicitHeight: popupWindow.owner.contentItem.implicitHeight + margin * 2
            color: Appearance.popup.colBackground
            radius: Appearance.popup.radius
            children: [popupWindow.owner.contentItem]

            border.width: 1
            border.color: Appearance.popup.colBorder
        }
    }
}
