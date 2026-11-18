pragma Singleton

import qs
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    // GlobalStates holds the committed state. The panels draw progress even before they take focus.
    readonly property GestureReveal overview: GestureReveal {
        id: overviewSurface
        open: GlobalStates.overviewOpen
        tracking: root.moving === overviewSurface
        onOpenChanged: root.stateChanged(overviewSurface)
        onPresentingChanged: if (!presenting) root.finishOverviewNavigation()
    }
    readonly property GestureReveal library: GestureReveal {
        id: librarySurface
        open: GlobalStates.appLibraryOpen
        tracking: root.moving === librarySurface
        hiddenDirection: Qt.point(0, -1)
        onOpenChanged: root.stateChanged(librarySurface)
    }
    property GestureReveal moving: null
    property string activeAction: ""
    property bool opening: false
    property real lastAmount: 0
    property string pendingOverviewCommand: ""

    property string hintAction: ""
    property real hintProgress: 0
    property bool hintDone: false
    readonly property real hintAt: 0.25

    function stateChanged(surface) {
        if (surface === overview && surface.open) pendingOverviewCommand = "";
        // A shortcut, click or focus dismissal takes precedence over an unfinished gesture.
        if (activeAction && (moving === surface || surface.open)) {
            const wasMoving = moving === surface;
            cancelGesture();
            if (wasMoving) return;
        }
        surface.settle();
    }

    // Let the chooser leave the screen before asking the compositor to focus or move a window.
    function leaveOverview(command) {
        if (moving === overview) cancelGesture();
        pendingOverviewCommand = command;
        GlobalStates.overviewOpen = false;
        if (!overview.presenting) finishOverviewNavigation();
    }

    function finishOverviewNavigation() {
        const command = pendingOverviewCommand;
        pendingOverviewCommand = "";
        if (command) Hyprland.dispatch(command);
    }

    function workspaceChanged() {
        if (!overview.presenting) return;
        pendingOverviewCommand = "";
        if (moving === overview) cancelGesture();
        GlobalStates.overviewOpen = false;
        overview.motion.stop();
        overview.progress = 0;
    }

    function cancelGesture() {
        const surface = moving;
        activeAction = "";
        moving = null;
        hintGone.stop();
        hintAction = "";
        hintDone = false;
        if (surface) surface.settle();
    }

    function begin(action, direction) {
        pendingOverviewCommand = "";
        if (activeAction || hintAction) cancelGesture();
        const requested = action === "overview" ? overview : action === "library" ? library : null;
        // Until a closing panel is offscreen it can still be caught and pulled back.
        const surface = overview.open ? overview : library.open ? library
            : overview.progress > 0 ? overview : library.progress > 0 ? library : requested;
        activeAction = action;
        lastAmount = 0;
        if (!surface) {
            hintDone = false;
            hintProgress = 0;
            hintAction = action;
            return;
        }
        const physicalDirection = direction || (action === "overview" ? "up" : action === "library" ? "down" : "pinchout");
        opening = surface.take(physicalDirection, surface === requested && !surface.open);
        moving = surface;
    }

    function handle(action, phase, progress, direction) {
        if (!["overview", "library", "desktop"].includes(action)) return;
        if (phase === "begin") {
            begin(action, direction);
            return;
        }
        if (action !== activeAction) return;
        if (phase === "cancel") {
            cancelGesture();
            return;
        }
        if ((phase !== "update" && phase !== "end") || !Number.isFinite(progress)) return;
        const amount = Math.max(0, Math.min(1, progress));
        const surface = moving;
        if (surface) {
            const delta = (amount - lastAmount) * (opening ? 1 : -1);
            surface.progress = Math.max(0, Math.min(1, surface.progress + delta));
        } else {
            hintProgress = amount;
        }
        lastAmount = amount;
        if (phase !== "end") return;

        activeAction = "";
        moving = null;
        if (!surface) {
            hintDone = amount >= hintAt;
            if (hintDone) {
                FreeWindows.showDesktop();
                hintGone.restart();
            } else {
                hintAction = "";
            }
            return;
        }

        const threshold = action === "library" ? (surface === overview ? 0.15 : 0.3) : 0.25;
        const reachedEnd = amount > 0 && surface.progress === (opening ? 1 : 0);
        if ((amount >= threshold || reachedEnd) && surface.open !== opening) {
            if (surface === overview) GlobalStates.overviewOpen = opening;
            else GlobalStates.appLibraryOpen = opening;
        } else {
            surface.settle();
        }
    }

    Timer {
        id: hintGone
        interval: 420
        onTriggered: root.hintAction = ""
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { root.workspaceChanged(); }
        function onRawEvent(event) {
            if (event.name === "workspacev2") {
                root.workspaceChanged();
                return;
            }
            if (event.name !== "custom" || !event.data.startsWith("gesture:")) return;
            const [, action, phase, amount, direction] = event.data.split(":");
            root.handle(action, phase, Number(amount), direction);
        }
    }
}
