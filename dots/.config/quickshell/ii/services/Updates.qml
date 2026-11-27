pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * System updates service. Currently only supports Arch.
 */
Singleton {
    id: root

    property bool veloraAvailable: false
    property bool hasUpdateState: false
    Timer {
        id: retryState
        interval: 2000
        repeat: true
        running: !root.hasUpdateState
        onTriggered: {
            updateState.reload();
            interval = Math.min(interval * 2, 60000);
        }
    }
    FileView {
        id: updateState
        path: `${Quickshell.env("XDG_STATE_HOME") || FileUtils.trimFileProtocol(Directories.home) + "/.local/state"}/velora/update.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.hasUpdateState = true;
            retryState.interval = 2000;
            try { const state = JSON.parse(text()); root.veloraAvailable = state.available === true; }
            catch (_) { root.veloraAvailable = false; }
        }
        onLoadFailed: { root.hasUpdateState = false; root.veloraAvailable = false; }
    }
    property bool available: false
    property alias checking: checkUpdatesProc.running
    property int count: 0
    
    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    function load() {}
    function refresh() {
        if (!available) return;
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }

    Timer {
        interval: Config.options.updates.checkInterval * 60 * 1000
        repeat: true
        running: Config.ready && Config.options.updates.enableCheck
        onTriggered: {
            print("[Updates] Periodic update check due")
            root.refresh();
        }
    }

    Process {
        id: checkAvailabilityProc
        running: Config.ready && Config.options.updates.enableCheck
        command: ["which", "checkupdates"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            root.refresh();
        }
    }

    Process {
        id: checkUpdatesProc
        command: ["bash", "-c", "checkupdates | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.count = parseInt(text.trim());
            }
        }
    }
}
