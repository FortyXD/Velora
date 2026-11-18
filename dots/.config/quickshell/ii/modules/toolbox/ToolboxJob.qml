import QtQuick
import Quickshell
import Quickshell.Io

// The native helper streams JSON events and owns the external tools for this job.
Process {
    id: root

    signal event(var data)
    signal finishedAll()

    function start(args) {
        root.running = false;
        root.command = [Quickshell.shellPath("scripts/helper"), "toolbox", ...args];
        root.running = true;
    }

    function cancel() {
        root.running = false;
    }

    stdout: SplitParser {
        onRead: line => {
            try {
                root.event(JSON.parse(line));
            } catch (e) {
                // Not an event line
            }
        }
    }
    onExited: root.finishedAll()
}
