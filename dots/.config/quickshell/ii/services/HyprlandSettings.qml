pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions

/**
 * Hyprland options edited from the settings app.
 * Current values are read with `hyprctl getoption`. Values the user changes are kept in
 * ~/.config/hypr/custom/shell_settings.json and written as Lua to custom/shell_settings.lua,
 * which hyprland.lua loads after the default and custom config. Hyprland is then reloaded.
 * The shell (presets) and the settings app both write here, so the file is watched and re-read
 * before every change. Keys starting with "shell:" aren't Hyprland options:
 *   shell:animationProfile  material (default) | fast | smooth | minimal — see hyprland/animations/
 */
Singleton {
    id: root

    readonly property string jsonPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/shell_settings.json`)
    readonly property string luaPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/shell_settings.lua`)
    readonly property string hyprlandConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland.lua`)
    // `hyprctl reload`, skipped while hyprland.lua can't be reached (a moved checkout leaves the link
    // dangling): Hyprland would reload into its generated fallback config, losing every bind and rule
    readonly property list<string> reloadCommand: ["sh", "-c", 'test -e "$1" && exec hyprctl reload', "sh", root.hyprlandConfigPath]

    // Options that the settings pages can show, read once on startup
    readonly property list<string> options: [
        "general:layout", "general:gaps_in", "general:gaps_out", "general:gaps_workspaces",
        "general:border_size", "general:resize_on_border", "general:snap:enabled",
        "dwindle:preserve_split", "dwindle:smart_split",
        "decoration:rounding", "decoration:rounding_power",
        "decoration:active_opacity", "decoration:inactive_opacity",
        "decoration:dim_inactive", "decoration:dim_strength",
        "decoration:blur:enabled", "decoration:blur:size", "decoration:blur:passes",
        "decoration:blur:xray", "decoration:blur:vibrancy",
        "decoration:shadow:enabled", "decoration:shadow:range",
        "animations:enabled",
        "input:kb_layout", "input:kb_variant", "input:kb_options",
        "input:repeat_rate", "input:repeat_delay", "input:numlock_by_default",
        "input:sensitivity", "input:accel_profile", "input:natural_scroll",
        "input:follow_mouse", "input:scroll_factor",
        "input:touchpad:natural_scroll", "input:touchpad:tap_to_click",
        "input:touchpad:disable_while_typing", "input:touchpad:clickfinger_behavior",
        "input:touchpad:scroll_factor",
        "gestures:workspace_swipe_distance", "gestures:workspace_swipe_create_new",
        "cursor:inactive_timeout", "cursor:hide_on_key_press",
        "misc:vrr", "misc:focus_on_activate", "misc:enable_swallow",
        "misc:animate_manual_resizes", "misc:animate_mouse_windowdragging",
        "misc:mouse_move_enables_dpms", "misc:key_press_enables_dpms"
    ]

    property var values: ({})     // Effective value of every option above
    property var overrides: ({})  // Only what was changed here
    property bool ready: false
    property bool applying: applyTimer.running || reloadProc.running

    function get(key, fallback) {
        const value = root.values[key];
        return value === undefined ? fallback : value;
    }

    function isOverridden(key) {
        return root.overrides[key] !== undefined;
    }

    // Picks up what the other writer saved. Skipped while changes made here wait to be written,
    // because those are newer. text() blocks until the reload is read, so this is synchronous.
    function syncFromFile() {
        if (applyTimer.running) return;
        jsonFile.reload();
        root.parseFile();
    }
    function parseFile() {
        const text = jsonFile.text();
        if (text.trim().length === 0) { // No file yet: nothing changed here
            root.overrides = {};
            return;
        }
        try {
            root.overrides = JSON.parse(text) ?? {};
        } catch (e) {
            // Keep what was known: writing the next change on top of {} would drop every other override
            console.warn("[HyprlandSettings] Couldn't parse", root.jsonPath, e);
        }
    }

    readonly property list<string> animationProfiles: ["material", "fast", "smooth", "minimal"]
    readonly property string animationProfile: root.overrides["shell:animationProfile"] ?? "material"

    function set(key, value) {
        root.syncFromFile();
        if (root.values[key] === value && root.isOverridden(key)) return;
        let newValues = Object.assign({}, root.values);
        newValues[key] = value;
        root.values = newValues;
        let newOverrides = Object.assign({}, root.overrides);
        newOverrides[key] = value;
        root.overrides = newOverrides;
        applyTimer.restart();
    }

    // Changes several options with a single reload of Hyprland
    function setMany(map) {
        root.syncFromFile();
        let newValues = Object.assign({}, root.values);
        let newOverrides = Object.assign({}, root.overrides);
        for (const key of Object.keys(map)) {
            newValues[key] = map[key];
            newOverrides[key] = map[key];
        }
        root.values = newValues;
        root.overrides = newOverrides;
        applyTimer.restart();
    }

    // Replaces every change made here at once (used to undo a preset)
    function replaceOverrides(map) {
        root.overrides = Object.assign({}, map ?? {});
        root.reloadValuesAfterApply = true;
        applyTimer.restart();
    }

    function setAnimationProfile(profile) {
        if (profile === "material") root.reset(["shell:animationProfile"]);
        else root.setMany({ "shell:animationProfile": profile });
    }

    // Forget the changes made here for these options and go back to the config files
    function reset(keys) {
        root.syncFromFile();
        let newOverrides = Object.assign({}, root.overrides);
        let changed = false;
        for (const key of keys) {
            if (newOverrides[key] === undefined) continue;
            delete newOverrides[key];
            changed = true;
        }
        if (!changed) return;
        root.overrides = newOverrides;
        root.reloadValuesAfterApply = true;
        applyTimer.restart();
    }

    function hasOverrides(keys) {
        return keys.some(key => root.isOverridden(key));
    }

    property bool reloadValuesAfterApply: false

    function luaValue(value) {
        if (typeof value === "boolean") return value ? "true" : "false";
        if (typeof value === "number") return Number.isInteger(value) ? value.toString() : value.toFixed(3);
        return `"${value.toString().replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
    }

    function luaKey(key) {
        return /^[A-Za-z_][A-Za-z0-9_]*$/.test(key) ? key : `["${key}"]`;
    }

    function buildLua() {
        // "decoration:blur:size" -> { decoration = { blur = { size = ... } } }
        let tree = {};
        for (const key of Object.keys(root.overrides).sort()) {
            if (key.startsWith("shell:")) continue;
            const path = key.split(":");
            let node = tree;
            for (let i = 0; i < path.length - 1; i++) {
                node[path[i]] = node[path[i]] ?? {};
                node = node[path[i]];
            }
            node[path[path.length - 1]] = root.overrides[key];
        }
        const write = (node, indent) => {
            let lines = [];
            for (const name of Object.keys(node)) {
                const value = node[name];
                if (typeof value === "object") {
                    lines.push(`${indent}${root.luaKey(name)} = {`);
                    lines.push(...write(value, indent + "    "));
                    lines.push(`${indent}},`);
                } else {
                    lines.push(`${indent}${root.luaKey(name)} = ${root.luaValue(value)},`);
                }
            }
            return lines;
        };
        const body = write(tree, "    ");
        const profile = root.overrides["shell:animationProfile"];
        const profileLines = root.animationProfiles.includes(profile) && profile !== "material"
            ? ["", `pcall(require, "hyprland.animations.${profile}")`] : [];
        return [
            "-- Generated by the Velora settings app. Edits here are overwritten;",
            "-- put manual changes in custom/general.lua instead.",
            "",
            ...(body.length > 0 ? ["hl.config({", ...body, "})"] : []),
            ...profileLines,
            ""
        ].join("\n");
    }

    Timer {
        id: applyTimer
        interval: 450 // Lets sliders and spin boxes settle before reloading Hyprland
        onTriggered: {
            jsonFile.setText(JSON.stringify(root.overrides, null, 4) + "\n");
            luaFile.setText(root.buildLua());
            reloadProc.running = false;
            reloadProc.running = true;
        }
    }

    Process {
        id: reloadProc
        command: root.reloadCommand
        onExited: {
            if (root.reloadValuesAfterApply) {
                root.reloadValuesAfterApply = false;
                root.readValues();
            }
        }
    }

    FileView {
        id: jsonFile
        path: root.jsonPath
        blockLoading: true // Saved changes must be known before anything new is written
        watchChanges: true
        onFileChanged: if (!applyTimer.running) reload()
        onLoaded: if (!applyTimer.running) root.parseFile() // A late load must not undo pending changes
    }

    FileView {
        id: luaFile
        path: root.luaPath
    }

    function readValues() {
        readProc.command = ["hyprctl", "--batch", root.options.map(option => `j/getoption ${option}`).join(";")];
        readProc.running = true;
    }

    Process {
        id: readProc
        stdout: StdioCollector {
            id: readCollector
            onStreamFinished: {
                let newValues = {};
                const objects = readCollector.text.match(/\{[^{}]*\}/g) ?? [];
                for (const text of objects) {
                    try {
                        const entry = JSON.parse(text);
                        let value;
                        if (entry.int !== undefined) value = entry.int;
                        else if (entry.float !== undefined) value = Math.round(entry.float * 1000) / 1000;
                        else if (entry.bool !== undefined) value = entry.bool;
                        else if (entry.str !== undefined) value = entry.str === "[[EMPTY]]" ? "" : entry.str;
                        else if (entry.css !== undefined) value = parseInt(entry.css.split(" ")[0]); // gaps: "top right bottom left"
                        else if (entry.custom !== undefined) value = entry.custom;
                        if (value !== undefined) newValues[entry.option] = value;
                    } catch (e) {
                        // Options this Hyprland doesn't know are simply left out
                    }
                }
                root.values = newValues;
                root.ready = true;
            }
        }
    }

    // Other things (game mode, manual edits) can change options too
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && !applyTimer.running) root.readValues();
        }
    }

    Component.onCompleted: root.readValues()
}
