pragma Singleton
import Quickshell
import qs.services

/**
 * What can be placed on the bar. Shared by the shell and the settings app, so it only holds
 * metadata; the components themselves live in modules/ii/bar/layout/BarWidgetFactory.qml.
 *
 * elastic:     takes the free space of its zone, and is left out when the center is balanced
 * fillHeight:  stretches across the bar's thickness
 * pillPadding: padding of a pill that holds only this widget
 * vertical:    has a variant for the vertical bar
 */
Singleton {
    id: root

    readonly property var categories: [
        { "id": "system", "name": Translation.tr("System"), "icon": "settings_applications" },
        { "id": "media", "name": Translation.tr("Media & activities"), "icon": "music_note" },
        { "id": "time", "name": Translation.tr("Time & weather"), "icon": "schedule" },
        { "id": "buttons", "name": Translation.tr("Buttons"), "icon": "touch_app" },
        { "id": "builder", "name": Translation.tr("Building blocks"), "icon": "widgets" },
    ]

    readonly property var widgets: ({
        "leftSidebarButton": {
            "name": Translation.tr("Left sidebar button"),
            "description": Translation.tr("Opens the AI, translator and image sidebar"),
            "icon": "spark", "category": "system", "vertical": true
        },
        "activeWindow": {
            "name": Translation.tr("Active window"),
            "description": Translation.tr("Icon, app and title of the focused window"),
            "icon": "web_asset", "category": "system", "elastic": true, "fillHeight": true, "vertical": false
        },
        "workspaces": {
            "name": Translation.tr("Workspaces"),
            "description": Translation.tr("Workspace switcher with app icons and previews"),
            "icon": "workspaces", "category": "system", "fillHeight": true, "pillPadding": 4, "vertical": true
        },
        "resources": {
            "name": Translation.tr("Resources"),
            "description": Translation.tr("Memory, swap and CPU usage"),
            "icon": "memory", "category": "system", "vertical": true
        },
        "battery": {
            "name": Translation.tr("Battery"),
            "description": Translation.tr("Charge level, shown when a battery is present"),
            "icon": "battery_full", "category": "system", "vertical": true
        },
        "sysTray": {
            "name": Translation.tr("System tray"),
            "description": Translation.tr("Icons of background apps"),
            "icon": "more_horiz", "category": "system", "fillHeight": true, "vertical": true, "unique": true
        },
        "privacy": {
            "name": Translation.tr("Privacy indicator"),
            "description": Translation.tr("Appears while the microphone, a camera or screen capture is in use"),
            "icon": "privacy_tip", "category": "system", "vertical": false
        },
        "statusIndicators": {
            "name": Translation.tr("Status indicators"),
            "description": Translation.tr("Network, Bluetooth, layout and notifications; opens the right sidebar"),
            "icon": "wifi", "category": "system", "vertical": true
        },
        "island": {
            "name": Translation.tr("Media island"),
            "description": Translation.tr("Now playing, taken over by recording, pomodoro and stopwatch"),
            "icon": "graphic_eq", "category": "media", "elastic": true, "fillHeight": true, "vertical": false
        },
        "clock": {
            "name": Translation.tr("Clock"),
            "description": Translation.tr("Time and date with a calendar popup"),
            "icon": "schedule", "category": "time", "vertical": true
        },
        "weather": {
            "name": Translation.tr("Weather"),
            "description": Translation.tr("Current temperature and conditions"),
            "icon": "partly_cloudy_day", "category": "time", "vertical": false
        },
        "utilButtons": {
            "name": Translation.tr("Quick buttons"),
            "description": Translation.tr("The buttons chosen under Bar → Utility buttons"),
            "icon": "apps", "category": "buttons", "vertical": false
        },
        "spacer": {
            "name": Translation.tr("Flexible space"),
            "description": Translation.tr("Takes the free space and pushes its neighbours apart"),
            "icon": "space_bar", "category": "builder", "elastic": true, "vertical": true
        },
    })

    function get(type) {
        return root.widgets[type] ?? null;
    }
}
