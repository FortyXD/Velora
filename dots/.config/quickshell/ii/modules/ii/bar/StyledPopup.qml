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
    property bool hoverEnabled: true
    property bool keepOpen: false // Retain an open popup over the panel, never open it there
    property bool closeImmediately: false // Bypass the grace period AND exit animation

    property bool animate: Config.options.bar.microAnimations
    property PopupHoverTarget targetPresence: PopupHoverTarget {
        target: root.hoverTarget
        enabled: root.hoverControlled && !GlobalStates.barEditing && root.hoverEnabled && !!root.hoverTarget?.enabled
    }
    readonly property bool targetHovered: targetPresence.containsMouse
    readonly property bool pointerInside: targetHovered || (interactive && popupHovered)
    property bool wanted: false
    onHoverControlledChanged: {
        openTimer.stop();
        closeTimer.stop();
        wanted = false;
        lingeringTimer.stop();
        lingering = false;
        dismissed = false;
    }
    onTargetHoveredChanged: {
        if (targetHovered) root.dismissed = false;
        if (targetHovered) updateHover();
    }
    onPointerInsideChanged: updateHover()
    // Mode bindings settle together before reconciling retention/interaction. Closing
    // at a real panel boundary (or disabling) is still synchronous, never deferred.
    onKeepOpenChanged: Qt.callLater(updateHover)
    onHoverEnabledChanged: updateHover()
    onCloseImmediatelyChanged: {
        if (closeImmediately) updateHover();
        else Qt.callLater(updateHover);
    }
    onInteractiveChanged: Qt.callLater(updateHover)

    function updateHover() {
        if (!hoverControlled) return;
        if (!hoverEnabled || closeImmediately) {
            openTimer.stop();
            closeTimer.stop();
            lingeringTimer.stop();
            wanted = false;
            lingering = false;
            popupHovered = false;
            dismissed = false;
            return;
        }
        const next = PopupHoverPolicy.next(wanted, dismissed, pointerInside, hideInstantly,
            interactive, openDelay > 0, hoverEnabled, keepOpen);
        dismissed = next.dismissed;
        if (next.stopOpen) openTimer.stop();
        if (next.stopClose) closeTimer.stop();
        if (next.startOpen) openTimer.restart();
        if (next.startClose) closeTimer.restart();
        wanted = next.wanted;
    }
    property Timer openTimer: Timer {
        interval: root.openDelay
        onTriggered: if (root.hoverControlled) root.wanted = root.hoverEnabled && !root.closeImmediately
            && PopupHoverPolicy.timerWanted(root.pointerInside, root.dismissed)
    }
    property Timer closeTimer: Timer {
        interval: root.closeDelay
        onTriggered: if (root.hoverControlled) root.wanted = root.hoverEnabled && !root.closeImmediately
            && PopupHoverPolicy.timerWanted(root.pointerInside || root.keepOpen, root.dismissed)
    }

    // Stays loaded for the length of the exit animation
    property bool lingering: false
    onWantedChanged: {
        if (wanted) lingeringTimer.stop();
        else if (animate && hoverControlled && hoverEnabled && !closeImmediately) {
            lingering = true;
            lingeringTimer.restart();
        }
    }
    property Timer lingeringTimer: Timer {
        interval: Appearance.animation.elementMoveFast.duration
        onTriggered: root.lingering = false
    }

    active: wanted || lingering

    // Embedded bar widgets have no native panel. Resolve the compositor window only when a popup opens.
    component: Loader {
        Component.onCompleted: setSource(Qt.resolvedUrl("StyledPopupWindow.qml"), { owner: root })
    }
}
