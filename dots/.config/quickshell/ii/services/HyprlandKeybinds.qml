pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Hyprland keybinds as the config describes them, and the user's changes to them.
 *
 * hypr/hyprland/keymap.lua writes every described bind to a JSON manifest on each config load,
 * so this always matches what's really bound. Changes made in the settings app are kept in
 * hypr/custom/keybind_overrides.json and written as Lua to keybind_overrides.lua, which the
 * keybinds read by id. Hyprland is then reloaded.
 */
Singleton {
    id: root

    readonly property string manifestPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/folis-keybinds.json`
    readonly property string overridesJsonPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybind_overrides.json`)
    readonly property string overridesLuaPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybind_overrides.lua`)
    readonly property string captureSubmap: "shortcut-capture"

    property var groups: []   // [{ id, name, icon }]
    property var binds: []    // [{ id, group, description, mods, key, default_mods, default_key, remappable, disabled, remapped, note, custom }]
    property var hiddenCombos: [] // Undescribed binds, normalized like KeyUtils.comboKey
    property bool ready: false
    property var activeRecorder: null // The ShortcutRecorder listening for keys, only one at a time
    property var bindMap: ({})       // uid -> bind, see uid()
    property var remap: ({})  // id -> { mods, key } or false
    property var custom: []   // [{ mods, key, description, app?, command? }]
    readonly property bool applying: saveTimer.running || reloadProc.running
    readonly property int changedCount: Object.keys(root.remap).length

    // Stable identity of a manifest entry, also for notes that have no id
    function uid(bind) {
        return bind.id ?? `${bind.group}:${bind.description}`;
    }

    function bindsInGroup(groupId) {
        return root.binds.filter(bind => bind.group === groupId);
    }

    // Enabled binds that use this combo, except the one with `exceptId`
    function conflicts(mods, key, exceptId) {
        const target = KeyUtils.comboKey(mods, key);
        return root.binds.filter(bind => !bind.disabled && !bind.note && bind.id !== exceptId
            && KeyUtils.comboKey(bind.mods, bind.key) === target);
    }

    // Whether a bind that isn't listed (no description) already uses this combo
    function hiddenConflict(mods, key) {
        return root.hiddenCombos.includes(KeyUtils.comboKey(mods, key));
    }

    function setRemap(id, value) {
        let newRemap = Object.assign({}, root.remap);
        if (value === undefined) delete newRemap[id];
        else newRemap[id] = value;
        root.remap = newRemap;
        root.save();
    }

    function rebind(id, mods, key) {
        const bind = root.binds.find(bind => bind.id === id);
        const isDefault = bind && KeyUtils.comboKey(mods, key) === KeyUtils.comboKey(bind.default_mods, bind.default_key);
        root.setRemap(id, isDefault ? undefined : { mods: KeyUtils.sortMods(mods).join("+"), key: key });
    }

    function disable(id) {
        root.setRemap(id, false);
    }

    function reset(id) {
        root.setRemap(id, undefined);
    }

    function resetAll() {
        root.remap = {};
        root.save();
    }

    function addCustom(shortcut) {
        root.custom = [...root.custom, shortcut];
        root.save();
    }

    function updateCustom(index, changes) {
        let newCustom = root.custom.slice();
        newCustom[index] = Object.assign({}, newCustom[index], changes);
        root.custom = newCustom;
        root.save();
    }

    function removeCustom(index) {
        root.custom = root.custom.filter((_, i) => i !== index);
        root.save();
    }

    // Index into `custom` of a manifest entry made from it ("custom:3" -> 2)
    function customIndex(bind) {
        const match = /^custom:(\d+)$/.exec(bind?.id ?? "");
        return match ? parseInt(match[1]) - 1 : -1;
    }

    // While recording a shortcut, keys must reach the app instead of running binds.
    // Hyprland returns to the normal keybinds by itself after 15 seconds.
    // Switches run one at a time, so a quick start/stop can't arrive in the wrong order.
    property bool captureWanted: false
    property bool captureApplied: false

    function startCapture() {
        root.captureWanted = true;
        root.applyCapture();
    }

    function endCapture() {
        root.captureWanted = false;
        root.applyCapture();
    }

    function applyCapture() {
        if (submapProc.running) return; // Picked up again when it exits
        const wanted = root.captureWanted;
        submapProc.command = ["hyprctl", "dispatch", `hl.dsp.submap("${wanted ? root.captureSubmap : "global"}")`];
        submapProc.applying = wanted;
        submapProc.running = true;
    }

    Process {
        id: submapProc
        property bool applying: false
        onExited: {
            root.captureApplied = submapProc.applying;
            if (root.captureApplied !== root.captureWanted) root.applyCapture();
        }
    }

    function luaString(value) {
        return `"${value.toString().replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
    }

    function buildLua() {
        let lines = [
            "-- Generated by the Velora settings app (Keyboard Shortcuts). Edits here are overwritten;",
            "-- put manual binds in custom/keybinds.lua instead.",
            "",
            "return {",
            "    remap = {"
        ];
        for (const id of Object.keys(root.remap).sort()) {
            const value = root.remap[id];
            if (value === false) lines.push(`        [${root.luaString(id)}] = false,`);
            else lines.push(`        [${root.luaString(id)}] = { mods = ${root.luaString(value.mods)}, key = ${root.luaString(value.key)} },`);
        }
        lines.push("    },", "    custom = {");
        for (const shortcut of root.custom) {
            let fields = [`mods = ${root.luaString(shortcut.mods ?? "")}`, `key = ${root.luaString(shortcut.key ?? "")}`,
                          `description = ${root.luaString(shortcut.description ?? "")}`];
            if (shortcut.app) fields.push(`app = ${root.luaString(shortcut.app)}`);
            if (shortcut.command) fields.push(`command = ${root.luaString(shortcut.command)}`);
            lines.push(`        { ${fields.join(", ")} },`);
        }
        lines.push("    },", "}", "");
        return lines.join("\n");
    }

    function save() {
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 150
        onTriggered: {
            overridesJson.setText(JSON.stringify({ remap: root.remap, custom: root.custom }, null, 4) + "\n");
            overridesLua.setText(root.buildLua());
            reloadProc.running = false;
            reloadProc.running = true;
        }
    }

    Process {
        id: reloadProc
        command: HyprlandSettings.reloadCommand
    }

    FileView {
        id: overridesJson
        path: root.overridesJsonPath
        blockLoading: true // Saved changes must be known before anything new is written
        onLoaded: {
            try {
                const data = JSON.parse(overridesJson.text());
                root.remap = data?.remap ?? {};
                root.custom = data?.custom ?? [];
            } catch (e) {
                console.warn("[HyprlandKeybinds] Couldn't parse", root.overridesJsonPath, e);
            }
        }
    }

    FileView {
        id: overridesLua
        path: root.overridesLuaPath
    }

    FileView {
        id: manifestFile
        path: root.manifestPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(manifestFile.text());
                root.groups = data.groups ?? [];
                root.binds = data.binds ?? [];
                let map = {};
                for (const bind of root.binds) map[root.uid(bind)] = bind;
                root.bindMap = map;
                root.hiddenCombos = (data.hidden ?? []).map(combo => KeyUtils.normalizeComboString(combo));
                root.ready = true;
            } catch (e) {
                console.warn("[HyprlandKeybinds] Couldn't parse", root.manifestPath, e);
            }
        }
    }
}
