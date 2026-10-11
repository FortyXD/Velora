pragma Singleton
import Quickshell
import qs.modules.common

/**
 * Names and labels for Hyprland key combos, shared by the cheat sheet and the settings app.
 * Combos are `{ mods: ["Super", "Shift"], key: "S" }`, with the key named the way Hyprland binds it.
 */
Singleton {
    id: root

    readonly property list<string> modOrder: ["Super", "Ctrl", "Alt", "Shift"]

    // XKB keycodes (evdev + 8) of a US layout, so a shortcut recorded in any layout binds the same physical keys
    readonly property var scanCodeNames: ({
        9: "Escape", 10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0",
        20: "Minus", 21: "Equal", 22: "BackSpace", 23: "Tab",
        24: "Q", 25: "W", 26: "E", 27: "R", 28: "T", 29: "Y", 30: "U", 31: "I", 32: "O", 33: "P",
        34: "BracketLeft", 35: "BracketRight", 36: "Return",
        38: "A", 39: "S", 40: "D", 41: "F", 42: "G", 43: "H", 44: "J", 45: "K", 46: "L",
        47: "Semicolon", 48: "Apostrophe", 49: "Grave", 51: "Backslash",
        52: "Z", 53: "X", 54: "C", 55: "V", 56: "B", 57: "N", 58: "M", 59: "Comma", 60: "Period", 61: "Slash",
        65: "Space",
        67: "F1", 68: "F2", 69: "F3", 70: "F4", 71: "F5", 72: "F6", 73: "F7", 74: "F8", 75: "F9", 76: "F10",
        95: "F11", 96: "F12", 107: "Print", 110: "Home", 111: "Up", 112: "Page_Up", 113: "Left", 114: "Right",
        115: "End", 116: "Down", 117: "Page_Down", 118: "Insert", 119: "Delete", 127: "Pause"
    })

    readonly property var qtKeyNames: ({
        [Qt.Key_VolumeUp]: "XF86AudioRaiseVolume", [Qt.Key_VolumeDown]: "XF86AudioLowerVolume",
        [Qt.Key_VolumeMute]: "XF86AudioMute", [Qt.Key_MicMute]: "XF86AudioMicMute",
        [Qt.Key_MediaPlay]: "XF86AudioPlay", [Qt.Key_MediaPause]: "XF86AudioPause",
        [Qt.Key_MediaTogglePlayPause]: "XF86AudioPlay", [Qt.Key_MediaNext]: "XF86AudioNext",
        [Qt.Key_MediaPrevious]: "XF86AudioPrev", [Qt.Key_MonBrightnessUp]: "XF86MonBrightnessUp",
        [Qt.Key_MonBrightnessDown]: "XF86MonBrightnessDown", [Qt.Key_Calculator]: "XF86Calculator",
        [Qt.Key_Print]: "Print", [Qt.Key_Escape]: "Escape", [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "KP_Enter",
        [Qt.Key_Space]: "Space", [Qt.Key_Tab]: "Tab", [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete",
        [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Page_Up", [Qt.Key_PageDown]: "Page_Down",
        [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down", [Qt.Key_Insert]: "Insert"
    })

    readonly property var labels: ({
        "Return": "Enter", "KP_Enter": "Enter", "Escape": "Esc", "Delete": "Del", "BackSpace": "⌫", "Space": "Space",
        "Slash": "/", "Backslash": "\\", "Period": ".", "Comma": ",", "Minus": "−", "Equal": "=",
        "BracketLeft": "[", "BracketRight": "]", "Semicolon": ";", "Apostrophe": "'", "Grave": "`",
        "Page_Up": "PgUp", "Page_Down": "PgDn", "Prior": "PgUp", "Next": "PgDn", "Print": "PrtSc",
        "Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Arrows": "← ↑ → ↓", "Left/Right": "← →", "1-0": "1 … 0",
        "XF86AudioRaiseVolume": "Vol +", "XF86AudioLowerVolume": "Vol −", "XF86AudioMute": "Mute",
        "XF86AudioMicMute": "Mic", "XF86AudioPlay": "Play", "XF86AudioPause": "Pause", "XF86AudioNext": "Next",
        "XF86AudioPrev": "Prev", "XF86MonBrightnessUp": "Bright +", "XF86MonBrightnessDown": "Bright −"
    })
    readonly property var mouseLabels: ({
        "mouse:272": "LMB", "mouse:273": "RMB", "mouse:274": "MMB", "mouse:275": "Mouse 4", "mouse:276": "Mouse 5",
        "mouse_up": "Scroll ↓", "mouse_down": "Scroll ↑", "Scroll": "Scroll"
    })
    readonly property var mouseSymbols: ({
        "mouse:272": "L󰍽", "mouse:273": "R󰍽", "mouse_up": "󱕐", "mouse_down": "󱕑", "Scroll": "󱕒"
    })
    readonly property var fnSymbols: ({
        "F1": "󱊫", "F2": "󱊬", "F3": "󱊭", "F4": "󱊮", "F5": "󱊯", "F6": "󱊰",
        "F7": "󱊱", "F8": "󱊲", "F9": "󱊳", "F10": "󱊴", "F11": "󱊵", "F12": "󱊶"
    })
    readonly property var modSymbols: ({ "Ctrl": "⌃", "Alt": "⌥", "Shift": "⇧" })

    function sortMods(mods) {
        return root.modOrder.filter(mod => (mods ?? []).includes(mod));
    }

    // Same identity the Lua side uses: "SUPER+SHIFT|S". Raw keycodes and key name aliases
    // are resolved first, so code:10 and 1 count as the same key.
    function normalizeKey(key) {
        let name = (key ?? "").toString();
        const code = /^code:(\d+)$/i.exec(name);
        if (code && root.scanCodeNames[parseInt(code[1])]) name = root.scanCodeNames[parseInt(code[1])];
        const aliases = { "PRIOR": "PAGE_UP", "NEXT": "PAGE_DOWN", "ENTER": "RETURN" };
        name = name.toUpperCase();
        return aliases[name] ?? name;
    }

    function comboKey(mods, key) {
        return `${root.sortMods(mods).join("+").toUpperCase()}|${root.normalizeKey(key)}`;
    }

    // Lua writes combos as "SUPER+SHIFT|S" already; this resolves keycodes in them the same way
    function normalizeComboString(combo) {
        const [mods, key] = combo.split("|");
        return `${mods}|${root.normalizeKey(key)}`;
    }

    function modLabel(mod) {
        const options = Config.options?.cheatsheet;
        if (mod === "Super") return options?.superKey?.length > 0 ? options.superKey : "Super";
        if (options?.useModifierSymbols && root.modSymbols[mod]) return root.modSymbols[mod];
        return mod;
    }

    function keyLabel(key) {
        const options = Config.options?.cheatsheet;
        if (key === "Super" || key === "Super_L" || key === "Super_R") return root.modLabel("Super");
        if (root.mouseLabels[key] !== undefined) return options?.useMouseSymbol && root.mouseSymbols[key] ? root.mouseSymbols[key] : root.mouseLabels[key];
        if (options?.useFnSymbol && root.fnSymbols[key]) return root.fnSymbols[key];
        if (root.labels[key] !== undefined) return root.labels[key];
        const code = /^code:(\d+)$/.exec(key ?? "");
        if (code) return root.keyLabel(root.scanCodeNames[parseInt(code[1])] ?? key);
        return (key ?? "").length === 1 ? key.toUpperCase() : key;
    }

    // Labels for every keycap of a combo
    function comboLabels(mods, key) {
        return [...root.sortMods(mods).map(mod => root.modLabel(mod)), root.keyLabel(key)];
    }

    // Plain text, for search and tooltips: "Super + Shift + S"
    function comboText(mods, key) {
        return [...root.sortMods(mods), root.labels[key] ?? root.mouseLabels[key] ?? key].join(" + ");
    }

    function isModifierKey(qtKey) {
        return [Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Meta, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Shift,
                Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_Hyper_L, Qt.Key_Hyper_R].includes(qtKey);
    }

    function modsFromEvent(modifiers) {
        let mods = [];
        if (modifiers & Qt.MetaModifier) mods.push("Super");
        if (modifiers & Qt.ControlModifier) mods.push("Ctrl");
        if (modifiers & Qt.AltModifier) mods.push("Alt");
        if (modifiers & Qt.ShiftModifier) mods.push("Shift");
        return mods;
    }

    // Hyprland's name for the key of a key event, or "" if it can't be bound
    function keyFromEvent(event) {
        if (root.isModifierKey(event.key)) return "";
        const byScanCode = root.scanCodeNames[event.nativeScanCode];
        if (byScanCode) return byScanCode;
        if (root.qtKeyNames[event.key]) return root.qtKeyNames[event.key];
        if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F24) return `F${event.key - Qt.Key_F1 + 1}`;
        if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) return String.fromCharCode(event.key);
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) return String.fromCharCode(event.key);
        return "";
    }

    // Keys that make sense without a modifier
    function worksAlone(key) {
        return /^(F\d+|Print|Pause|Insert|XF86.*)$/.test(key);
    }
}
