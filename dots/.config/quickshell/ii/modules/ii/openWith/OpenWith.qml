pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions

/**
 * "How do you want to open this file?" — shown the first time a file type without an app is opened.
 * Files of such types open with folis-open-with.desktop, which runs `velora-helper apps open-with`;
 * that asks here through IPC with the file, its type and the apps that can open it.
 */
Scope {
    id: root

    readonly property string helper: Quickshell.shellPath("scripts/helper")
    property var queue: []
    readonly property var request: root.queue.length > 0 ? root.queue[0] : null

    function finish(app, remember) {
        const request = root.request;
        if (!request) return;
        if (app) {
            if (remember) Quickshell.execDetached([root.helper, "apps", "set-mime", app.id, ...request.types]);
            Quickshell.execDetached([root.helper, "apps", "open", app.id, ...request.uris]);
        }
        root.queue = root.queue.slice(1);
    }

    IpcHandler {
        target: "openWith"

        function ask(request: string): void {
            try {
                root.queue = [...root.queue, JSON.parse(request)];
            } catch (e) {
                console.warn("[OpenWith] Bad request:", e);
            }
        }
    }

    // Installs the chooser and hands it every file type that has no app yet (also ones from new apps)
    Process {
        running: true
        command: [root.helper, "apps", "sync"]
    }

    Loader {
        active: root.request !== null
        sourceComponent: PanelWindow {
            id: panelWindow
            // Only on the monitor in use
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            color: "transparent"
            WlrLayershell.namespace: "quickshell:openWith"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore

            OpenWithContent {
                anchors.fill: parent
                request: root.request
                onChosen: (app, remember) => root.finish(app, remember)
                onCanceled: root.finish(null, false)
            }
        }
    }
}
