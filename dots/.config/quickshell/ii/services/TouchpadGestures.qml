pragma Singleton

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Touchpad gestures the shell draws (hyprland/gestures.lua sends their progress as
 * `custom>>gesture:<action>:<phase>:<progress>` events). Four fingers toward you close the overview
 * when it's open, close the app library when that's open, and otherwise pull the library out under
 * your fingers; four fingers up open the overview.
 */
Singleton {
    id: root

    // The app library follows this while a gesture moves it: 0 hidden, 1 open; -1 when no gesture does
    property real libraryProgress: -1
    property string libraryGesture: "" // "open" or "close" while a gesture moves the library
    readonly property real commitAt: 0.3

    // What a gesture without its own picture is about to do, for the hint at the bottom of the screen
    // (modules/ii/gestureHint): the action while fingers move, and how far along they are
    property string hintAction: ""
    property real hintProgress: 0
    property bool hintDone: false // Let go past the point: it happened
    readonly property real hintAt: 0.25

    function handle(action, phase, progress) {
        if (action === "overview" || action === "desktop") {
            if (phase === "begin") {
                hintGone.stop();
                root.hintDone = false;
                root.hintProgress = 0;
                root.hintAction = action;
                return;
            }
            root.hintProgress = progress;
            if (phase === "update") return;
            const done = phase === "end" && progress >= root.hintAt;
            root.hintDone = done;
            hintGone.restart();
            if (!done) return;
            if (action === "desktop") {
                FreeWindows.showDesktop();
            } else if (GlobalStates.appLibraryOpen) {
                GlobalStates.appLibraryOpen = false;
            } else {
                GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
            }
            return;
        }
        if (action !== "library") return;
        if (phase === "begin") {
            if (GlobalStates.overviewOpen) {
                root.libraryGesture = "overview";
                return;
            }
            root.libraryGesture = GlobalStates.appLibraryOpen ? "close" : "open";
            root.libraryProgress = root.libraryGesture === "open" ? 0 : 1;
            return;
        }
        if (root.libraryGesture === "overview") {
            if (phase === "end" && progress >= 0.15) GlobalStates.overviewOpen = false;
            if (phase === "end" || phase === "cancel") root.libraryGesture = "";
            return;
        }
        if (root.libraryGesture === "") return;
        const opening = root.libraryGesture === "open";
        // A little past the end stretches instead of stopping dead
        const amount = progress <= 1 ? progress : 1 + (1 - 1 / (1 + (progress - 1) * 2)) * 0.12;
        if (phase === "update") {
            root.libraryProgress = opening ? amount : Math.max(0, 1 - amount);
            if (opening && !GlobalStates.appLibraryOpen && progress > 0.02) GlobalStates.appLibraryOpen = true;
            return;
        }
        // Ended: far enough to go through with it, or back where it was
        const done = phase === "end" && progress >= root.commitAt;
        GlobalStates.appLibraryOpen = opening ? done : !done;
        root.libraryGesture = "";
        root.libraryProgress = -1;
    }

    Timer {
        id: hintGone
        interval: 420
        onTriggered: root.hintAction = ""
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "custom" || !event.data.startsWith("gesture:")) return;
            const [, action, phase, progress] = event.data.split(":");
            root.handle(action, phase, Number(progress) || 0);
        }
    }
}
