pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
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
    property bool saving: false
    property var pendingApp: null
    property string saveError: ""
    readonly property var request: root.queue.length > 0 ? root.queue[0] : null

    function finish(app, remember) {
        if (root.saving) return;
        const request = root.request;
        if (!request) return;
        root.saveError = "";
        if (app && remember) {
            root.pendingApp = app;
            root.saving = true;
            rememberProc.command = [root.helper, "apps", "set-mime", app.id, ...request.types];
            rememberProc.running = true;
            return;
        }
        root.complete(app, false);
    }

    function complete(app, remembered) {
        const request = root.request;
        let remaining = root.queue.slice(1);
        if (app) {
            let uris = [...request.uris];
            if (remembered) {
                remaining = remaining.filter(next => {
                    if (!next.types.every(type => request.types.includes(type))) return true;
                    uris.push(...next.uris);
                    return false;
                });
            }
            Quickshell.execDetached([root.helper, "apps", "open", app.id, ...new Set(uris)]);
        }
        root.queue = remaining;
        root.pendingApp = null;
    }

    Process {
        id: rememberProc
        onExited: (exitCode, exitStatus) => {
            root.saving = false;
            if (exitCode !== 0 || exitStatus !== 0) {
                root.saveError = Translation.tr("Could not save the default app. Try again or turn off “Always use this app”.");
                return;
            }
            root.complete(root.pendingApp, true);
        }
    }

    IpcHandler {
        target: "openWith"

        function ask(request: string): void {
            try {
                const incoming = JSON.parse(request);
                const key = [...incoming.uris].sort().join("\u0000");
                if (!root.queue.some(item => [...item.uris].sort().join("\u0000") === key))
                    root.queue = [...root.queue, incoming];
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
                busy: root.saving
                errorText: root.saveError
                onChosen: (app, remember) => root.finish(app, remember)
                onCanceled: root.finish(null, false)
            }
        }
    }
}
