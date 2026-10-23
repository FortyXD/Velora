pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * What the sidebars are made of, for the sidebars themselves and their editor in the settings app:
 * the sections of the right sidebar, the quick toggles of both styles, the widget tabs and the left tabs.
 * Metadata only; the toggles' own models start services, so editors use this instead.
 */
Singleton {
    id: root

    readonly property list<var> sections: [
        { "type": "header", "name": Translation.tr("Top row"), "icon": "toolbar", "fixed": true,
          "description": Translation.tr("Uptime and the edit, reload, settings and power buttons") },
        { "type": "sliders", "name": Translation.tr("Sliders"), "icon": "tune",
          "description": Translation.tr("Brightness, volume and microphone") },
        { "type": "toggles", "name": Translation.tr("Quick toggles"), "icon": "toggle_on",
          "description": Translation.tr("Wi-Fi, Bluetooth, night light and more, one tap each") },
        { "type": "notifications", "name": Translation.tr("Notifications"), "icon": "notifications",
          "description": Translation.tr("The notification list; it takes the free height") },
        { "type": "widgets", "name": Translation.tr("Calendar and tools"), "icon": "calendar_month",
          "description": Translation.tr("Calendar, to-do list and timers as tabs") }
    ]

    readonly property list<var> toggles: [
        { "type": "network", "name": Translation.tr("Internet"), "icon": "wifi", "classic": true },
        { "type": "bluetooth", "name": Translation.tr("Bluetooth"), "icon": "bluetooth", "classic": true },
        { "type": "audio", "name": Translation.tr("Audio output"), "icon": "volume_up" },
        { "type": "mic", "name": Translation.tr("Audio input"), "icon": "mic" },
        { "type": "nightLight", "name": Translation.tr("Night Light"), "icon": "bedtime", "classic": true },
        { "type": "darkMode", "name": Translation.tr("Dark Mode"), "icon": "contrast" },
        { "type": "idleInhibitor", "name": Translation.tr("Keep awake"), "icon": "coffee", "classic": true },
        { "type": "powerSaving", "name": Translation.tr("Energy saving"), "icon": "energy_savings_leaf", "classic": true },
        { "type": "powerProfile", "name": Translation.tr("Power Profile"), "icon": "speed" },
        { "type": "gameMode", "name": Translation.tr("Game mode"), "icon": "gamepad", "classic": true },
        { "type": "easyEffects", "name": Translation.tr("EasyEffects"), "icon": "graphic_eq", "classic": true },
        { "type": "cloudflareWarp", "name": Translation.tr("Cloudflare WARP"), "icon": "cloud_lock", "classic": true },
        { "type": "notifications", "name": Translation.tr("Notifications"), "icon": "notifications_active" },
        { "type": "screenSnip", "name": Translation.tr("Screen snip"), "icon": "screenshot_region" },
        { "type": "colorPicker", "name": Translation.tr("Color picker"), "icon": "colorize" },
        { "type": "onScreenKeyboard", "name": Translation.tr("Virtual Keyboard"), "icon": "keyboard" },
        { "type": "musicRecognition", "name": Translation.tr("Identify Music"), "icon": "music_note" },
        { "type": "antiFlashbang", "name": Translation.tr("Anti-flashbang"), "icon": "flash_off" }
    ]

    readonly property list<var> widgetTabs: [
        { "type": "calendar", "name": Translation.tr("Calendar"), "icon": "calendar_month", "widget": "calendar/CalendarWidget.qml" },
        { "type": "todo", "name": Translation.tr("To Do"), "icon": "done_outline", "widget": "todo/TodoWidget.qml" },
        { "type": "timer", "name": Translation.tr("Timer"), "icon": "schedule", "widget": "pomodoro/PomodoroWidget.qml" }
    ]

    readonly property list<var> headerButtons: [
        { "id": "edit", "name": Translation.tr("Edit quick toggles"), "icon": "edit" },
        { "id": "reload", "name": Translation.tr("Reload Hyprland & Quickshell"), "icon": "restart_alt" },
        { "id": "settings", "name": Translation.tr("Settings"), "icon": "settings" },
        { "id": "session", "name": Translation.tr("Session"), "icon": "power_settings_new" }
    ]

    readonly property list<var> leftTabs: [
        { "id": "ai", "name": Translation.tr("Intelligence"), "icon": "neurology" },
        { "id": "translator", "name": Translation.tr("Translator"), "icon": "translate" },
        { "id": "anime", "name": Translation.tr("Anime"), "icon": "bookmark_heart" }
    ]

    function section(type) {
        return root.sections.find(s => s.type === type) ?? null;
    }
    function toggle(type) {
        return root.toggles.find(t => t.type === type) ?? null;
    }
    function widgetTab(type) {
        return root.widgetTabs.find(t => t.type === type) ?? null;
    }
}
