pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs

Scope {
    id: root
    property string output: ""
    signal showTarget(string outputName, rect bounds)

    function clear() {
        output = "";
        showTarget("", Qt.rect(0, 0, 0, 0));
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" || (event.name === "monitorremoved" && event.data === root.output)) {
                root.clear();
                return;
            }
            const prefix = "velora-snap-preview:";
            if (event.name !== "custom" || !event.data.startsWith(prefix)) return;
            const fields = event.data.slice(prefix.length).split(",");
            const [width, height, x, y, w, h] = fields.slice(1).map(Number);
            if (GlobalStates.screenLocked || fields.length !== 7 || !fields[0] || ![width, height, x, y, w, h].every(Number.isFinite)
                    || width <= 0 || height <= 0 || w <= 0 || h <= 0) {
                root.clear();
                return;
            }
            // Fractions keep Qt and the compositor aligned even with a separate shell scale.
            root.output = fields[0];
            root.showTarget(root.output, Qt.rect(x / width, y / height, w / width, h / height));
        }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (GlobalStates.screenLocked) root.clear(); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: overlay
            required property ShellScreen modelData
            screen: modelData
            visible: !GlobalStates.screenLocked && (highlight.requested || highlight.opacity > 0)
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:windowSnapPreview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
            anchors { top: true; bottom: true; left: true; right: true }

            Connections {
                target: root
                function onShowTarget(outputName, bounds) {
                    if (outputName === overlay.modelData.name) {
                        highlight.show(bounds);
                    } else {
                        highlight.requested = false;
                    }
                }
            }
            WindowSnapHighlight { id: highlight }
        }
    }
}
