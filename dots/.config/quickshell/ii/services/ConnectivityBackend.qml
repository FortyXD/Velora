pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The link to velora-connectivityd, which does the talking to NetworkManager and BlueZ. It takes requests
 * as JSON lines and publishes state the same way, and this keeps it running: `network` and `bluetooth`
 * always hold the latest state, and `call` sends a request and hands its outcome to a callback.
 * Passwords only ever go through `call`, and so through the daemon's stdin.
 */
Singleton {
    id: root

    // What this shell expects; a daemon left over from another version isn't spoken to
    readonly property int protocolVersion: 1

    // The running shell answers password and pairing requests; the settings app doesn't
    property bool agents: false
    // Empty when all is well, or "missing" (not installed), "version" (needs rebuilding), "crashed"
    property string problem: ""
    property bool ready: false
    property bool agentsActive: false
    property var network: ({})
    property var bluetooth: ({})

    // Something the daemon wants known outside of a request: a prompt to answer, a transfer's progress
    signal event(string name, var data)

    property int nextRequestId: 1
    property var pending: ({})
    property int failures: 0
    property real startedAt: 0

    /** Sends a request. `done` gets the result or, on failure, `{ code, message }` as its second argument. */
    function call(method: string, params: var, done: var): void {
        if (!daemon.running || !root.ready) {
            if (done) done(null, { code: "unavailable", message: "The connection service is not running" });
            return;
        }
        const id = root.nextRequestId++;
        if (done) root.pending[id] = done;
        daemon.write(JSON.stringify({ id, method, params: params ?? {} }) + "\n");
    }

    function failPending(): void {
        const waiting = root.pending;
        root.pending = ({});
        for (const id in waiting)
            waiting[id](null, { code: "unavailable", message: "The connection service stopped" });
    }

    function handleLine(line: string): void {
        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            return;
        }
        if (message.type === "hello") {
            if (message.protocol !== root.protocolVersion) {
                root.problem = "version";
                daemon.running = false;
                return;
            }
            root.problem = "";
            root.ready = true;
            root.agentsActive = message.agents === true;
        } else if (message.type === "snapshot") {
            if (message.domain === "network") root.network = message.data;
            else if (message.domain === "bluetooth") root.bluetooth = message.data;
        } else if (message.type === "response") {
            const done = root.pending[message.id];
            delete root.pending[message.id];
            if (done) done(message.ok ? (message.result ?? null) : null, message.ok ? null : message.error);
        } else if (message.type === "event") {
            root.event(message.name, message.data);
        }
    }

    /** Opens the settings app on one of its pages, from the bar and the sidebars. */
    function openSettings(page: string): void {
        Quickshell.execDetached(["env", `QS_SETTINGS_PAGE=${page}`, "QS_SETTINGS_SECTION=", "QS_SETTINGS_SEARCH=", "qs", "-p", Quickshell.shellPath("settings.qml")]);
    }

    function start(): void {
        root.startedAt = Date.now();
        daemon.running = true;
    }

    // Asked to stop in order to come back with another setting, which isn't a crash
    property bool restarting: false
    onAgentsChanged: {
        if (!daemon.running) return;
        root.restarting = true;
        daemon.running = false;
    }

    Component.onCompleted: Qt.callLater(root.start)

    Process {
        id: daemon
        stdinEnabled: true
        command: ["sh", "-c", 'exec "${VELORA_CONNECTIVITYD:-$(command -v velora-connectivityd || echo "$HOME/.local/bin/velora-connectivityd")}" "$@"',
            "velora-connectivityd", ...(root.agents ? ["--agents"] : [])]
        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }
        onExited: (exitCode, exitStatus) => {
            root.ready = false;
            root.agentsActive = false;
            root.failPending();
            if (root.restarting) {
                root.restarting = false;
                root.start();
                return;
            }
            // A version mismatch clears up once an update finishes building it, so it is tried again too
            if (root.problem !== "version") {
                if (exitCode === 127 || exitCode === 126) root.problem = "missing";
                else if (exitCode !== 0) root.problem = "crashed";
            }
            root.failures = Date.now() - root.startedAt > 30000 ? 1 : root.failures + 1;
            restartTimer.interval = Math.min(30000, 1000 * Math.pow(2, root.failures - 1));
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        onTriggered: root.start()
    }
}
