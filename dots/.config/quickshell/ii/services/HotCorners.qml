pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Screen corners that do something when the pointer reaches them (Config.options.hotCorners): what each one
 * can do, and running it. The corners themselves are drawn by modules/ii/screenCorners/ScreenCorners.qml.
 */
Singleton {
    id: root

    readonly property list<string> cornerNames: ["topLeft", "topRight", "bottomLeft", "bottomRight"]
    readonly property var actions: [
        { "value": "none", "displayName": Translation.tr("Nothing"), "icon": "block" },
        { "value": "sidebarLeft", "displayName": Translation.tr("Left sidebar"), "icon": "left_panel_open" },
        { "value": "sidebarRight", "displayName": Translation.tr("Right sidebar"), "icon": "right_panel_open" },
        { "value": "overview", "displayName": Translation.tr("Search and overview"), "icon": "search" },
        { "value": "wallpaperSelector", "displayName": Translation.tr("Wallpapers"), "icon": "wallpaper" },
        { "value": "session", "displayName": Translation.tr("Session menu"), "icon": "power_settings_new" },
        { "value": "lock", "displayName": Translation.tr("Lock the screen"), "icon": "lock" },
        { "value": "screenshot", "displayName": Translation.tr("Screenshot of an area"), "icon": "screenshot_region" },
        { "value": "doNotDisturb", "displayName": Translation.tr("Do not disturb"), "icon": "notifications_paused" },
        { "value": "powerSaving", "displayName": Translation.tr("Energy saving"), "icon": "energy_savings_leaf" },
        { "value": "nightLight", "displayName": Translation.tr("Night Light"), "icon": "bedtime" },
        { "value": "mediaPlayPause", "displayName": Translation.tr("Play or pause media"), "icon": "play_pause" },
        { "value": "command", "displayName": Translation.tr("Run a command"), "icon": "terminal" },
    ]

    function actionInfo(value) {
        return root.actions.find(action => action.value === value) ?? root.actions[0];
    }

    function run(action, command) {
        switch (action) {
        case "sidebarLeft": GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen; break;
        case "sidebarRight": GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen; break;
        case "overview": GlobalStates.overviewOpen = !GlobalStates.overviewOpen; break;
        case "wallpaperSelector": GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen; break;
        case "session": GlobalStates.sessionOpen = !GlobalStates.sessionOpen; break;
        case "lock": Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "lock", "activate"]); break;
        case "screenshot": Hyprland.dispatch(`hl.dsp.global("quickshell:regionScreenshot")`); break;
        case "doNotDisturb": Notifications.silent = !Notifications.silent; break;
        case "powerSaving": PowerSaving.toggle(); break;
        case "nightLight": Hyprsunset.toggleTemperature(); break;
        case "mediaPlayPause": MprisController.activePlayer?.togglePlaying(); break;
        case "command": if ((command ?? "").trim().length > 0) Quickshell.execDetached(["bash", "-c", command]); break;
        }
    }

    // ---- Main shell only: take over the old sidebar.cornerOpen settings once ----

    property bool loaded: false
    function load() {
        root.loaded = true;
        root.migrate();
    }
    Connections {
        target: Config
        enabled: root.loaded
        function onReadyChanged() { root.migrate() }
    }
    function migrate() {
        if (!root.loaded || !Config.ready || Config.options.hotCorners.version >= 1) return;
        const old = Config.options.sidebar.cornerOpen;
        const corners = Config.options.hotCorners;
        const used = old.bottom ? ["bottomLeft", "bottomRight"] : ["topLeft", "topRight"];
        const unused = old.bottom ? ["topLeft", "topRight"] : ["bottomLeft", "bottomRight"];
        corners[used[0]].action = old.enable ? "sidebarLeft" : "none";
        corners[used[1]].action = old.enable ? "sidebarRight" : "none";
        corners[unused[0]].action = "none";
        corners[unused[1]].action = "none";
        corners.trigger = (old.clickless || old.clicklessCornerEnd) ? "hover" : "click";
        corners.scroll = old.valueScroll;
        corners.version = 1;
    }
}
