pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common

/**
 * Exposes the active Hyprland Xkb keyboard layout name and code for indicators.
 */
Singleton {
    id: root
    // You can read these
    property list<string> layoutCodes: []
    property var cachedLayoutCodes: ({})
    property string currentLayoutName: ""
    property string currentLayoutCode: ""
    // For the service
    property var baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"
    property bool needsLayoutRefresh: false

    // Power/sleep buttons, brightness keys, laptop hotkeys and virtual input devices all show up
    // as keyboards with their own layout state. They often become Hyprland's "main" keyboard,
    // but nobody types on them, so their layout must not be reported as the current one.
    function isPseudoKeyboard(name) {
        return /power-button|sleep-button|video-bus|hotkeys|wmi|virtual|ydotool|consumer-control|system-control|lid-switch|avrcp/i.test(name ?? "");
    }

    function typingKeyboard(keyboards) {
        return keyboards.find(kb => kb.main && !root.isPseudoKeyboard(kb.name))
            ?? keyboards.find(kb => !root.isPseudoKeyboard(kb.name))
            ?? keyboards.find(kb => kb.main);
    }

    // Index all names once. Switching layouts must not wait for a new process or file read.
    FileView {
        id: layoutNames
        path: root.baseLayoutFilePath
        blockLoading: true
        onLoaded: root.indexLayoutNames(text())
    }
    function indexLayoutNames(content) {
        let codes = {};
        let section = "";
        for (const line of content.split("\n")) {
            if (line.trim().startsWith("!")) {
                section = line.trim().slice(1).trim();
                continue;
            }
            const entry = line.trim().match(/^(\S+)\s+(.+)$/);
            if (!entry) continue;
            if (section === "layout") codes[entry[2]] = entry[1];
            else if (section === "variant") {
                const variant = entry[2].match(/^(\S+):\s+(.+)$/);
                if (variant) codes[variant[2]] = variant[1];
            }
        }
        root.cachedLayoutCodes = codes;
        root.updateLayoutCode();
    }
    onCurrentLayoutNameChanged: root.updateLayoutCode()
    function updateLayoutCode() {
        root.currentLayoutCode = root.cachedLayoutCodes[root.currentLayoutName] ?? "";
    }

    // Find out available layouts and current active layout. Should only be necessary on init
    Process {
        id: fetchLayoutsProc
        running: true
        command: ["hyprctl", "-j", "devices"]

        stdout: StdioCollector {
            id: devicesCollector
            onStreamFinished: {
                try {
                    const parsedOutput = JSON.parse(devicesCollector.text);
                    const keyboard = root.typingKeyboard(parsedOutput.keyboards ?? []);
                    if (!keyboard) return;
                    root.layoutCodes = keyboard.layout.split(",").map(code => code.trim());
                    root.currentLayoutName = keyboard.active_keymap;
                } catch (error) {
                    console.warn("[HyprlandXkb] Couldn't read keyboards:", error);
                }
                // console.log("[HyprlandXkb] Fetched | Layouts (multiple: " + (root.layoutCodes.length > 1) + "): "
                //     + root.layoutCodes.join(", ") + " | Active: " + root.currentLayoutName);
            }
        }
    }

    // Update the layout name when it changes
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                if (root.needsLayoutRefresh) {
                    root.needsLayoutRefresh = false;
                    fetchLayoutsProc.running = true;
                }

                // Update when layout might have changed
                const dataString = event.data;
                if (root.isPseudoKeyboard(dataString.substring(0, dataString.indexOf(",")))) return;
                root.currentLayoutName = dataString.substring(dataString.indexOf(",") + 1);

                // Update layout for on-screen keyboard (osk)
                Config.options.osk.layout = root.currentLayoutName.split(" (")[0];
            } else if (event.name == "configreloaded") {
                // Read added/removed layouts now, rather than losing the first switch after a reload.
                root.needsLayoutRefresh = true;
                fetchLayoutsProc.running = true;
            }
        }
    }
}
