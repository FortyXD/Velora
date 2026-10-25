pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell

/**
 * How the sidebars are put together (Config.options.sidebar.{left,right}.parts), for the sidebars and the
 * settings app: both sidebars as lists of parts, and edits to them with undo. A part is
 *   { uid, type, hidden, options }, a "tabs" part also has tabs: [{ uid, type, hidden, swipeOnly, options }]
 * (see SidebarCatalog for the types). Without `parts` a sidebar is made from the settings older versions had.
 * Lists are always replaced as a whole: JsonAdapter doesn't notice changes made inside a list.
 */
Singleton {
    id: root

    readonly property var options: Config.options.sidebar
    readonly property list<string> sides: ["right", "left"]

    // Both sidebars, cleaned up together: a part allowed once in the shell stays where it's met first,
    // the right sidebar before the left. Compared as text, so lists only change when their content does.
    readonly property string revision: JSON.stringify(root.normalizeBoth(root.given("right"), root.given("left")))
    readonly property var layouts: JSON.parse(root.revision)
    readonly property var right: root.layouts.right
    readonly property var left: root.layouts.left

    // The saved list as plain JavaScript (the config hands lists over as its own array type), or null
    function saved(side) {
        const parts = Config.options.sidebar[side].parts;
        if (parts === null || parts === undefined) return null;
        const plain = JSON.parse(JSON.stringify(parts));
        return Array.isArray(plain) ? plain : null;
    }
    function given(side) {
        return root.saved(side) ?? SidebarLayoutDefaults.legacy(side);
    }
    function isCustom(side) {
        return root.saved(side) !== null;
    }

    function normalizeBoth(rightParts, leftParts) {
        let usedShell = {};
        let usedUids = {};
        let result = {};
        for (const side of root.sides) {
            let usedHere = {};
            result[side] = [];
            (side === "right" ? rightParts : leftParts ?? []).forEach((part, index) => {
                const clean = root.cleanPart(part, side, `${index}`, usedShell, usedHere, usedUids, false);
                if (clean) result[side].push(clean);
            });
        }
        return result;
    }

    function cleanPart(part, side, position, usedShell, usedHere, usedUids, inTabs) {
        const meta = SidebarCatalog.part(part?.type);
        if (!meta || (inTabs && !meta.tabbable)) return null;
        if (meta.limit === "shell") {
            if (usedShell[part.type]) return null;
            usedShell[part.type] = true;
        } else if (meta.limit === "sidebar") {
            if (usedHere[part.type]) return null;
            usedHere[part.type] = true;
        }
        let uid = (typeof part.uid === "string" && part.uid.length > 0) ? part.uid : `${part.type}-${side}-${position}`;
        while (usedUids[uid]) uid += "_";
        usedUids[uid] = true;
        let clean = { "uid": uid, "type": part.type, "hidden": !!part.hidden,
            "options": (part.options && typeof part.options === "object") ? JSON.parse(JSON.stringify(part.options)) : {} };
        if (inTabs) clean.swipeOnly = !!part.swipeOnly;
        if (part.type === "tabs") {
            clean.tabs = [];
            (part.tabs ?? []).forEach((tab, index) => {
                const cleanTab = root.cleanPart(tab, side, `${position}-${index}`, usedShell, usedHere, usedUids, true);
                if (cleanTab) clean.tabs.push(cleanTab);
            });
        }
        return clean;
    }

    // ---- Reading ----

    function parts(side) {
        return root.layouts[side] ?? [];
    }

    // Where a part is: { side, index, group (the tabs part it's a page of, or null), part }
    function find(uid, layouts = root.layouts) {
        for (const side of root.sides) {
            const list = layouts[side] ?? [];
            for (let i = 0; i < list.length; i++) {
                if (list[i].uid === uid) return { "side": side, "index": i, "group": null, "part": list[i] };
                for (let j = 0; j < (list[i].tabs ?? []).length; j++) {
                    if (list[i].tabs[j].uid === uid) return { "side": side, "index": j, "group": list[i], "part": list[i].tabs[j] };
                }
            }
        }
        return null;
    }
    function findType(type, layouts = root.layouts) {
        for (const side of root.sides) {
            for (const part of layouts[side] ?? []) {
                if (part.type === type) return { "side": side, "group": null, "part": part };
                const tab = (part.tabs ?? []).find(tab => tab.type === type);
                if (tab) return { "side": side, "group": part, "part": tab };
            }
        }
        return null;
    }

    // Turned off elsewhere: the assistant and the image browser by their policies, sliders without any slider
    function allowed(type) {
        const policy = SidebarCatalog.part(type)?.policy;
        if (policy === "ai") return Config.options.policies.ai !== 0;
        if (policy === "weeb") return Config.options.policies.weeb !== 0;
        if (type === "sliders") {
            const sliders = root.options.quickSliders;
            return sliders.showBrightness || sliders.showVolume || sliders.showMic;
        }
        return true;
    }
    function shown(part) {
        if (!part || part.hidden || !root.allowed(part.type)) return false;
        return part.type !== "tabs" || (part.tabs ?? []).some(tab => root.shown(tab));
    }
    function shownParts(side) {
        return root.parts(side).filter(part => root.shown(part));
    }
    // Shown somewhere, also as a page of tabs
    function uses(type) {
        const found = root.findType(type);
        return found !== null && root.shown(found.part) && (found.group === null || root.shown(found.group));
    }
    function sideOf(type) {
        return root.uses(type) ? root.findType(type).side : "";
    }

    // The value of one of a part's options (SidebarCatalog parts[type].options)
    function optionValue(part, spec) {
        if ((spec.scope ?? "").startsWith("path:")) return Config.getNestedValue(`sidebar.${spec.scope.slice(5).replace(/^sidebar\./, "")}`, spec.default);
        const value = part?.options?.[spec.key];
        return value === undefined ? spec.default : value;
    }
    // All of a part's options with defaults filled in
    function optionsOf(part) {
        let result = Object.assign({}, part?.options ?? {});
        for (const spec of SidebarCatalog.part(part?.type)?.options ?? []) result[spec.key] = root.optionValue(part, spec);
        return result;
    }

    // ---- Editing ----

    property list<var> undoStack: []
    readonly property bool canUndo: root.undoStack.length > 0

    function copyLayouts() {
        return JSON.parse(root.revision);
    }
    function write(changes) {
        let stack = [...root.undoStack, JSON.stringify({ "right": Config.options.sidebar.right.parts ?? null, "left": Config.options.sidebar.left.parts ?? null })];
        root.undoStack = stack.slice(-50);
        for (const side of root.sides) {
            if (changes[side] !== undefined) Config.options.sidebar[side].parts = JSON.parse(JSON.stringify(changes[side]));
        }
    }
    function undo() {
        if (!root.canUndo) return;
        const previous = JSON.parse(root.undoStack[root.undoStack.length - 1]);
        root.undoStack = root.undoStack.slice(0, -1);
        Config.options.sidebar.right.parts = previous.right;
        Config.options.sidebar.left.parts = previous.left;
    }

    function newUid(type) {
        return `${type}-${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;
    }
    function insertAt(list, item, index) {
        list.splice(index < 0 ? list.length : Math.min(index, list.length), 0, item);
    }
    // Takes a part out of `layouts`; returns it, or null
    function detach(layouts, uid) {
        const found = root.find(uid, layouts);
        if (!found) return null;
        (found.group ? found.group.tabs : layouts[found.side]).splice(found.index, 1);
        return found.part;
    }

    // Adds a part; one that may exist once and already does is moved here instead. Returns its uid.
    function insert(side, type, index = -1, groupUid = "") {
        const meta = SidebarCatalog.part(type);
        if (!meta) return "";
        const existing = root.findType(type);
        if (existing && meta.limit === "shell") {
            root.move(existing.part.uid, side, index, groupUid);
            return existing.part.uid;
        }
        if (existing && meta.limit === "sidebar" && existing.side === side) return existing.part.uid;
        let layouts = root.copyLayouts();
        let part = { "uid": root.newUid(type), "type": type, "hidden": false, "options": {} };
        if (type === "tabs") {
            part.tabs = [];
            part.options = { "style": "bar" };
        }
        if (groupUid.length > 0) {
            const group = layouts[side].find(p => p.uid === groupUid);
            if (!group || !meta.tabbable) return "";
            root.insertAt(group.tabs, part, index);
        } else {
            root.insertAt(layouts[side], part, index);
        }
        root.write(layouts);
        if (!root.allowed(type)) root.allow(type);
        return part.uid;
    }

    // Moves a part to `index` of a sidebar, or into the tabs part `groupUid`
    function move(uid, side, index, groupUid = "") {
        let layouts = root.copyLayouts();
        const part = root.detach(layouts, uid);
        if (!part) return;
        if (groupUid.length > 0) {
            const group = layouts[side].find(p => p.uid === groupUid);
            if (!group || !SidebarCatalog.part(part.type)?.tabbable) return;
            delete part.tabs;
            root.insertAt(group.tabs, part, index);
        } else {
            delete part.swipeOnly;
            root.insertAt(layouts[side], part, index);
        }
        root.write(layouts);
    }
    function moveBy(uid, offset) {
        const found = root.find(uid);
        if (!found) return;
        const length = found.group ? found.group.tabs.length : root.parts(found.side).length;
        const target = Math.max(0, Math.min(length - 1, found.index + offset));
        if (target !== found.index) root.move(uid, found.side, target, found.group?.uid ?? "");
    }
    function moveToOtherSide(uid) {
        const found = root.find(uid);
        if (found) root.move(uid, found.side === "left" ? "right" : "left", -1);
    }
    // Takes a page out of its tabs and puts it right after them
    function takeOutOfTabs(uid) {
        const found = root.find(uid);
        if (!found?.group) return;
        root.move(uid, found.side, root.parts(found.side).findIndex(p => p.uid === found.group.uid) + 1);
    }
    function remove(uid) {
        let layouts = root.copyLayouts();
        if (root.detach(layouts, uid)) root.write(layouts);
    }

    function setField(uid, field, value) {
        let layouts = root.copyLayouts();
        const found = root.find(uid, layouts);
        if (!found) return;
        found.part[field] = value;
        root.write(layouts);
    }
    function setHidden(uid, hidden) {
        const found = root.find(uid);
        if (!found) return;
        root.setField(uid, "hidden", hidden);
        if (!hidden && !root.allowed(found.part.type)) root.allow(found.part.type);
    }
    // Showing a part that is turned off elsewhere turns it back on there
    function allow(type) {
        const policy = SidebarCatalog.part(type)?.policy;
        if (policy === "ai" && Config.options.policies.ai === 0) Config.options.policies.ai = 1;
        if (policy === "weeb" && Config.options.policies.weeb === 0) Config.options.policies.weeb = 1;
        if (type === "sliders" && !root.allowed("sliders")) {
            Config.options.sidebar.quickSliders.showBrightness = true;
            Config.options.sidebar.quickSliders.showVolume = true;
        }
        if (type === "sliders") Config.options.sidebar.quickSliders.enable = true;
    }

    function setOption(uid, spec, value) {
        if ((spec.scope ?? "").startsWith("path:")) {
            Config.setNestedValue(`sidebar.${spec.scope.slice(5).replace(/^sidebar\./, "")}`, value);
            return;
        }
        let layouts = root.copyLayouts();
        const found = root.find(uid, layouts);
        if (!found) return;
        found.part.options = Object.assign({}, found.part.options ?? {}, { [spec.key]: value });
        root.write(layouts);
    }
    function setOptionKey(uid, key, value) {
        root.setOption(uid, { "key": key }, value);
    }

    function reset(side) {
        root.write({ [side]: SidebarLayoutDefaults.forSide(side) });
    }

    // ---- Remembered tabs ----

    function tabState(uid) {
        const all = Persistent.states.sidebar.tabs ?? {};
        if (all[uid]) return all[uid];
        // Where older versions remembered them
        if (uid === "tabs-right") return { "index": Persistent.states.sidebar.bottomGroup.tab, "collapsed": Persistent.states.sidebar.bottomGroup.collapsed };
        if (uid === "tabs-left") return { "index": Persistent.states.sidebar.leftTab };
        return {};
    }
    function setTabState(uid, patch) {
        let all = Object.assign({}, Persistent.states.sidebar.tabs ?? {});
        all[uid] = Object.assign({}, root.tabState(uid), patch);
        Persistent.states.sidebar.tabs = all;
    }

    // ---- Quick toggles (Android style) ----

    function androidToggles() {
        return (root.options.quickToggles.android.toggles ?? []).filter(t => t && t.type).map(t => ({ "type": t.type, "size": t.size === 2 ? 2 : 1 }));
    }

    function setAndroidToggles(list) {
        Config.options.sidebar.quickToggles.android.toggles = list;
    }

    function hasAndroidToggle(type) {
        return root.androidToggles().some(t => t.type === type);
    }

    function addAndroidToggle(type, index = -1) {
        if (root.hasAndroidToggle(type)) return;
        let list = root.androidToggles();
        list.splice(index < 0 ? list.length : Math.min(index, list.length), 0, { "type": type, "size": 1 });
        root.setAndroidToggles(list);
    }

    function removeAndroidToggle(type) {
        root.setAndroidToggles(root.androidToggles().filter(t => t.type !== type));
    }

    function toggleAndroidToggle(type) {
        if (root.hasAndroidToggle(type)) root.removeAndroidToggle(type);
        else root.addAndroidToggle(type);
    }

    function resizeAndroidToggle(type) {
        root.setAndroidToggles(root.androidToggles().map(t => t.type === type ? { "type": t.type, "size": 3 - t.size } : t));
    }

    function moveAndroidToggle(type, index) {
        let list = root.androidToggles();
        const from = list.findIndex(t => t.type === type);
        if (from < 0) return;
        const [moving] = list.splice(from, 1);
        list.splice(Math.max(0, Math.min(index, list.length)), 0, moving);
        root.setAndroidToggles(list);
    }

    function moveAndroidToggleBy(type, offset) {
        const index = root.androidToggles().findIndex(t => t.type === type);
        if (index >= 0) root.moveAndroidToggle(type, index + offset);
    }

    // ---- Quick toggles (classic style) ----

    function classicToggles() {
        return (root.options.quickToggles.classic.toggles ?? []).filter(type => SidebarCatalog.toggle(type)?.classic);
    }

    function toggleClassicToggle(type) {
        const list = root.classicToggles();
        Config.options.sidebar.quickToggles.classic.toggles = list.includes(type) ? list.filter(t => t !== type) : [...list, type];
    }

    function moveClassicToggle(type, index) {
        let list = root.classicToggles().filter(t => t !== type);
        list.splice(Math.max(0, Math.min(index, list.length)), 0, type);
        Config.options.sidebar.quickToggles.classic.toggles = list;
    }

    // ---- Lists of names (widget tabs, header buttons, left tabs) ----

    function toggleInList(path, value) {
        const list = root.listAt(path);
        root.setList(path, list.includes(value) ? list.filter(v => v !== value) : [...list, value]);
    }

    function moveInList(path, value, index) {
        let list = root.listAt(path).filter(v => v !== value);
        list.splice(Math.max(0, Math.min(index, list.length)), 0, value);
        root.setList(path, list);
    }

    function listAt(path) {
        let node = Config.options;
        for (const key of path.split(".")) node = node[key];
        return [...(node ?? [])];
    }

    function setList(path, list) {
        const keys = path.split(".");
        let node = Config.options;
        for (const key of keys.slice(0, -1)) node = node[key];
        node[keys[keys.length - 1]] = list;
    }
}
