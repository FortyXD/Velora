pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell

/**
 * Edits to how the sidebars are put together (Config.options.sidebar), for the sidebars' own edit mode
 * and the settings app. Lists are always replaced as a whole: JsonAdapter doesn't notice changes made
 * inside a list, like the size of one toggle.
 */
Singleton {
    id: root

    readonly property var options: Config.options.sidebar

    // ---- Right sidebar sections ----

    // The sections in order, header first, every known one present once
    readonly property var sections: {
        const given = (root.options.right.sections ?? []).filter(s => SidebarCatalog.section(s?.type));
        let result = [{ "type": "header", "hidden": !!given.find(s => s.type === "header")?.hidden }];
        for (const s of given) {
            if (s.type !== "header" && !result.some(r => r.type === s.type)) result.push({ "type": s.type, "hidden": !!s.hidden });
        }
        for (const s of SidebarCatalog.sections) {
            if (!result.some(r => r.type === s.type)) result.push({ "type": s.type, "hidden": false });
        }
        return result;
    }

    function sectionShown(type) {
        if (type === "sliders") return root.options.quickSliders.enable;
        return !(root.sections.find(s => s.type === type)?.hidden ?? false);
    }

    function setSectionShown(type, shown) {
        if (type === "sliders") {
            Config.options.sidebar.quickSliders.enable = shown;
            return;
        }
        Config.options.sidebar.right.sections = root.sections.map(s => s.type === type ? { "type": s.type, "hidden": !shown } : s);
    }

    // Moves a section to `index` among the sections (the header stays first)
    function moveSection(type, index) {
        if (type === "header") return;
        let list = root.sections.filter(s => s.type !== type);
        const moving = root.sections.find(s => s.type === type);
        list.splice(Math.max(1, Math.min(index, list.length)), 0, moving);
        Config.options.sidebar.right.sections = list;
    }

    function resetSections() {
        Config.options.sidebar.right.sections = SidebarCatalog.sections.map(s => ({ "type": s.type }));
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
