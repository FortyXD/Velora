pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

/**
 * Actions on windows done in Hyprland (hyprland/modes/floating.lua for free windows, and
 * hyprland/window_actions.lua), so the keyboard, gestures, the taskbar, snap layouts and the window
 * menu all behave the same.
 * `address` is Hyprland's "0x…"; empty means the active window.
 */
Singleton {
    id: root
    readonly property bool enabled: HyprlandSettings.windowMode !== "tiling"

    property bool nativeAvailable: false
    function checkNative() {
        if (enabled) probeDelay.restart();
        else nativeAvailable = false;
    }
    Component.onCompleted: checkNative()
    onEnabledChanged: checkNative()
    Timer {
        id: probeDelay
        interval: 180
        onTriggered: if (root.enabled) probe.running = true
    }
    Process {
        id: probe
        command: ["hyprctl", "repl", "return hl.plugin.velora ~= nil"]
        stdout: StdioCollector {
            onStreamFinished: root.nativeAvailable = root.enabled && text.trim() === "true"
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") root.checkNative();
        }
    }

    function addressOf(toplevel) {
        const raw = String(toplevel?.HyprlandToplevel?.address ?? "").replace(/^0x/, "");
        return /^[a-fA-F0-9]+$/.test(raw) ? "0x" + raw : "";
    }
    function minimized(name) {
        return name === "special:minimized" || (name ?? "").startsWith("special:velora-min-");
    }
    function desktopHidden(name) {
        return name === "special:desktop" || (name ?? "").startsWith("special:velora-desktop-");
    }
    function workspaceOf(toplevel) {
        return HyprlandData.windowByAddress[addressOf(toplevel)]?.workspace?.name ?? "";
    }
    function activateToplevel(toplevel, toggle = false) {
        if (!toplevel) return;
        const address = addressOf(toplevel);
        if (!address) { toplevel.activate(); return; }
        if (toggle && enabled && toplevel.activated) minimize(address);
        else restore(address);
    }
    function caption(address, mode) {
        if (/^0x[0-9a-f]+$/i.test(address) && ["auto", "on", "off"].includes(mode))
            Quickshell.execDetached(["hyprctl", "eval", 'if hl.plugin.velora then hl.plugin.velora.caption("' + address + '","' + mode + '") end']);
    }
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
        const module = ["minimize", "restore", "show_desktop", "toggle_maximize"].includes(name) ? "hyprland.window_actions" : "hyprland.modes.floating";
        const list = args.map(value => `"${String(value).replace(/[^0-9A-Za-z_-]/g, "")}"`).join(", ");
        Quickshell.execDetached(["hyprctl", "eval", `require("${module}").${name}(${list})`]);
    }

    function snap(zone, address = "") {
        if (!enabled) return;
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
