pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Screen recording state. record.sh reports start and stop over IPC,
 * and a wf-recorder process check covers shell reloads and crashed scripts.
 */
Singleton {
    id: root

    property bool recording: false
    property real startedAt: 0 // ms since epoch

    function toggle() {
        Quickshell.execDetached([Directories.recordScriptPath]);
    }

    function markStarted(elapsedSeconds = 0) {
        if (root.recording) return;
        root.startedAt = Date.now() - elapsedSeconds * 1000;
        root.recording = true;
    }

    function markStopped() {
        root.recording = false;
    }

    IpcHandler {
        target: "recorder"

        function started(): void {
            root.markStarted();
        }
        function stopped(): void {
            root.markStopped();
        }
    }

    // Prints how long wf-recorder has been running, fails when it isn't
    Process {
        id: processCheck
        command: ["ps", "-o", "etimes=", "-C", "wf-recorder"]
        stdout: StdioCollector {
            id: processCheckOutput
        }
        onExited: exitCode => {
            if (exitCode === 0) root.markStarted(parseInt(processCheckOutput.text.trim().split("\n")[0]) || 0);
            else root.markStopped();
        }
    }

    Component.onCompleted: processCheck.running = true

    Timer {
        interval: 10000
        running: root.recording
        repeat: true
        onTriggered: processCheck.running = true
    }
}
