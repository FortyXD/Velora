import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Runs one command of scripts/toolbox/folis_toolbox.py and reports its JSON events.
 * Stopping it (cancel) sends SIGTERM; the script then stops its own child tools.
 */
Process {
    id: root

    signal event(var data)
    signal finishedAll()

    readonly property string script: Quickshell.shellPath("scripts/toolbox/folis_toolbox.py")

    function start(args) {
        root.running = false;
        root.command = ["/usr/bin/python3", "-I", root.script, ...args];
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
