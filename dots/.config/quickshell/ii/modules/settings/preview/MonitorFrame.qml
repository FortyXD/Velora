import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

// ShellScreen dimensions are logical pixels and already include output rotation and fractional scaling.
Item {
    id: root
    readonly property var output: Quickshell.screens.find(s => s.name === root.Window.window?.screen?.name)
        ?? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
    readonly property real logicalWidth: output?.width || Screen.width || 1920
    readonly property real logicalHeight: output?.height || Screen.height || 1080
    readonly property real aspect: logicalWidth / logicalHeight
    implicitHeight: width / aspect
    Layout.fillWidth: true
    Layout.maximumWidth: Math.max(240, (root.Window.window?.height || 850) * 0.62) * aspect
    Layout.alignment: Qt.AlignHCenter
    clip: true
}
