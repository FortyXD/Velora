pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string compositorVersion: ""
    // Keep capture off until the compositor is identified. Hyprland 0.57.0's
    // legacy toplevel-export path can leave a frame object unregistered when
    // its window closes. A later request then kills the entire Wayland client.
    // https://github.com/hyprwm/Hyprland/blob/v0.57.0/src/protocols/ToplevelExport.cpp
    // Related capture regression: quickshell-mirror/quickshell#1418.
    readonly property bool allowed: compositorVersion !== "" && compositorVersion !== "0.57.0"

    function readVersion(text) {
        try {
            const info = JSON.parse(text);
            const version = String(info.version ?? info.tag ?? "").replace(/^v/, "");
            compositorVersion = /^\d+\.\d+\.\d+$/.test(version) ? version : "";
        } catch (_) {
            compositorVersion = "";
        }
    }

    Process {
        id: probe
        running: true
        command: ["hyprctl", "-j", "version"]
        stdout: StdioCollector { onStreamFinished: root.readVersion(text) }
        onExited: (code, status) => { if (code !== 0) root.compositorVersion = ""; }
    }
    Timer {
        interval: 3000
        running: probe.running
        onTriggered: { probe.running = false; root.compositorVersion = ""; }
    }
}
