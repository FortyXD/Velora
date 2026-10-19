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
 * unique:      only one makes sense per bar
 * defaults:    item fields for a newly added one (pill, hideAt, …)
 * options:     [{ key, kind: switch|spin|text|choice|command, label, default, from, to, choices,
 *                 scope: "instance" (stored in the item) | "path:<config path>" (shared setting) }]
 */
Singleton {
    id: root

    readonly property var categories: [
        { "id": "system", "name": Translation.tr("System"), "icon": "settings_applications" },
        { "id": "indicators", "name": Translation.tr("Indicators"), "icon": "wifi" },
        { "id": "media", "name": Translation.tr("Media & activities"), "icon": "music_note" },
        { "id": "time", "name": Translation.tr("Time & weather"), "icon": "schedule" },
        { "id": "buttons", "name": Translation.tr("Buttons"), "icon": "touch_app" },
        { "id": "builder", "name": Translation.tr("Building blocks"), "icon": "widgets" },
    ]

    // Order of the quick buttons group, with the setting that shows each one in it
    readonly property var utilButtonKinds: [
        { "kind": "screenSnip", "option": "showScreenSnip", "name": Translation.tr("Screen snip"), "icon": "screenshot_region" },
        { "kind": "screenRecord", "option": "showScreenRecord", "name": Translation.tr("Screen recording"), "icon": "videocam" },
        { "kind": "colorPicker", "option": "showColorPicker", "name": Translation.tr("Color picker"), "icon": "colorize" },
        { "kind": "keyboardToggle", "option": "showKeyboardToggle", "name": Translation.tr("On-screen keyboard"), "icon": "keyboard" },
        { "kind": "micToggle", "option": "showMicToggle", "name": Translation.tr("Microphone"), "icon": "mic" },
        { "kind": "idleInhibitor", "option": "showIdleInhibitor", "name": Translation.tr("Keep awake"), "icon": "coffee" },
        { "kind": "nightLight", "option": "showNightLight", "name": Translation.tr("Night Light"), "icon": "bedtime" },
        { "kind": "doNotDisturb", "option": "showDoNotDisturb", "name": Translation.tr("Do not disturb"), "icon": "notifications_paused" },
        { "kind": "darkMode", "option": "showDarkModeToggle", "name": Translation.tr("Dark mode"), "icon": "dark_mode" },
        { "kind": "performanceProfile", "option": "showPerformanceProfileToggle", "name": Translation.tr("Power profile"), "icon": "airwave" },
        { "kind": "gpuMode", "option": "showSupergfxctlToggle", "name": Translation.tr("GPU mode"), "icon": "developer_board" },
    ]

    // What a click, middle click or scroll on the free space of a zone does
    readonly property var clickActions: [
        { "value": "none", "name": Translation.tr("Nothing"), "icon": "block" },
        { "value": "sidebarLeft", "name": Translation.tr("Left sidebar"), "icon": "left_panel_open" },
        { "value": "sidebarRight", "name": Translation.tr("Right sidebar"), "icon": "right_panel_open" },
        { "value": "overview", "name": Translation.tr("Search and overview"), "icon": "search" },
        { "value": "session", "name": Translation.tr("Session menu"), "icon": "power_settings_new" },
        { "value": "wallpaperSelector", "name": Translation.tr("Wallpapers"), "icon": "wallpaper" },
        { "value": "mediaPlayPause", "name": Translation.tr("Play or pause media"), "icon": "play_pause" },
        { "value": "muteToggle", "name": Translation.tr("Mute sound"), "icon": "volume_off" },
    ]
    readonly property var scrollActions: [
        { "value": "none", "name": Translation.tr("Nothing"), "icon": "block" },
        { "value": "brightness", "name": Translation.tr("Brightness"), "icon": "light_mode" },
        { "value": "volume", "name": Translation.tr("Volume"), "icon": "volume_up" },
        { "value": "workspaces", "name": Translation.tr("Switch workspaces"), "icon": "view_carousel" },
    ]

    readonly property var widgets: {
        let result = {
            "leftSidebarButton": {
                "name": Translation.tr("Left sidebar button"),
                "description": Translation.tr("Opens the AI, translator and image sidebar"),
                "icon": "auto_awesome", "category": "system", "vertical": true, "unique": true,
                "options": [
                    { "key": "topLeftIcon", "kind": "choice", "label": Translation.tr("Icon"), "scope": "path:bar.topLeftIcon",
                      "choices": [
                          { "value": "spark", "name": Translation.tr("Spark") },
                          { "value": "distro", "name": Translation.tr("Distribution logo") },
                      ] },
                ]
            },
            "activeWindow": {
                "name": Translation.tr("Active window"),
                "description": Translation.tr("Icon, app and title of the focused window"),
                "icon": "web_asset", "category": "system", "elastic": true, "fillHeight": true, "vertical": false,
                "defaults": { "hideAt": 1 }
            },
            "workspaces": {
                "name": Translation.tr("Workspaces"),
                "description": Translation.tr("Workspace switcher with app icons and previews"),
                "icon": "workspaces", "category": "system", "fillHeight": true, "pillPadding": 4, "vertical": true,
                "defaults": { "pill": true },
                "options": [
                    { "key": "shown", "kind": "spin", "label": Translation.tr("Workspaces shown"), "from": 1, "to": 30, "scope": "path:bar.workspaces.shown" },
                    { "key": "showAppIcons", "kind": "switch", "label": Translation.tr("App icons"), "scope": "path:bar.workspaces.showAppIcons" },
                    { "key": "monochromeIcons", "kind": "switch", "label": Translation.tr("Tint app icons"), "scope": "path:bar.workspaces.monochromeIcons" },
                    { "key": "alwaysShowNumbers", "kind": "switch", "label": Translation.tr("Always show numbers"), "scope": "path:bar.workspaces.alwaysShowNumbers" },
                ]
            },
            "resources": {
                "name": Translation.tr("Resources"),
                "description": Translation.tr("Memory, swap and CPU usage"),
                "icon": "memory", "category": "system", "vertical": true,
                "defaults": { "pill": true },
                "options": [
                    { "key": "alwaysShowSwap", "kind": "switch", "label": Translation.tr("Always show swap"), "scope": "path:bar.resources.alwaysShowSwap" },
                    { "key": "alwaysShowCpu", "kind": "switch", "label": Translation.tr("Show CPU while media plays"), "scope": "path:bar.resources.alwaysShowCpu" },
                ]
            },
            "battery": {
                "name": Translation.tr("Battery"),
                "description": Translation.tr("Charge level, shown when a battery is present"),
                "icon": "battery_full", "category": "system", "vertical": true,
                "defaults": { "pill": true }
            },
            "sysTray": {
                "name": Translation.tr("System tray"),
                "description": Translation.tr("Icons of background apps"),
                "icon": "more_horiz", "category": "system", "fillHeight": true, "vertical": true, "unique": true,
                "options": [
                    { "key": "monochromeIcons", "kind": "switch", "label": Translation.tr("Tint icons"), "scope": "path:tray.monochromeIcons" },
                ]
            },
            "privacy": {
                "name": Translation.tr("Privacy indicator"),
                "description": Translation.tr("Appears while the microphone, a camera or screen capture is in use"),
                "icon": "privacy_tip", "category": "indicators", "vertical": false
            },
            "statusIndicators": {
                "name": Translation.tr("Status indicators"),
                "description": Translation.tr("Network, Bluetooth, layout and notifications; opens the right sidebar"),
                "icon": "right_panel_open", "category": "indicators", "vertical": true,
                "options": [
                    { "key": "showAudioMuted", "kind": "switch", "label": Translation.tr("Muted sound"), "default": true, "scope": "instance" },
                    { "key": "showMicMuted", "kind": "switch", "label": Translation.tr("Muted microphone"), "default": true, "scope": "instance" },
                    { "key": "showKeyboardLayout", "kind": "switch", "label": Translation.tr("Keyboard layout"), "default": true, "scope": "instance" },
                    { "key": "showNotifications", "kind": "switch", "label": Translation.tr("Notifications"), "default": true, "scope": "instance" },
                    { "key": "showNetwork", "kind": "switch", "label": Translation.tr("Network"), "default": true, "scope": "instance" },
                    { "key": "showBluetooth", "kind": "switch", "label": Translation.tr("Bluetooth"), "default": true, "scope": "instance" },
                    { "key": "bluetoothBattery", "kind": "switch", "label": Translation.tr("Bluetooth device battery"), "scope": "path:bar.indicators.bluetoothBattery" },
                ]
            },
            "network": {
                "name": Translation.tr("Network"), "description": Translation.tr("Connection and signal strength"),
                "icon": "wifi", "category": "indicators", "vertical": true
            },
            "bluetooth": {
                "name": Translation.tr("Bluetooth"), "description": Translation.tr("Bluetooth state and device battery"),
                "icon": "bluetooth", "category": "indicators", "vertical": true
            },
            "keyboardLayout": {
                "name": Translation.tr("Keyboard layout"), "description": Translation.tr("Current layout, when there is more than one"),
                "icon": "keyboard", "category": "indicators", "vertical": true
            },
            "notifications": {
                "name": Translation.tr("Notifications"), "description": Translation.tr("Bell with unread notifications"),
                "icon": "notifications", "category": "indicators", "vertical": true,
                "options": [
                    { "key": "alwaysShow", "kind": "switch", "label": Translation.tr("Show without unread"), "default": false, "scope": "instance" },
                    { "key": "showUnreadCount", "kind": "switch", "label": Translation.tr("Unread count"), "scope": "path:bar.indicators.notifications.showUnreadCount" },
                ]
            },
            "audioMuted": {
                "name": Translation.tr("Muted sound"), "description": Translation.tr("Shown while the output is muted; click to unmute"),
                "icon": "volume_off", "category": "indicators", "vertical": true
            },
            "micMuted": {
                "name": Translation.tr("Muted microphone"), "description": Translation.tr("Shown while the microphone is muted; click to unmute"),
                "icon": "mic_off", "category": "indicators", "vertical": true
            },
            "island": {
                "name": Translation.tr("Media island"),
                "description": Translation.tr("Now playing, taken over by recording, pomodoro and stopwatch"),
                "icon": "graphic_eq", "category": "media", "elastic": true, "fillHeight": true, "vertical": false,
                "defaults": { "pill": true, "hideAt": 2 },
                "options": [
                    { "key": "showRecording", "kind": "switch", "label": Translation.tr("Screen recording"), "scope": "path:bar.island.showRecording" },
                    { "key": "showPomodoro", "kind": "switch", "label": Translation.tr("Pomodoro"), "scope": "path:bar.island.showPomodoro" },
                    { "key": "showStopwatch", "kind": "switch", "label": Translation.tr("Stopwatch"), "scope": "path:bar.island.showStopwatch" },
                    { "key": "trackToast", "kind": "switch", "label": Translation.tr("Card on track change"), "scope": "path:bar.island.trackToast" },
                ]
            },
            "media": {
                "name": Translation.tr("Media"),
                "description": Translation.tr("Now playing with controls on hover"),
                "icon": "music_note", "category": "media", "elastic": true, "fillHeight": true, "vertical": true,
                "defaults": { "pill": true }
            },
            "clock": {
                "name": Translation.tr("Clock"),
                "description": Translation.tr("Time and date with a calendar popup"),
                "icon": "schedule", "category": "time", "vertical": true,
                "defaults": { "pill": true },
                "options": [
                    { "key": "showDate", "kind": "switch", "label": Translation.tr("Date"), "default": true, "scope": "instance" },
                ]
            },
            "weather": {
                "name": Translation.tr("Weather"),
                "description": Translation.tr("Current temperature and conditions"),
                "icon": "partly_cloudy_day", "category": "time", "vertical": false,
                "defaults": { "pill": true },
                "options": [
                    { "key": "city", "kind": "text", "label": Translation.tr("City (empty: by location)"), "scope": "path:bar.weather.city" },
                    { "key": "useUSCS", "kind": "switch", "label": Translation.tr("Fahrenheit"), "scope": "path:bar.weather.useUSCS" },
                ]
            },
            "utilButtons": {
                "name": Translation.tr("Quick buttons"),
                "description": Translation.tr("A group of the small round buttons"),
                "icon": "apps", "category": "buttons", "vertical": false,
                "defaults": { "pill": true },
                "options": root.utilButtonKinds.map(entry => ({
                    "key": entry.option, "kind": "switch", "label": entry.name, "scope": `path:bar.utilButtons.${entry.option}`
                }))
            },
            "launcher": {
                "name": Translation.tr("Search button"), "description": Translation.tr("Opens search and the overview"),
                "icon": "search", "category": "buttons", "vertical": true
            },
            "session": {
                "name": Translation.tr("Power button"), "description": Translation.tr("Opens the session menu"),
                "icon": "power_settings_new", "category": "buttons", "vertical": true
            },
            "settingsButton": {
                "name": Translation.tr("Settings button"), "description": Translation.tr("Opens the settings app"),
                "icon": "settings", "category": "buttons", "vertical": true
            },
            "wallpaperButton": {
                "name": Translation.tr("Wallpaper button"), "description": Translation.tr("Opens the wallpaper selector"),
                "icon": "wallpaper", "category": "buttons", "vertical": true
            },
            "appButton": {
                "name": Translation.tr("App or command"), "description": Translation.tr("An icon that runs a command of your choice"),
                "icon": "terminal", "category": "buttons", "vertical": true,
                "options": [
                    { "key": "icon", "kind": "text", "label": Translation.tr("Icon (Material Symbols name)"), "default": "terminal", "scope": "instance" },
                    { "key": "command", "kind": "command", "label": Translation.tr("Command"), "default": "", "scope": "instance" },
                    { "key": "tooltip", "kind": "text", "label": Translation.tr("Tooltip"), "default": "", "scope": "instance" },
                ]
            },
            "spacer": {
                "name": Translation.tr("Flexible space"),
                "description": Translation.tr("Takes the free space and pushes its neighbours apart"),
                "icon": "space_bar", "category": "builder", "elastic": true, "vertical": true
            },
            "fixedSpace": {
                "name": Translation.tr("Fixed space"), "description": Translation.tr("A gap of a set size"),
                "icon": "width", "category": "builder", "vertical": true,
                "options": [
                    { "key": "size", "kind": "spin", "label": Translation.tr("Size"), "default": 16, "from": 1, "to": 400, "scope": "instance" },
                ]
            },
            "separator": {
                "name": Translation.tr("Separator"), "description": Translation.tr("A thin line between widgets"),
                "icon": "more_vert", "category": "builder", "vertical": true
            },
            "text": {
                "name": Translation.tr("Text"), "description": Translation.tr("A label with an optional icon"),
                "icon": "title", "category": "builder", "vertical": false,
                "options": [
                    { "key": "text", "kind": "text", "label": Translation.tr("Text"), "default": Translation.tr("Hello"), "scope": "instance" },
                    { "key": "icon", "kind": "text", "label": Translation.tr("Icon (Material Symbols name)"), "default": "", "scope": "instance" },
                ]
            },
        };
        for (const entry of root.utilButtonKinds) {
            result[entry.kind] = {
                "name": entry.name, "description": Translation.tr("Quick button"),
                "icon": entry.icon, "category": "buttons", "vertical": true, "utilButton": true
            };
        }
        return result;
    }

    function get(type) {
        return root.widgets[type] ?? null;
    }

    function optionValue(item, spec) {
        if (spec.scope === "instance") return item?.options?.[spec.key] ?? spec.default;
        return Config.getNestedValue(spec.scope.slice(5), spec.default);
    }
}
