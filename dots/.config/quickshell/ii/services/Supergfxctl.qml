pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string mode: ""
    property string pendingMode: ""
    property string powerState: "unknown"
    property bool hasModeService: true
    property bool modeChecked: false
    property string requestedMode: ""
    property string lastError: ""
    property bool available: false
    property bool toggleAfterModeRefresh: false
    property int setModeCooldownMs: 30000
    property real lastSetModeRequestAt: 0

    readonly property bool busy: getModeProc.running || getPendingModeProc.running || setModeProc.running
    readonly property string effectiveMode: mode
    readonly property bool integrated: effectiveMode === "Integrated"
    readonly property bool hybrid: effectiveMode === "Hybrid"
    readonly property string icon: integrated ? "memory" : hybrid ? "desktop_windows" : "question_mark"
    readonly property string statusText: !modeChecked ? "Checking…"
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
        return ["AsusMuxDgpu", "Vfio", "AsusEgpu"].find(mode => cleanText.toLowerCase() === mode.toLowerCase()) ?? "";
    }

    function setModeCooldownActive() {
        return lastSetModeRequestAt > 0 && Date.now() - lastSetModeRequestAt < setModeCooldownMs;
    }

    function refresh() {
        if (!getModeProc.running) {
            lastModeProbe = Date.now();
            getModeProc.running = true;
        }
        if (!getPendingModeProc.running) getPendingModeProc.running = true;
        if (!powerProbe.running) powerProbe.running = true;
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

    function toggle() {
        if (setModeProc.running || root.setModeCooldownActive())
            return;
        root.toggleAfterModeRefresh = true;
        if (!getModeProc.running) getModeProc.running = true;
    }

    Component.onCompleted: root.refresh()

    Process {
        id: powerProbe
        command: ["timeout", "3s", "supergfxctl", "-S"]
        stdout: StdioCollector {
            onStreamFinished: {
                const status = root.cleanOutput(text).toLowerCase();
                root.powerState = ["active", "suspended", "off", "disabled", "asleep", "d3cold"].includes(status) ? status : "unknown";
            }
        }
        onExited: code => { if (code !== 0) root.powerState = "unknown"; }
    }
    property double lastModeProbe: 0
    function refreshPower() {
        if (!busy && Date.now() - lastModeProbe >= 30000) refresh();
        else if (!powerProbe.running) powerProbe.running = true;
    }

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
        stdout: StdioCollector { id: modeOutput }
        stderr: StdioCollector { id: modeError }
        onExited: (exitCode, exitStatus) => {
            const toggleRequested = root.toggleAfterModeRefresh;
            root.toggleAfterModeRefresh = false;
            root.hasModeService = exitCode !== 127;
            root.mode = exitCode === 0 ? root.normalizedMode(modeOutput.text) : "";
            root.available = root.mode.length > 0;
            root.modeChecked = true;
            if (!root.available) {
                root.lastError = exitCode === 124 ? "supergfxctl timed out"
                    : root.cleanOutput(modeError.text) || "Could not read graphics mode";
                if (toggleRequested)
                    root.notifyError("Could not read the current mode");
                return;
            }
            root.lastError = "";
            if (toggleRequested) root.setMode(root.integrated ? "Hybrid" : "Integrated");
        }
    }

    Process {
        id: getPendingModeProc
        command: ["timeout", "3s", "supergfxctl", "-P"]
        stdout: StdioCollector { id: pendingOutput }
        onExited: code => root.pendingMode = code === 0 ? root.normalizedMode(pendingOutput.text) : ""
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
