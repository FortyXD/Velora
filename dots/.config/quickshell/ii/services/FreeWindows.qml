pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Actions on windows done in Hyprland (hyprland/modes/floating.lua for free windows, and
 * hyprland/window_actions.lua), so the keyboard, gestures, the taskbar, snap layouts and the window
 * menu all behave the same.
 * `address` is Hyprland's "0x…"; empty means the active window.
 */
Singleton {
    id: root
    readonly property bool enabled: HyprlandSettings.windowMode === "floating"

    // Zones of snap layouts, as hyprland/modes/floating.lua names them
    readonly property var layouts: [
        [["left", 0, 0, 0.5, 1], ["right", 0.5, 0, 0.5, 1]],
        [["left-two-thirds", 0, 0, 2 / 3, 1], ["right-third", 2 / 3, 0, 1 / 3, 1]],
        [["left-third", 0, 0, 1 / 3, 1], ["middle-third", 1 / 3, 0, 1 / 3, 1], ["right-third", 2 / 3, 0, 1 / 3, 1]],
        [["left", 0, 0, 0.5, 1], ["top-right", 0.5, 0, 0.5, 0.5], ["bottom-right", 0.5, 0.5, 0.5, 0.5]],
        [["top-left", 0, 0, 0.5, 0.5], ["top-right", 0.5, 0, 0.5, 0.5], ["bottom-left", 0, 0.5, 0.5, 0.5], ["bottom-right", 0.5, 0.5, 0.5, 0.5]],
    ]

    // Snapping needs the free windows mode; minimizing, restoring and the desktop work in both
    function call(name, ...args) {
        const module = ["minimize", "restore", "show_desktop"].includes(name) ? "hyprland.window_actions" : "hyprland.modes.floating";
        const list = args.map(value => `"${String(value).replace(/[^0-9A-Za-z_-]/g, "")}"`).join(", ");
        Quickshell.execDetached(["hyprctl", "eval", `require("${module}").${name}(${list})`]);
    }

    function snap(zone, address = "") {
        if (address) root.call("snap", zone, address);
        else root.call("snap", zone);
    }
    function minimize(address = "") {
        if (address) root.call("minimize", address);
        else root.call("minimize");
    }
    function restore(address) {
        root.call("restore", address);
    }
    function toggleMaximize(address = "") {
        if (address) root.call("toggle_maximize", address);
        else root.call("toggle_maximize");
    }
    function showDesktop() {
        root.call("show_desktop");
    }
}
