pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell

/**
 * Where each part of the lock screen is (modules/common/LockElementCatalog.qml), and edits to it.
 * Config.options.lock.layout = { version: 1, items: { <id>: { show, x, y, size, attach } } }, or null for the
 * built-in arrangement, which also follows the older lock.* switches.
 *   x, y    where the middle of the part is, as fractions of the screen (so any screen size works)
 *   size    scale of a scalable part
 *   attach  "password": sits next to the password field (user, power on its sides, message above it)
 * Edits replace the whole object: JsonAdapter only saves a `var` property when it is assigned.
 * Used by the lock screen, the full-size editor and the settings app.
 */
Singleton {
    id: root

    readonly property var options: Config.options.lock
    // Published only when the content changes, not on every config reload
    readonly property string revision: JSON.stringify(root.normalize(root.options.layout))
    readonly property var items: JSON.parse(root.revision).items
    readonly property bool isCustom: root.options.layout !== null && root.options.layout !== undefined

    property list<var> undoStack: []
    readonly property bool canUndo: root.undoStack.length > 0

    // The built-in arrangement, from the older switches
    function builtin() {
        const lock = root.options;
        return {
            "clock": { "show": true, "x": 0.5, "y": lock.centerClock ? 0.5 : 0.3, "size": 1 },
            "greeting": { "show": false, "x": 0.5, "y": 0.2, "size": 1 },
            "password": { "show": true, "x": 0.5, "y": lock.passwordPosition === "center" ? 0.68 : 0.955, "size": 1 },
            "user": { "show": lock.showUser || lock.showKeyboardLayout, "attach": "password", "x": 0.3, "y": 0.955, "size": 1 },
            "power": { "show": lock.showBattery || lock.showPowerButtons, "attach": "password", "x": 0.7, "y": 0.955, "size": 1 },
            "message": { "show": true, "attach": "password", "x": 0.5, "y": 0.88, "size": 1 },
            "media": { "show": lock.showMedia, "x": 0.83, "y": 0.13, "size": 1 },
            "weather": { "show": lock.showWeather, "x": 0.12, "y": 0.1, "size": 1 },
            "notifications": { "show": false, "x": 0.5, "y": 0.85, "size": 1 },
            "timer": { "show": false, "x": 0.88, "y": 0.3, "size": 1 }
        };
    }

    function clamp(value, low, high) {
        return Math.max(low, Math.min(high, value));
    }

    // Fills in what a layout leaves out, so the lock screen and editors can rely on every key
    function normalize(layout) {
        const base = root.builtin();
        const given = layout?.items ?? {};
        let items = {};
        for (const id of LockElementCatalog.ids) {
            const item = Object.assign({}, base[id], given[id] ?? {});
            item.x = root.clamp(Number(item.x) || 0, 0, 1);
            item.y = root.clamp(Number(item.y) || 0, 0, 1);
            item.size = root.clamp(Number(item.size) || 1, 0.5, 2);
            item.show = id === "password" ? true : !!item.show;
            item.attach = LockElementCatalog.get(id).attachable ? (item.attach ?? "") : "";
            items[id] = item;
        }
        return { "version": 1, "items": items };
    }

    function clone(object) {
        return JSON.parse(JSON.stringify(object));
    }

    function write(layout) {
        const previous = root.options.layout;
        root.undoStack = [...root.undoStack, previous ? root.clone(previous) : null].slice(-50);
        Config.options.lock.layout = layout === null ? null : root.clone(layout);
    }

    function undo() {
        if (root.undoStack.length === 0) return;
        const previous = root.undoStack[root.undoStack.length - 1];
        root.undoStack = root.undoStack.slice(0, -1);
        Config.options.lock.layout = previous;
    }

    function setItem(id, patch) {
        let layout = root.normalize(root.options.layout);
        Object.assign(layout.items[id], patch);
        root.write(layout);
    }

    // Puts a part's middle at (x, y); a part that was stuck to the password field comes loose
    function move(id, x, y) {
        root.setItem(id, { "x": root.clamp(x, 0, 1), "y": root.clamp(y, 0, 1), "attach": "" });
    }

    function setShown(id, shown) {
        root.setItem(id, { "show": shown });
    }

    function setSize(id, size) {
        root.setItem(id, { "size": root.clamp(size, 0.5, 2) });
    }

    function setAttached(id, attached) {
        root.setItem(id, { "attach": attached ? "password" : "" });
    }

    // Back to where the built-in arrangement has it, keeping whether it's shown
    function resetItem(id) {
        const base = root.builtin()[id];
        root.setItem(id, { "x": base.x, "y": base.y, "size": base.size, "attach": base.attach ?? "" });
    }

    function reset() {
        root.write(null);
    }

    // Ready-made arrangements. Each moves the parts it names; `show` is only set where the arrangement needs it.
    readonly property list<var> presets: [
        { "id": "center", "name": Translation.tr("Centered"), "icon": "align_center", "items": {
            "clock": { "show": true, "x": 0.5, "y": 0.5, "size": 1 },
            "greeting": { "x": 0.5, "y": 0.2 },
            "password": { "x": 0.5, "y": 0.955 },
            "user": { "attach": "password" }, "power": { "attach": "password" }, "message": { "attach": "password" },
            "media": { "x": 0.83, "y": 0.13 }, "weather": { "x": 0.12, "y": 0.1 },
            "notifications": { "x": 0.5, "y": 0.85 }, "timer": { "x": 0.88, "y": 0.3 } } },
        { "id": "left", "name": Translation.tr("On the left"), "icon": "align_horizontal_left", "items": {
            "clock": { "show": true, "x": 0.2, "y": 0.36, "size": 1 },
            "greeting": { "x": 0.2, "y": 0.12 },
            "password": { "x": 0.2, "y": 0.66 },
            "user": { "attach": "", "x": 0.14, "y": 0.75 }, "power": { "attach": "", "x": 0.15, "y": 0.955 },
            "message": { "attach": "password" },
            "media": { "x": 0.8, "y": 0.86 }, "weather": { "x": 0.88, "y": 0.1 },
            "notifications": { "x": 0.2, "y": 0.84 }, "timer": { "x": 0.88, "y": 0.22 } } },
        { "id": "journal", "name": Translation.tr("Dashboard"), "icon": "dashboard", "items": {
            "clock": { "show": true, "x": 0.27, "y": 0.42, "size": 1.3 },
            "greeting": { "show": true, "x": 0.27, "y": 0.13 },
            "password": { "x": 0.5, "y": 0.955 },
            "user": { "attach": "password" }, "power": { "attach": "password" }, "message": { "attach": "password" },
            "weather": { "show": true, "x": 0.73, "y": 0.22 },
            "media": { "show": true, "x": 0.73, "y": 0.45 },
            "notifications": { "show": true, "x": 0.73, "y": 0.63 },
            "timer": { "x": 0.73, "y": 0.74 } } },
        { "id": "bottom", "name": Translation.tr("Down below"), "icon": "align_vertical_bottom", "items": {
            "clock": { "show": true, "x": 0.17, "y": 0.78, "size": 1 },
            "greeting": { "x": 0.17, "y": 0.55 },
            "password": { "x": 0.76, "y": 0.9 },
            "user": { "attach": "", "x": 0.06, "y": 0.06 }, "power": { "attach": "", "x": 0.93, "y": 0.06 },
            "message": { "attach": "password" },
            "media": { "x": 0.76, "y": 0.72 }, "weather": { "x": 0.5, "y": 0.06 },
            "notifications": { "x": 0.76, "y": 0.58 }, "timer": { "x": 0.5, "y": 0.16 } } },
        { "id": "minimal", "name": Translation.tr("Minimal"), "icon": "check_box_outline_blank", "items": {
            "clock": { "show": true, "x": 0.5, "y": 0.42, "size": 1.15 },
            "greeting": { "show": false }, "password": { "x": 0.5, "y": 0.72 },
            "user": { "show": false, "attach": "password" }, "power": { "show": false, "attach": "password" },
            "message": { "attach": "password" },
            "media": { "show": false }, "weather": { "show": false }, "notifications": { "show": false }, "timer": { "show": false } } }
    ]

    function applyPreset(presetId) {
        const preset = root.presets.find(p => p.id === presetId);
        if (!preset) return;
        let layout = root.normalize(root.options.layout);
        for (const id of Object.keys(preset.items)) Object.assign(layout.items[id], preset.items[id]);
        root.write(layout);
    }

    // What the layout would be with a preset applied, for drawing it
    function previewItems(presetId) {
        const preset = root.presets.find(p => p.id === presetId);
        let layout = root.normalize(root.options.layout);
        for (const id of Object.keys(preset?.items ?? {})) Object.assign(layout.items[id], preset.items[id]);
        return root.normalize(layout).items;
    }

    // Whether the layout is a preset as it is: that one is shown as chosen
    function matchesPreset(presetId) {
        const preset = root.presets.find(p => p.id === presetId);
        if (!preset) return false;
        for (const id of Object.keys(preset.items)) {
            const want = preset.items[id];
            const have = root.items[id];
            for (const key of Object.keys(want)) {
                if (key === "show" && want.show !== have.show) return false;
                if ((key === "x" || key === "y" || key === "size") && Math.abs(want[key] - have[key]) > 0.005) return false;
                if (key === "attach" && (want.attach ?? "") !== (have.attach ?? "")) return false;
            }
        }
        return true;
    }

    // ---- Shell only: where each screen's desktop clock is, so the lock clock can glide from there ----
    property var desktopClocks: ({})
    function setDesktopClock(screenName, rect) {
        root.desktopClocks[screenName] = rect; // Not a binding source on purpose: read once when locking
    }
}
