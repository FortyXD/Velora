pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

/** Only shell.qml owns the collector. Settings and popups just read its small snapshot. */
Singleton {
    id: root
    property bool loaded: false
    readonly property bool enabled: Config.ready && Config.options.battery.advancedAnalytics
    readonly property string stateDirectory: `${FileUtils.trimFileProtocol(Directories.state)}/user/power-analytics`
    readonly property string scriptPath: Quickshell.shellPath("scripts/power/analytics.py")
    property var latest: null
    property string error: ""
    property real clock: Date.now() / 1000
    property bool erasePending: false
    readonly property bool fresh: enabled && !erasePending && latest !== null && clock - latest.timestamp < 8 && clock >= latest.timestamp - 2
    readonly property bool hasLivePower: fresh && latest.battery_power_w !== null && isFinite(latest.battery_power_w)

    function load() {
        root.loaded = true;
        if (Config.ready && !root.enabled) root.erasePending = true;
        root.reconcile();
    }
    function reconcile() {
        if (!root.loaded || !Config.ready || eraser.running) return;
        if (collector.running) {
            if (!root.enabled || root.erasePending) collector.running = false;
            return; // Wait for onExited before deleting files or starting again.
        }
        if (root.erasePending) {
            eraser.running = true;
        } else if (root.enabled) {
            root.error = "";
            collector.running = true;
        }
    }
    onEnabledChanged: {
        retry.stop();
        root.latest = null;
        if (root.loaded && Config.ready && !root.enabled) root.erasePending = true;
        if (root.enabled) snapshot.reload();
        root.reconcile();
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (root.loaded && Config.ready && !root.enabled) root.erasePending = true;
            root.reconcile();
        }
    }
    Process {
        id: collector
        command: ["python3", root.scriptPath, "collect", "--state-dir", root.stateDirectory]
        stderr: SplitParser { onRead: data => root.error = data.slice(0, 400) }
        onExited: (exitCode, exitStatus) => {
            if (!root.enabled) root.erasePending = true;
            if (root.erasePending) root.reconcile();
            else if (root.enabled) {
                root.error = Translation.tr("Power sampling stopped. Retrying…");
                retry.restart();
            }
        }
    }
    Process {
        id: eraser
        command: ["python3", root.scriptPath, "clear", "--state-dir", root.stateDirectory]
        stderr: SplitParser { onRead: data => root.error = data.slice(0, 400) }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.erasePending = false;
                root.error = "";
                root.reconcile(); // Handles a quick off → on while cleanup was running.
            } else {
                root.error = Translation.tr("Could not delete power history. Turn analytics on and off to retry.");
            }
        }
    }
    Timer {
        id: retry
        interval: 2000
        onTriggered: root.reconcile()
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.enabled
        triggeredOnStart: true
        onTriggered: {
            root.clock = Date.now() / 1000;
            // A watcher cannot track a file before the collector creates its directory.
            snapshot.reload();
        }
    }
    FileView {
        id: snapshot
        path: root.enabled ? `${root.stateDirectory}/latest.json` : ""
        watchChanges: root.enabled
        onFileChanged: reload()
        onLoaded: {
            if (!root.enabled) return;
            try {
                const sample = JSON.parse(snapshot.text());
                if (!sample || !isFinite(sample.timestamp)) return;
                root.clock = Date.now() / 1000;
                root.latest = sample;
                root.error = sample.error ?? "";
            } catch (e) {
                root.error = Translation.tr("Could not read the power sample.");
            }
        }
        onLoadFailed: error => root.latest = null
    }
}
