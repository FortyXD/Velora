pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * What the sidebars can be made of, for the sidebars themselves and their editor in the settings app.
 * Metadata only; the toggles' own models start services, so editors use this instead.
 *
 * parts{type}: name, description, icon, category,
 *   limit     "shell": once across both sidebars (counting tabs) | "sidebar": once per sidebar | "none"
 *   fill      takes free height (true) or its own (false)
 *   minHeight when it fills
 *   tabbable  can be a page of a "tabs" part
 *   lazy      built the first time its sidebar opens rather than with the shell
 *   policy    "ai" / "weeb": a global switch (Config.options.policies) also turns it off
 *   options   [{ key, kind: "switch"|"slider"|"choice", label, icon, description, default, from, to, step,
 *               unit, choices: [{ value, label, icon }], scope: "instance"|"path:<config path>", when: { key, value } }]
 *   editor    a special editor in the settings app: "headerButtons", "quickToggles", "tabs", "tools"
 *   links     [{ label, icon, page, section }] to other settings pages
 */
Singleton {
    id: root

    readonly property list<var> categories: [
        { "id": "controls", "name": Translation.tr("Controls"), "icon": "tune" },
        { "id": "info", "name": Translation.tr("At a glance"), "icon": "visibility" },
        { "id": "productivity", "name": Translation.tr("Productivity"), "icon": "task_alt" },
        { "id": "assistant", "name": Translation.tr("Assistant and fun"), "icon": "neurology" },
        { "id": "layout", "name": Translation.tr("Layout"), "icon": "tab" }
    ]

    readonly property var parts: ({
        "header": {
            "name": Translation.tr("Top row"), "icon": "toolbar", "category": "controls", "limit": "sidebar",
            "description": Translation.tr("Uptime and the edit, reload, settings and power buttons"),
            "options": [
                { "key": "showUptime", "kind": "switch", "icon": "timer", "label": Translation.tr("Uptime"), "default": true }
            ],
            "editor": "headerButtons"
        },
        "sliders": {
            "name": Translation.tr("Sliders"), "icon": "tune", "category": "controls", "limit": "sidebar",
            "description": Translation.tr("Brightness, volume and microphone"),
            "options": [
                { "key": "showBrightness", "kind": "switch", "icon": "brightness_6", "label": Translation.tr("Brightness"), "scope": "path:sidebar.quickSliders.showBrightness" },
                { "key": "showVolume", "kind": "switch", "icon": "volume_up", "label": Translation.tr("Volume"), "scope": "path:sidebar.quickSliders.showVolume" },
                { "key": "showMic", "kind": "switch", "icon": "mic", "label": Translation.tr("Microphone"), "scope": "path:sidebar.quickSliders.showMic" }
            ]
        },
        "toggles": {
            "name": Translation.tr("Quick toggles"), "icon": "toggle_on", "category": "controls", "limit": "shell",
            "description": Translation.tr("Wi-Fi, Bluetooth, night light and more, one tap each"),
            "editor": "quickToggles"
        },
        "tools": {
            "name": Translation.tr("Quick tools"), "icon": "handyman", "category": "controls", "limit": "none",
            "description": Translation.tr("Screenshot, recording, color picker, text from the screen, emoji and your apps, a click away"),
            "options": [
                { "key": "labels", "kind": "switch", "icon": "label", "label": Translation.tr("Names under the buttons"), "default": true },
                { "key": "columns", "kind": "slider", "icon": "view_column", "label": Translation.tr("Columns"), "default": 4, "from": 3, "to": 6, "step": 1 }
            ],
            "editor": "tools"
        },
        "notifications": {
            "name": Translation.tr("Notifications"), "icon": "notifications", "category": "info", "limit": "shell",
            "fill": true, "minHeight": 160, "tabbable": true,
            "description": Translation.tr("The notification list; marked read when its sidebar opens"),
            "links": [{ "label": Translation.tr("Which apps may notify"), "icon": "notifications", "page": "notifications", "section": Translation.tr("Notifications") }]
        },
        "media": {
            "name": Translation.tr("Media"), "icon": "music_note", "category": "info", "limit": "shell", "lazy": true,
            "description": Translation.tr("What's playing, with its cover and controls"),
            "options": [
                { "key": "hideWhenIdle", "kind": "switch", "icon": "visibility_off", "label": Translation.tr("Hide when nothing plays"), "default": true }
            ]
        },
        "weather": {
            "name": Translation.tr("Weather"), "icon": "partly_cloudy_day", "category": "info", "limit": "shell", "lazy": true,
            "description": Translation.tr("Now, the next hours and the coming days"),
            "options": [
                { "key": "showHours", "kind": "switch", "icon": "schedule", "label": Translation.tr("Next hours"), "default": true },
                { "key": "showDays", "kind": "switch", "icon": "date_range", "label": Translation.tr("Coming days"), "default": false },
                { "key": "showDetails", "kind": "switch", "icon": "air", "label": Translation.tr("Wind, humidity and more"), "default": false }
            ],
            "links": [{ "label": Translation.tr("Place and units"), "icon": "location_on", "page": "widgets", "section": Translation.tr("Weather") }]
        },
        "system": {
            "name": Translation.tr("System"), "icon": "monitor_heart", "category": "info", "limit": "shell", "lazy": true,
            "description": Translation.tr("Processor, memory, network speed, battery and updates"),
            "options": [
                { "key": "graphs", "kind": "switch", "icon": "show_chart", "label": Translation.tr("Graphs"), "default": true },
                { "key": "network", "kind": "switch", "icon": "network_check", "label": Translation.tr("Network speed"), "default": true },
                { "key": "battery", "kind": "switch", "icon": "battery_full", "label": Translation.tr("Battery"), "default": true },
                { "key": "updates", "kind": "switch", "icon": "system_update", "label": Translation.tr("Updates"), "default": true }
            ]
        },
        "calendar": {
            "name": Translation.tr("Calendar"), "icon": "calendar_month", "category": "productivity", "limit": "shell",
            "fill": true, "minHeight": 280, "tabbable": true,
            "description": Translation.tr("The month at a glance")
        },
        "todo": {
            "name": Translation.tr("To Do"), "icon": "done_outline", "category": "productivity", "limit": "shell",
            "fill": true, "minHeight": 240, "tabbable": true,
            "description": Translation.tr("Tasks to do and done")
        },
        "timer": {
            "name": Translation.tr("Timer"), "icon": "schedule", "category": "productivity", "limit": "shell",
            "fill": true, "minHeight": 280, "tabbable": true,
            "description": Translation.tr("Pomodoro, stopwatch and countdown")
        },
        "notes": {
            "name": Translation.tr("Notes"), "icon": "sticky_note_2", "category": "productivity", "limit": "shell",
            "fill": true, "minHeight": 160, "tabbable": true, "lazy": true,
            "description": Translation.tr("A scratchpad that saves as you type; the same notes as on the overlay")
        },
        "clipboard": {
            "name": Translation.tr("Clipboard"), "icon": "content_paste", "category": "productivity", "limit": "shell",
            "fill": true, "minHeight": 200, "tabbable": true, "lazy": true,
            "description": Translation.tr("What you copied, searchable; click to copy again"),
            "options": [
                { "key": "showImages", "kind": "switch", "icon": "image", "label": Translation.tr("Show copied images"), "default": true },
                { "key": "closeAfterCopy", "kind": "switch", "icon": "close", "label": Translation.tr("Close the sidebar after copying"), "default": true }
            ]
        },
        "ai": {
            "name": Translation.tr("Intelligence"), "icon": "neurology", "category": "assistant", "limit": "shell",
            "fill": true, "minHeight": 260, "tabbable": true, "lazy": true, "policy": "ai",
            "description": Translation.tr("Chat with an assistant about anything on your screen"),
            "options": [
                { "key": "textFadeIn", "kind": "switch", "icon": "gradient", "label": Translation.tr("Fade in the answers"), "scope": "path:sidebar.ai.textFadeIn" }
            ],
            "links": [{ "label": Translation.tr("Models, keys and the system prompt"), "icon": "neurology", "page": "search", "section": Translation.tr("Assistant") }]
        },
        "translator": {
            "name": Translation.tr("Translator"), "icon": "translate", "category": "assistant", "limit": "shell",
            "fill": true, "minHeight": 240, "tabbable": true, "lazy": true,
            "description": Translation.tr("Translates as you type"),
            "options": [
                { "key": "delay", "kind": "slider", "icon": "hourglass_empty", "label": Translation.tr("Translate after a pause of"), "from": 100, "to": 1500, "step": 50, "unit": "ms", "scope": "path:sidebar.translator.delay" }
            ]
        },
        "anime": {
            "name": Translation.tr("Anime"), "icon": "bookmark_heart", "category": "assistant", "limit": "shell",
            "fill": true, "minHeight": 260, "tabbable": true, "lazy": true, "policy": "weeb",
            "description": Translation.tr("Wallhaven and booru image browser"),
            "options": [
                { "key": "limit", "kind": "slider", "icon": "photo_library", "label": Translation.tr("Images per page"), "from": 5, "to": 100, "step": 5, "scope": "path:sidebar.booru.limit" }
            ]
        },
        "tabs": {
            "name": Translation.tr("Tabs"), "icon": "tab", "category": "layout", "limit": "none",
            "fill": true, "minHeight": 200,
            "description": Translation.tr("Several parts in one place, one at a time"),
            "options": [
                { "key": "style", "kind": "choice", "icon": "style", "label": Translation.tr("Style"), "default": "bar", "choices": [
                    { "value": "bar", "label": Translation.tr("Tab bar on top"), "icon": "tab" },
                    { "value": "rail", "label": Translation.tr("Rail on the side"), "icon": "view_sidebar" }
                ] },
                { "key": "collapsible", "kind": "switch", "icon": "unfold_less", "label": Translation.tr("Can be folded away"), "default": false, "when": { "key": "style", "value": "rail" } },
                { "key": "share", "kind": "slider", "icon": "height", "label": Translation.tr("Height"), "description": Translation.tr("Of the sidebar, while another part takes the rest; 0 shares the free height"),
                  "default": 0, "from": 0, "to": 0.7, "step": 0.05, "unit": "%" }
            ],
            "editor": "tabs"
        }
    })

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

    readonly property list<var> headerButtons: [
        { "id": "edit", "name": Translation.tr("Edit quick toggles"), "icon": "edit" },
        { "id": "reload", "name": Translation.tr("Reload Hyprland & Quickshell"), "icon": "restart_alt" },
        { "id": "settings", "name": Translation.tr("Settings"), "icon": "settings" },
        { "id": "session", "name": Translation.tr("Session"), "icon": "power_settings_new" }
    ]

    // The quick tools part (ToolsPart): a tool, or "app:<desktop id>" for an app
    readonly property list<var> tools: [
        { "id": "screenshot", "name": Translation.tr("Screenshot"), "icon": "screenshot_region" },
        { "id": "record", "name": Translation.tr("Record"), "icon": "videocam" },
        { "id": "colorPicker", "name": Translation.tr("Color picker"), "icon": "colorize" },
        { "id": "ocr", "name": Translation.tr("Text from screen"), "icon": "document_scanner" },
        { "id": "lens", "name": Translation.tr("Search the screen"), "icon": "image_search" },
        { "id": "emoji", "name": Translation.tr("Emoji"), "icon": "mood" },
        { "id": "clipboardSearch", "name": Translation.tr("Clipboard search"), "icon": "content_paste_search" },
        { "id": "songRec", "name": Translation.tr("Identify music"), "icon": "music_note" },
        { "id": "qr", "name": Translation.tr("QR codes"), "icon": "qr_code_2" },
        { "id": "converter", "name": Translation.tr("Convert files"), "icon": "swap_horiz" },
        { "id": "keyboard", "name": Translation.tr("On-screen keyboard"), "icon": "keyboard" }
    ]
    readonly property list<string> defaultTools: ["screenshot", "record", "colorPicker", "ocr", "lens", "emoji", "songRec", "qr"]

    function part(type) {
        return root.parts[type] ?? null;
    }
    function toggle(type) {
        return root.toggles.find(t => t.type === type) ?? null;
    }
    function tool(id) {
        return root.tools.find(t => t.id === id) ?? null;
    }
    function typesIn(category) {
        return Object.keys(root.parts).filter(type => root.parts[type].category === category);
    }
}
