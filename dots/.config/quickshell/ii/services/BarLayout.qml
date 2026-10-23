pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * The bar layouts in effect (custom from the config, or built-in) and the edits made to them.
 * Edits always replace the whole layout object in the config: JsonAdapter only saves a `var`
 * property when it is assigned. Used by the shell and the settings app alike.
 */
Singleton {
    id: root

    readonly property list<string> zoneNames: BarLayoutDefaults.zoneNames

    // Published only when the content changes, not on every config reload
    readonly property string horizontalRevision: JSON.stringify(normalize(Config.options.bar.layout, BarLayoutDefaults.horizontal))
    readonly property string verticalRevision: JSON.stringify(normalize(Config.options.bar.verticalLayout, BarLayoutDefaults.vertical))
    readonly property var horizontal: JSON.parse(horizontalRevision)
    readonly property var vertical: JSON.parse(verticalRevision)

    readonly property bool horizontalIsCustom: Config.options.bar.layout !== null && Config.options.bar.layout !== undefined
    readonly property bool verticalIsCustom: Config.options.bar.verticalLayout !== null && Config.options.bar.verticalLayout !== undefined

    property list<var> undoStack: []
    readonly property bool canUndo: undoStack.length > 0

    // Names of the parts of the bar for editors: full title, a short label and an icon
    function zoneInfo(orientation) {
        const vertical = orientation === "vertical";
        return [
            { "zone": "start", "title": vertical ? Translation.tr("Top") : Translation.tr("Left edge"),
              "short": vertical ? Translation.tr("Top") : Translation.tr("Left"), "icon": vertical ? "vertical_align_top" : "align_horizontal_left" },
            { "zone": "centerStart", "title": vertical ? Translation.tr("Above center") : Translation.tr("Left of center"),
              "short": vertical ? "↑" : "←", "icon": vertical ? "arrow_upward" : "arrow_back" },
            { "zone": "center", "title": Translation.tr("Center"),
              "short": Translation.tr("Center"), "icon": vertical ? "align_vertical_center" : "align_horizontal_center" },
            { "zone": "centerEnd", "title": vertical ? Translation.tr("Below center") : Translation.tr("Right of center"),
              "short": vertical ? "↓" : "→", "icon": vertical ? "arrow_downward" : "arrow_forward" },
            { "zone": "end", "title": vertical ? Translation.tr("Bottom") : Translation.tr("Right edge"),
              "short": vertical ? Translation.tr("Bottom") : Translation.tr("Right"), "icon": vertical ? "vertical_align_bottom" : "align_horizontal_right" },
        ];
    }

    function configKey(orientation) {
        return orientation === "vertical" ? "verticalLayout" : "layout";
    }

    function current(orientation) {
        return orientation === "vertical" ? root.vertical : root.horizontal;
    }

    function newUid(type) {
        return `${type}-${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;
    }

    // Fills in what a layout may leave out, so the renderer and editors can rely on it
    function normalize(layout, fallback) {
        const source = (layout && typeof layout === "object" && layout.zones) ? layout : fallback;
        let zones = {};
        let usedUids = new Set();
        for (const zone of root.zoneNames) {
            zones[zone] = (source.zones?.[zone] ?? []).filter(item => item && typeof item.type === "string").map((item, index) => {
                let copy = Object.assign({}, item);
                // Deterministic, so a layout without uids doesn't look changed on every reload
                if (!copy.uid || usedUids.has(copy.uid)) copy.uid = `${copy.type}-${zone}-${index}`;
                usedUids.add(copy.uid);
                return copy;
            });
        }
        let actions = {};
        for (const zone of root.zoneNames) {
            if (source.actions?.[zone]) actions[zone] = Object.assign({}, source.actions[zone]);
        }
        return {
            "version": 1,
            "balanceCenter": source.balanceCenter ?? false,
            "actions": actions,
            "zones": zones
        };
    }

    function clone(layout) {
        return JSON.parse(JSON.stringify(layout));
    }

    function find(layout, uid) {
        for (const zone of root.zoneNames) {
            const index = layout.zones[zone].findIndex(item => item.uid === uid);
            if (index >= 0) return { "zone": zone, "index": index, "item": layout.zones[zone][index] };
        }
        return null;
    }

    function write(orientation, layout) {
        const key = root.configKey(orientation);
        const previous = Config.options.bar[key];
        root.undoStack = [...root.undoStack, { "orientation": orientation, "layout": previous ? root.clone(previous) : null }].slice(-50);
        Config.options.bar[key] = layout === null ? null : root.clone(layout);
    }

    function undo() {
        if (root.undoStack.length === 0) return;
        const entry = root.undoStack[root.undoStack.length - 1];
        root.undoStack = root.undoStack.slice(0, -1);
        Config.options.bar[root.configKey(entry.orientation)] = entry.layout;
    }

    // Moves an item to `index` of `zone` (index counted without the item itself)
    function move(orientation, uid, zone, index) {
        let layout = root.clone(root.current(orientation));
        const found = root.find(layout, uid);
        if (!found) return;
        layout.zones[found.zone].splice(found.index, 1);
        const target = layout.zones[zone];
        target.splice(Math.max(0, Math.min(index, target.length)), 0, found.item);
        root.write(orientation, layout);
    }

    // Where a widget added without a position goes: the side of the zone nearest the center.
    // In the end zone that is just after its flexible space, so it joins the group at the edge.
    function defaultIndex(items, zone) {
        if (zone !== "end") return items.length;
        const spacer = items.findIndex(item => item.type === "spacer");
        return spacer >= 0 ? spacer + 1 : 0;
    }

    function insert(orientation, type, zone, index, extra = {}) {
        let layout = root.clone(root.current(orientation));
        // A new widget starts with its own options at their defaults, so it shows something right away
        let options = {};
        for (const spec of (BarWidgetCatalog.get(type)?.options ?? [])) {
            if (spec.scope === "instance" && spec.default !== undefined) options[spec.key] = spec.default;
        }
        Object.assign(options, extra.options ?? {});
        const item = Object.assign({ "uid": root.newUid(type), "type": type }, BarWidgetCatalog.get(type)?.defaults ?? {}, extra);
        if (Object.keys(options).length > 0) item.options = options;
        const target = layout.zones[zone];
        target.splice(index < 0 ? root.defaultIndex(target, zone) : Math.min(index, target.length), 0, item);
        root.write(orientation, layout);
        if (type === "weather") Config.options.bar.weather.enable = true;
        return item.uid;
    }

    function remove(orientation, uid) {
        let layout = root.clone(root.current(orientation));
        const found = root.find(layout, uid);
        if (!found) return;
        layout.zones[found.zone].splice(found.index, 1);
        root.write(orientation, layout);
    }

    // Changes pill, pillBreak, hideAt, fill or options of one item; null removes a key
    function setItem(orientation, uid, patch) {
        let layout = root.clone(root.current(orientation));
        const found = root.find(layout, uid);
        if (!found) return;
        for (const key of Object.keys(patch)) {
            if (patch[key] === null || patch[key] === undefined) delete found.item[key];
            else found.item[key] = patch[key];
        }
        root.write(orientation, layout);
    }

    // Island mode: whether a widget sits in a card of its own instead of sharing one with its neighbours
    function isOwnIsland(orientation, uid) {
        const found = root.find(root.current(orientation), uid);
        if (!found) return false;
        const segment = BarLayoutUtils.segments(root.current(orientation).zones[found.zone], true)
            .find(segment => segment.items.some(item => item.uid === uid));
        return (segment?.items.length ?? 0) === 1;
    }

    // Island mode: a card of its own starts at the widget and ends right after it (see BarLayoutUtils.segments)
    function setOwnIsland(orientation, uid, own) {
        let layout = root.clone(root.current(orientation));
        const found = root.find(layout, uid);
        if (!found) return;
        const next = layout.zones[found.zone][found.index + 1];
        if (own) found.item.pillBreak = true;
        else delete found.item.pillBreak;
        if (next && next.type !== "spacer") {
            if (own) next.pillBreak = true;
            else delete next.pillBreak;
        }
        root.write(orientation, layout);
    }

    function setOption(orientation, uid, key, value) {
        const found = root.find(root.current(orientation), uid);
        if (!found) return;
        let options = Object.assign({}, found.item.options ?? {});
        options[key] = value;
        root.setItem(orientation, uid, { "options": options });
    }

    // Writes a shared setting named by a catalog option scope ("path:bar.workspaces.shown")
    function setPathValue(path, value) {
        let patch = {};
        let node = patch;
        const keys = path.split(".");
        for (let i = 0; i < keys.length - 1; i++) {
            node[keys[i]] = {};
            node = node[keys[i]];
        }
        node[keys[keys.length - 1]] = value;
        Config.applyPatch(patch);
    }

    function setOptionValue(orientation, uid, spec, value) {
        if (spec.scope === "instance") root.setOption(orientation, uid, spec.key, value);
        else root.setPathValue(spec.scope.slice(5), value);
    }

    function setActions(orientation, zone, actions) {
        let layout = root.clone(root.current(orientation));
        layout.actions[zone] = Object.assign({}, layout.actions[zone] ?? {}, actions);
        root.write(orientation, layout);
    }

    function setBalanceCenter(orientation, balance) {
        let layout = root.clone(root.current(orientation));
        layout.balanceCenter = balance;
        root.write(orientation, layout);
    }

    function reset(orientation) {
        root.write(orientation, null);
    }

    function apply(orientation, layout) {
        root.write(orientation, root.normalize(layout, BarLayoutDefaults[orientation === "vertical" ? "vertical" : "horizontal"]));
    }

    // Commands a layout would run (custom command and app widgets), shown before importing
    function commandsIn(layout) {
        let commands = [];
        for (const zone of root.zoneNames) {
            for (const item of (layout?.zones?.[zone] ?? [])) {
                for (const key of ["command", "clickCommand", "middleClickCommand", "scrollUpCommand", "scrollDownCommand"]) {
                    const command = item.options?.[key];
                    if (typeof command === "string" && command.trim().length > 0) commands.push(command);
                }
            }
        }
        return commands;
    }

    function exportText(orientation) {
        return JSON.stringify(root.current(orientation), null, 4);
    }

    // Parses a layout from text; returns { layout, commands } or { error }
    function parse(text) {
        let layout;
        try {
            layout = JSON.parse(text);
        } catch (e) {
            return { "error": Translation.tr("Not valid JSON") };
        }
        if (!layout || typeof layout !== "object" || !layout.zones || typeof layout.zones !== "object")
            return { "error": Translation.tr("This is not a bar layout") };
        const normalized = root.normalize(layout, BarLayoutDefaults.horizontal);
        return { "layout": normalized, "commands": root.commandsIn(normalized) };
    }
}
