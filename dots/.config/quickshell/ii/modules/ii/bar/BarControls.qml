import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// IPC target "bar" and the bar's global shortcuts, shared by the horizontal and vertical bars
Scope {
    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen
        }

        function close(): void {
            GlobalStates.barOpen = false
        }

        function open(): void {
            GlobalStates.barOpen = true
        }

        // Edit mode on the bar of the focused screen
        function edit(): void {
            GlobalStates.barEditScreen = Hyprland.focusedMonitor?.name ?? "";
            GlobalStates.barOpen = true;
            GlobalStates.barEditing = true;
        }

        function stopEditing(): void {
            GlobalStates.barEditing = false;
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barEditToggle"
        description: "Toggles editing of the bar layout"

        onPressed: {
            if (GlobalStates.barEditing) {
                GlobalStates.barEditing = false;
                return;
            }
            GlobalStates.barEditScreen = Hyprland.focusedMonitor?.name ?? "";
            GlobalStates.barOpen = true;
            GlobalStates.barEditing = true;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}
