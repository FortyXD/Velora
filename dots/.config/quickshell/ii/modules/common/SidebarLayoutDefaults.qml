pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Ready-made sidebar layouts (services/SidebarLayout.qml), as lists of parts:
 *   { uid, type, hidden?, options? }  and for "tabs" also  tabs: [{ uid, type, hidden?, swipeOnly? }]
 * legacy(side) builds a sidebar from the settings older versions had (right: sections, header,
 * widgets; left: order, translator, policies), so a config without `parts` looks as it did. Its uids
 * are fixed, so the remembered tabs survive the first edit that writes the list out.
 */
Singleton {
    id: root

    function right() {
        return [
            { "uid": "header-right", "type": "header" },
            { "uid": "sliders-right", "type": "sliders", "hidden": true },
            { "uid": "toggles-right", "type": "toggles" },
            { "uid": "notifications-right", "type": "notifications" },
            { "uid": "tabs-right", "type": "tabs", "options": { "style": "rail", "collapsible": true, "share": 0.3 },
              "tabs": [{ "uid": "calendar-right", "type": "calendar" }, { "uid": "todo-right", "type": "todo" }, { "uid": "timer-right", "type": "timer" }] }
        ];
    }

    function left() {
        return [
            { "uid": "media-left", "type": "media", "options": { "hideWhenIdle": true } },
            { "uid": "weather-left", "type": "weather" },
            { "uid": "tools-left", "type": "tools" },
            { "uid": "tabs-left", "type": "tabs", "options": { "style": "bar" },
              "tabs": [{ "uid": "ai-left", "type": "ai" }, { "uid": "translator-left", "type": "translator" },
                       { "uid": "clipboard-left", "type": "clipboard" }, { "uid": "notes-left", "type": "notes" },
                       { "uid": "anime-left", "type": "anime", "hidden": true }] }
        ];
    }

    function forSide(side) {
        return side === "left" ? root.left() : root.right();
    }

    function legacy(side) {
        const o = Config.options;
        if (side === "right") {
            const known = ["header", "sliders", "toggles", "notifications", "widgets"];
            const given = (o.sidebar.right.sections ?? []).filter(s => known.includes(s?.type));
            let order = ["header", ...given.map(s => s.type).filter(t => t !== "header"), ...known];
            order = order.filter((t, i) => order.indexOf(t) === i);
            const hidden = type => type === "sliders" ? !o.sidebar.quickSliders.enable : !!given.find(s => s.type === type)?.hidden;
            const tabTypes = (o.sidebar.right.widgets.tabs ?? []).filter((t, i, list) => ["calendar", "todo", "timer"].includes(t) && list.indexOf(t) === i);
            return order.map(type => {
                if (type === "header") return { "uid": "header-right", "type": "header", "hidden": hidden(type),
                    "options": { "showUptime": o.sidebar.right.header.showUptime, "buttons": [...o.sidebar.right.header.buttons] } };
                if (type === "widgets") return { "uid": "tabs-right", "type": "tabs", "hidden": hidden(type),
                    "options": { "style": "rail", "collapsible": true, "share": Math.max(0.2, Math.min(0.7, o.sidebar.right.widgets.height)) },
                    "tabs": (tabTypes.length > 0 ? tabTypes : ["calendar"]).map(t => ({ "uid": `${t}-right`, "type": t })) };
                return { "uid": `${type}-right`, "type": type, "hidden": hidden(type) };
            });
        }
        const known = ["ai", "translator", "anime"];
        const given = (o.sidebar.left.order ?? []).filter(id => known.includes(id));
        const hidden = { "ai": o.policies.ai === 0, "translator": !o.sidebar.translator.enable, "anime": o.policies.weeb === 0 };
        const start = o.sidebar.left.startTab ?? "last";
        return [{ "uid": "tabs-left", "type": "tabs", "options": { "style": "bar", "start": known.includes(start) ? start : "last" },
                  "tabs": [...given, ...known.filter(id => !given.includes(id))].map(id => ({ "uid": `${id}-left`, "type": id,
                      "hidden": hidden[id], "swipeOnly": id === "anime" && o.policies.weeb === 2 })) }];
    }
}
