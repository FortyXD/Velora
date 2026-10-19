import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root

    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0

    // False when the owner drives `active` itself (e.g. a click-toggled menu); hover then only positions it
    property bool hoverControlled: true
    // Interactive popups stay open while the pointer is over them, so their content can be used
    property bool interactive: false
    property int openDelay: 0 // ms of hovering before opening, so sweeping across the bar doesn't flash popups
    property bool popupHovered: false

    readonly property bool animate: Config.options.bar.microAnimations
    readonly property bool targetHovered: !!(hoverTarget && hoverTarget.containsMouse) && !GlobalStates.barEditing
    readonly property bool pointerInside: targetHovered || popupHovered
    property bool wanted: false
    onPointerInsideChanged: {
        if (pointerInside) {
            closeTimer.stop();
            if (wanted) return;
            if (openDelay > 0) openTimer.restart();
            else wanted = true;
        } else {
            openTimer.stop();
            if (!wanted) return;
            // Time to cross the gap between the bar and the popup
            if (interactive) closeTimer.restart();
            else wanted = false;
        }
    }
    property Timer openTimer: Timer {
        interval: root.openDelay
        onTriggered: root.wanted = root.pointerInside
    }
    property Timer closeTimer: Timer {
        interval: 280
        onTriggered: root.wanted = root.pointerInside
    }

    // Stays loaded for the length of the exit animation
    property bool lingering: false
    onWantedChanged: {
        if (wanted) lingeringTimer.stop();
        else if (animate && hoverControlled) {
            lingering = true;
            lingeringTimer.restart();
        }
    }
    property Timer lingeringTimer: Timer {
        interval: Appearance.animation.elementMoveFast.duration
        onTriggered: root.lingering = false
    }

    active: wanted || lingering

    component: PanelWindow {
        id: popupWindow
        color: "transparent"

        // Slides out of the bar edge it is attached to
        property bool revealed: false
        Component.onCompleted: revealed = Qt.binding(() => !root.hoverControlled || root.wanted)
        readonly property real slideDistance: root.animate && !revealed ? 6 : 0

        anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
        anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

        implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        mask: Region {
            item: popupBackground
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        // Centered on the target, but kept inside the bar's window (which spans the screen edge)
        readonly property var barWindow: root.QsWindow?.window
        function clamp(value, size, available) {
            return Math.max(0, Math.min(value, available - size));
        }
        margins {
            left: {
                if (!Config.options.bar.vertical) return popupWindow.clamp(root.QsWindow?.mapFromItem(
                    root.hoverTarget,
                    (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
                ).x, popupWindow.implicitWidth, popupWindow.barWindow?.width ?? Infinity);
                return Appearance.sizes.verticalBarWidth
            }
            top: {
                if (!Config.options.bar.vertical) return Appearance.sizes.barHeight;
                return popupWindow.clamp(root.QsWindow?.mapFromItem(
                    root.hoverTarget,
                    0, (root.hoverTarget.height - popupBackground.implicitHeight) / 2
                ).y, popupWindow.implicitHeight, popupWindow.barWindow?.height ?? Infinity);
            }
            right: Appearance.sizes.verticalBarWidth
            bottom: Appearance.sizes.barHeight
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        Item {
            anchors.fill: parent
            opacity: popupWindow.revealed || !root.animate ? 1 : 0
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
                readonly property real margin: 10

                HoverHandler {
                    enabled: root.interactive
                    onHoveredChanged: root.popupHovered = hovered
                }
                Component.onDestruction: root.popupHovered = false
                anchors {
                    fill: parent
                    leftMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                    rightMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                    topMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                    bottomMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
                }
                implicitWidth: root.contentItem.implicitWidth + margin * 2
                implicitHeight: root.contentItem.implicitHeight + margin * 2
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.small
                children: [root.contentItem]

                border.width: 1
                border.color: Appearance.colors.colLayer0Border
            }
        }
    }
}
