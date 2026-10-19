pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Runs the commands of "custom command" bar widgets on their intervals and keeps the output.
 * Widgets with the same command and interval share one runner, so a bar per screen doesn't
 * multiply processes.
 */
Singleton {
    id: root

    property var outputs: ({}) // key → last output, trimmed
    property var entries: ({}) // key → { runner, users }

    function keyFor(command, interval) {
        return `${interval}|${command}`;
    }

    function subscribe(command, interval) {
        if (!command || command.trim().length === 0) return "";
        const seconds = Math.max(1, Math.round(interval));
        const key = root.keyFor(command, seconds);
        const entry = root.entries[key];
        if (entry) {
            entry.users += 1;
            return key;
        }
        root.entries[key] = {
            "runner": runnerComponent.createObject(root, { "command": command, "seconds": seconds, "key": key }),
            "users": 1
        };
        return key;
    }

    function unsubscribe(key) {
        const entry = root.entries[key];
        if (!entry) return;
        entry.users -= 1;
        if (entry.users > 0) return;
        entry.runner.destroy();
        delete root.entries[key];
    }

    function refresh(key) {
        root.entries[key]?.runner.run();
    }

    function runDetached(command) {
        if (command && command.trim().length > 0) Quickshell.execDetached(["bash", "-c", command]);
    }

    Component {
        id: runnerComponent
        QtObject {
            id: runner
            required property string command
            required property int seconds
            required property string key

            function run() {
                if (!process.running) process.running = true;
            }

            property Process process: Process {
                command: ["bash", "-c", runner.command]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let outputs = Object.assign({}, root.outputs);
                        outputs[runner.key] = text.trim();
                        root.outputs = outputs;
                    }
                }
            }

            property Timer timer: Timer {
                interval: runner.seconds * 1000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: runner.run()
            }
        }
    }
}
