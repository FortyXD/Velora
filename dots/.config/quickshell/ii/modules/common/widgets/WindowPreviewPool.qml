pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Wayland
import qs

QtObject {
    property bool active: false
    property var current: []
    readonly property var windows: active && !GlobalStates.screenLocked
        ? current.filter(window => window && ToplevelManager.toplevels.values.includes(window)) : []
}
