pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string mode: ""
    property string pendingMode: ""
    property string requestedMode: ""
    property string lastError: ""
    property bool available: false
    property bool toggleAfterModeRefresh: false
    property int setModeCooldownMs: 30000
    property real lastSetModeRequestAt: 0

    readonly property bool busy: getModeProc.running || getPendingModeProc.running || setModeProc.running
    readonly property string effectiveMode: pendingMode.length > 0 ? pendingMode : mode
    readonly property bool integrated: effectiveMode === "Integrated"
    readonly property bool hybrid: effectiveMode === "Hybrid"
    readonly property string icon: integrated ? "memory" : hybrid ? "desktop_windows" : "question_mark"
    readonly property string statusText: busy ? "Checking…"
        : effectiveMode.length > 0 ? effectiveMode
        : lastError.length > 0 ? root.errorSummary(lastError)
        : "Unknown"

    function cleanOutput(text) {
        return (text || "").replace(/\x1b\[[0-9;]*m/g, "").trim();
    }

    function errorSummary(text) {
        const cleanText = root.cleanOutput(text);
        if (/timed out/i.test(cleanText))
            return "Daemon timeout";
        const firstLine = cleanText.split("\n")[0];
        return firstLine.length > 0 ? firstLine : "Unavailable";
    }

    function notifyError(action) {
        Quickshell.execDetached([
            "notify-send",
            "GPU mode",
            action + ": " + root.errorSummary(lastError),
            "-a",
            "Shell"
        ]);
    }

    function normalizedMode(text) {
        const cleanText = root.cleanOutput(text);
        if (/\bintegrated\b/i.test(cleanText))
            return "Integrated";
        if (/\bhybrid\b/i.test(cleanText))
            return "Hybrid";
        return "";
    }

    function setModeCooldownActive() {
        return lastSetModeRequestAt > 0 && Date.now() - lastSetModeRequestAt < setModeCooldownMs;
    }

    function refresh() {
        lastError = "";
        getModeProc.running = false;
        getPendingModeProc.running = false;
        getModeProc.command = ["timeout", "3s", "supergfxctl", "-g"];
        getPendingModeProc.command = ["timeout", "3s", "supergfxctl", "-P"];
        getModeProc.running = true;
        getPendingModeProc.running = true;
    }

    function setMode(nextMode) {
        if (setModeProc.running || root.setModeCooldownActive())
            return;

        requestedMode = nextMode;
        lastSetModeRequestAt = Date.now();
        lastError = "";
        setModeProc.command = ["timeout", "30s", "supergfxctl", "-m", nextMode];
        setModeProc.running = true;
    }

    function refreshModeForToggle() {
        toggleAfterModeRefresh = true;
        lastError = "";
        getModeProc.running = false;
        getModeProc.command = ["timeout", "3s", "supergfxctl", "-g"];
        getModeProc.running = true;
    }

    function toggle() {
        if (setModeProc.running || getModeProc.running)
            return;

        if (effectiveMode.length === 0) {
            root.refreshModeForToggle();
            return;
        }

        root.setMode(effectiveMode === "Integrated" ? "Hybrid" : "Integrated");
    }

    Component.onCompleted: root.refresh()

    Timer {
        id: refreshAfterSetTimer
        interval: 1000
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: logoutAfterSetTimer
        interval: 1200
        repeat: false
        onTriggered: Quickshell.execDetached(["pkill", "-i", "Hyprland"])
    }

    Process {
        id: getModeProc
        command: ["timeout", "3s", "supergfxctl", "-g"]
        stdout: StdioCollector {
            onStreamFinished: {
                const newMode = root.normalizedMode(text);
                if (newMode.length > 0) {
                    root.mode = newMode;
                    root.available = true;
                    root.lastError = "";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = root.cleanOutput(text);
                if (errorText.length > 0)
                    root.lastError = errorText;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                const toggleRequested = root.toggleAfterModeRefresh;
                root.available = false;
                root.toggleAfterModeRefresh = false;
                if (exitCode === 124)
                    root.lastError = "supergfxctl timed out";
                if (toggleRequested)
                    root.notifyError("Could not read the current mode");
                return;
            }

            if (root.toggleAfterModeRefresh) {
                root.toggleAfterModeRefresh = false;
                if (root.effectiveMode.length > 0) {
                    root.setMode(root.effectiveMode === "Integrated" ? "Hybrid" : "Integrated");
                } else {
                    root.available = false;
                    if (root.lastError.length === 0)
                        root.lastError = "Could not read graphics mode";
                }
            }
        }
    }

    Process {
        id: getPendingModeProc
        command: ["timeout", "3s", "supergfxctl", "-P"]
        stdout: StdioCollector {
            onStreamFinished: {
                const newPendingMode = root.normalizedMode(text);
                root.pendingMode = newPendingMode;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = root.cleanOutput(text);
                if (errorText.length > 0)
                    root.lastError = errorText;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 124)
                root.lastError = "supergfxctl timed out";
        }
    }

    Process {
        id: setModeProc
        stderr: StdioCollector {
            onStreamFinished: {
                const errorText = root.cleanOutput(text);
                if (errorText.length > 0)
                    root.lastError = errorText;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.available = true;
                root.pendingMode = root.requestedMode;
                root.mode = root.requestedMode;
                refreshAfterSetTimer.restart();
                logoutAfterSetTimer.restart();
            } else {
                root.available = false;
                if (exitCode === 124 && root.lastError.length === 0)
                    root.lastError = "supergfxctl timed out";
                root.lastSetModeRequestAt = 0;
                root.notifyError("Could not change the mode");
            }
            root.requestedMode = "";
        }
    }
}
