pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common

/**
 * Tracks the active typing device and its XKB layout and variant.
 */
Singleton {
    id: root
    property var keyboards: []
    property string keyboardName: ""
    readonly property var keyboard: keyboards.find(device => device.name === keyboardName)
    readonly property list<string> layoutCodes: keyboard?.layout ? keyboard.layout.split(",").map(code => code.trim()) : []
    readonly property list<string> variantCodes: (keyboard?.variant ?? "").split(",").map(code => code.trim())
    property var layoutsByName: ({})
    property string currentLayoutName: ""
    readonly property var currentLayout: {
        const index = keyboard?.active_layout_index;
        if (keyboard?.active_keymap === currentLayoutName && layoutCodes[index])
            return { code: layoutCodes[index], variant: variantCodes[index] ?? "" };
        return layoutsByName[currentLayoutName];
    }
    readonly property string currentLayoutCode: currentLayout?.code ?? ""
    readonly property string currentLayoutVariant: currentLayout?.variant ?? ""
    property var baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"
    property int layoutRevision: 0
    property bool refreshPending: false

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
        const layouts = {};
        let section = "";
        for (const line of content.split("\n")) {
            if (line.trim().startsWith("!")) {
                section = line.trim().slice(1).trim();
                continue;
            }
            const entry = line.trim().match(/^(\S+)\s+(.+)$/);
            if (!entry) continue;
            if (section === "layout") layouts[entry[2]] = { code: entry[1], variant: "" };
            else if (section === "variant") {
                const variant = entry[2].match(/^(\S+):\s+(.+)$/);
                if (variant) layouts[variant[2]] = { code: variant[1], variant: entry[1] };
            }
        }
        root.layoutsByName = layouts;
    }

    function refreshDevices() {
        root.refreshPending = fetchLayoutsProc.running;
        if (root.refreshPending) return;
        fetchLayoutsProc.revision = root.layoutRevision;
        fetchLayoutsProc.running = true;
    }

    function layoutChanged(data) {
        const separator = data.indexOf(",");
        const device = data.slice(0, separator);
        if (separator < 0 || root.isPseudoKeyboard(device)) return;
        root.layoutRevision++;
        root.keyboardName = device;
        root.currentLayoutName = data.slice(separator + 1);
        Config.options.osk.layout = root.currentLayoutName.split(" (")[0];
        const inDevice = root.layoutCodes.some((code, i) => code === root.currentLayoutCode
            && (root.variantCodes[i] ?? "") === root.currentLayoutVariant);
        if (!inDevice) root.refreshDevices();
    }

    Component.onCompleted: refreshDevices()
    Process {
        id: fetchLayoutsProc
        property int revision
        command: ["hyprctl", "-j", "devices"]
        onExited: if (root.refreshPending) Qt.callLater(root.refreshDevices)
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return;
                try {
                    root.keyboards = JSON.parse(text).keyboards ?? [];
                    // A layout event received during this read is newer than the snapshot.
                    if (fetchLayoutsProc.revision !== root.layoutRevision) return;
                    const keyboard = root.keyboard ?? root.typingKeyboard(root.keyboards);
                    if (!keyboard) return;
                    root.keyboardName = keyboard.name;
                    root.currentLayoutName = keyboard.active_keymap;
                } catch (error) {
                    console.warn("[HyprlandXkb] Couldn't read keyboards:", error);
                }
            }
        }
    }

    // Update the layout name when it changes
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") root.layoutChanged(event.data);
            else if (event.name === "configreloaded") root.refreshDevices();
        }
    }
}
