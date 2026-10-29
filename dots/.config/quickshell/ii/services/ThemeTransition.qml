pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

// One captured scene per screen. Presets prepare everything they can before the capture, retain
// the picture only while their files and layout are put in place, then reveal the complete scene
// in one wave from the pointer, across every screen.
Singleton {
    id: root
    property int overlays: 0
    property bool captureInhibited: false
    readonly property bool available: root.overlays > 0 && Appearance.animationSpeed > 0 && !root.captureInhibited
    property string phase: "idle"
    property int generation: 0
    property var capturedScreens: []
    property var changes: []
    property var holds: []
    property int nextToken: 0
    property bool presetTransition: false
    property point origin: Qt.point(-1, -1) // Global; where the pointer is when the wave starts
    readonly property int revealDuration: Appearance.scaledDuration(root.presetTransition ? 850 : 700)
    // QS_DEBUG_TRANSITION=1: how long the screen stood still, in the log
    property bool debug: false
    property real capturedAt: 0

    signal captureRequested(int generation)
    signal revealRequested(int generation)

    function prepare() {
        if (!root.available) return;
        if (root.phase === "capturing" || root.phase === "holding") return;
        settleTimer.stop();
        revealEnd.stop();
        root.generation++;
        root.phase = "capturing";
        root.capturedScreens = [];
        root.origin = Qt.point(-1, -1);
        cursorProc.running = true;
        root.captureRequested(root.generation);
        captureLimit.restart();
        holdLimit.restart();
    }

    // A retained change gets a token: release it once its asynchronous work is ready.
    function run(change, retain = false) {
        if (!root.available) {
            change(0);
            return 0;
        }
        const token = retain ? ++root.nextToken : 0;
        if (token) {
            root.holds = root.holds.concat([token]);
            root.presetTransition = true;
        }
        settleTimer.stop();
        root.changes.push({ change: change, token: token });
        if (root.phase === "holding") root.applyChanges();
        else if (root.phase !== "capturing") root.prepare();
        holdLimit.restart();
        return token;
    }

    function release(token) {
        if (!token || !root.holds.includes(token)) return;
        root.holds = root.holds.filter(held => held !== token);
        root.maybeReveal();
    }

    function reportCaptured(generation, screenName) {
        if (generation !== root.generation || root.phase !== "capturing" || root.capturedScreens.includes(screenName)) return;
        root.capturedScreens = root.capturedScreens.concat([screenName]);
        if (root.capturedScreens.length >= root.overlays) root.hold();
    }

    function hold() {
        if (root.phase !== "capturing") return;
        captureLimit.stop();
        root.phase = "holding";
        root.capturedAt = Date.now();
        root.applyChanges();
    }

    function applyChanges() {
        const changes = root.changes;
        root.changes = [];
        for (const entry of changes) {
            try {
                entry.change(entry.token);
            } catch (error) {
                console.warn("[ThemeTransition] A change failed:", error);
                root.release(entry.token);
            }
        }
        root.maybeReveal();
    }

    function maybeReveal() {
        if (root.phase !== "holding" || root.holds.length > 0 || root.changes.length > 0) return;
        // The pointer may have moved while the scene was held: the wave starts where it is now
        cursorProc.running = false;
        cursorProc.running = true;
        settleTimer.restart();
    }

    function reveal() {
        if (root.phase !== "holding" || root.holds.length > 0) return;
        settleTimer.stop();
        holdLimit.stop();
        if (root.debug) console.info(`[ThemeTransition] The screen stood still for ${Date.now() - root.capturedAt} ms`);
        root.phase = "revealing";
        root.revealRequested(root.generation);
        revealEnd.restart();
    }

    Timer {
        id: settleTimer
        interval: 64 // A few frames, so the new scene reaches the compositor before it's uncovered
        onTriggered: root.reveal()
    }
    Timer {
        id: captureLimit
        interval: 350
        onTriggered: root.hold()
    }
    Timer { // A failed subprocess must never leave a frozen picture on screen.
        id: holdLimit
        interval: 10000
        onTriggered: {
            root.holds = [];
            root.maybeReveal();
        }
    }
    Timer {
        id: revealEnd
        interval: root.revealDuration
        onTriggered: {
            root.phase = "idle";
            root.presetTransition = false;
        }
    }

    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const position = JSON.parse(text);
                    root.origin = Qt.point(position.x, position.y);
                } catch (error) {
                    root.origin = Qt.point(-1, -1);
                }
            }
        }
    }
}
