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
    property int closeDelay: 280 // ms to cross the gap between the bar and the popup before it closes
    // An owner that measures the pointer can ask to close at once (a flick). It also latches:
    // the popup must not pop back while the pointer is still inside it, and re-arms on the bar.
    property bool hideInstantly: false
    property bool dismissed: false
    property bool popupHovered: false

    readonly property bool animate: Config.options.bar.microAnimations
    readonly property bool targetHovered: !!(hoverTarget && hoverTarget.containsMouse) && !GlobalStates.barEditing
    readonly property bool pointerInside: targetHovered || popupHovered
    property bool wanted: false
    onTargetHoveredChanged: if (targetHovered) root.dismissed = false
    onPointerInsideChanged: {
        const next = PopupHoverPolicy.next(wanted, dismissed, pointerInside, hideInstantly,
            interactive, openDelay > 0);
        dismissed = next.dismissed;
        if (next.stopOpen) openTimer.stop();
        if (next.stopClose) closeTimer.stop();
        if (next.startOpen) openTimer.restart();
        if (next.startClose) closeTimer.restart();
        wanted = next.wanted;
    }
    property Timer openTimer: Timer {
        interval: root.openDelay
        onTriggered: root.wanted = PopupHoverPolicy.timerWanted(root.pointerInside, root.dismissed)
    }
    property Timer closeTimer: Timer {
        interval: root.closeDelay
        onTriggered: root.wanted = PopupHoverPolicy.timerWanted(root.pointerInside, root.dismissed)
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
        // Centered on the target, but kept inside the bar's window (which spans the screen edge).
        // The card sits elevationMargin inside the window (room for its shadow), so the window starts that much earlier
        readonly property var barWindow: root.QsWindow?.window
        function clamp(value, size, available) {
            return Math.max(0, Math.min(value, available - size));
        }
        margins {
            left: {
                if (!Config.options.bar.vertical) return popupWindow.clamp(root.QsWindow?.mapFromItem(
                    root.hoverTarget,
                    (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
                ).x - Appearance.sizes.elevationMargin, popupWindow.implicitWidth, popupWindow.barWindow?.width ?? Infinity);
                return Appearance.sizes.verticalBarWidth
            }
            top: {
                if (!Config.options.bar.vertical) return Appearance.sizes.barHeight;
                return popupWindow.clamp(root.QsWindow?.mapFromItem(
                    root.hoverTarget,
                    0, (root.hoverTarget.height - popupBackground.implicitHeight) / 2
                ).y - Appearance.sizes.elevationMargin, popupWindow.implicitHeight, popupWindow.barWindow?.height ?? Infinity);
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
                readonly property real margin: Appearance.popup.padding

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
                color: Appearance.popup.colBackground
                radius: Appearance.popup.radius
                children: [root.contentItem]

                border.width: 1
                border.color: Appearance.popup.colBorder
            }
        }
    }
}
