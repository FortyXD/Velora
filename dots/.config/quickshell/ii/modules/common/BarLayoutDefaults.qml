pragma Singleton
import Quickshell

/**
 * Built-in bar layouts, used while `bar.layout` / `bar.verticalLayout` are null.
 * Zones run in visual order: start (left/top) → centerStart → center → centerEnd → end (right/bottom).
 * Items: { uid, type, pill?, pillBreak?, hideAt?, fill?, options? } — see BarWidgetCatalog for types.
 */
Singleton {
    id: root

    readonly property list<string> zoneNames: ["start", "centerStart", "center", "centerEnd", "end"]

    readonly property var horizontal: ({
        "version": 1,
        "balanceCenter": true,
        "actions": {
            "start": { "click": "sidebarLeft", "scroll": "brightness" },
            "centerEnd": { "click": "sidebarRight" },
            "end": { "click": "sidebarRight", "scroll": "volume" }
        },
        "zones": {
            "start": [
                { "uid": "lsb", "type": "leftSidebarButton" },
                { "uid": "aw", "type": "activeWindow", "hideAt": 1 }
            ],
            "centerStart": [
                { "uid": "res", "type": "resources", "pill": true },
                { "uid": "isl", "type": "island", "pill": true, "hideAt": 2 }
            ],
            "center": [
                { "uid": "ws", "type": "workspaces", "pill": true }
            ],
            "centerEnd": [
                { "uid": "clk", "type": "clock", "pill": true, "fill": true },
                { "uid": "ub", "type": "utilButtons", "pill": true, "hideAt": 1 },
                { "uid": "bat", "type": "battery", "pill": true, "hideAt": 2 }
            ],
            "end": [
                { "uid": "wx", "type": "weather", "pill": true },
                { "uid": "sp", "type": "spacer" },
                { "uid": "tray", "type": "sysTray", "hideAt": 1 },
                { "uid": "prv", "type": "privacy" },
                { "uid": "st", "type": "statusIndicators" }
            ]
        }
    })

    readonly property var vertical: ({
        "version": 1,
        "balanceCenter": false,
        "actions": {
            "start": { "click": "sidebarLeft", "scroll": "brightness" },
            "end": { "click": "sidebarRight", "scroll": "volume" }
        },
        "zones": {
            "start": [
                { "uid": "lsb", "type": "leftSidebarButton" }
            ],
            "centerStart": [
                { "uid": "res", "type": "resources", "pill": true },
                { "uid": "med", "type": "media", "pill": true }
            ],
            "center": [
                { "uid": "ws", "type": "workspaces", "pill": true }
            ],
            "centerEnd": [
                { "uid": "clk", "type": "clock", "pill": true },
                { "uid": "bat", "type": "battery", "pill": true }
            ],
            "end": [
                { "uid": "sp", "type": "spacer" },
                { "uid": "tray", "type": "sysTray" },
                { "uid": "st", "type": "statusIndicators" }
            ]
        }
    })
}
