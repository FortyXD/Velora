pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs.modules.common

/** Hands the daemon the settings it acts on by itself, in the running shell: login state and receiving files. */
Singleton {
    id: root

    readonly property string receiveFolder: {
        const chosen = Config.options.connectivity?.bluetoothReceiveFolder ?? "";
        return chosen.length > 0 ? chosen : `${Directories.home}/Downloads`;
    }
    readonly property var wanted: ({
        onLogin: Config.options.connectivity?.bluetoothOnLogin ?? "remember",
        receivePolicy: Config.options.connectivity?.bluetoothReceivePolicy ?? "ask",
        receiveFolder: root.receiveFolder,
    })

    function send(): void {
        if (ConnectivityBackend.ready && Config.ready) ConnectivityBackend.call("bluetooth.configure", root.wanted, null);
    }

    onWantedChanged: root.send()
    Connections {
        target: ConnectivityBackend
        function onReadyChanged() {
            root.send();
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.send();
        }
    }
}
