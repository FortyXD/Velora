pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * The parts of the lock screen that can be placed, shown or hidden (see services/LockLayout.qml).
 * `attachable` parts can stick to the password field; `scalable` ones have a size.
 * The order is the order they appear in when the screen locks.
 */
Singleton {
    id: root

    readonly property list<var> elements: [
        { "id": "clock", "name": Translation.tr("Clock"), "icon": "schedule", "scalable": true, "hideable": true,
          "description": Translation.tr("Cookie or digital, with “Locked” under it") },
        { "id": "greeting", "name": Translation.tr("Greeting"), "icon": "waving_hand", "scalable": true, "hideable": true,
          "description": Translation.tr("Good morning, afternoon or evening, with your picture") },
        { "id": "password", "name": Translation.tr("Password field"), "icon": "password", "scalable": false, "hideable": false,
          "description": Translation.tr("Always there; warnings about Caps Lock and the layout show above it") },
        { "id": "user", "name": Translation.tr("User and layout"), "icon": "account_circle", "scalable": false, "hideable": true, "attachable": true,
          "description": Translation.tr("Your user name and the keyboard layout") },
        { "id": "power", "name": Translation.tr("Battery and power"), "icon": "power_settings_new", "scalable": false, "hideable": true, "attachable": true,
          "description": Translation.tr("Battery level and the sleep, power off and restart buttons") },
        { "id": "message", "name": Translation.tr("Message"), "icon": "chat", "scalable": true, "hideable": true, "attachable": true,
          "description": Translation.tr("Your own text, like who to call if this computer is found") },
        { "id": "media", "name": Translation.tr("Music"), "icon": "music_note", "scalable": true, "hideable": true,
          "description": Translation.tr("What's playing, with buttons that work without unlocking") },
        { "id": "weather", "name": Translation.tr("Weather"), "icon": "partly_cloudy_day", "scalable": true, "hideable": true,
          "description": Translation.tr("The weather now, optionally with the next hours") },
        { "id": "notifications", "name": Translation.tr("Notifications"), "icon": "notifications", "scalable": true, "hideable": true,
          "description": Translation.tr("How many there are and from which apps, never their text") },
        { "id": "timer", "name": Translation.tr("Timer"), "icon": "timer", "scalable": true, "hideable": true,
          "description": Translation.tr("A running timer, pomodoro or stopwatch") }
    ]

    readonly property list<string> ids: root.elements.map(element => element.id)

    function get(id) {
        return root.elements.find(element => element.id === id) ?? null;
    }
}
