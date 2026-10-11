pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Installed font families, for font pickers. Monospace ones come from fontconfig, which knows
 * the spacing of each font; Qt only lists the names.
 */
Singleton {
    id: root

    readonly property var families: Array.from(new Set(Qt.fontFamilies())).sort((a, b) => a.localeCompare(b))
    property var monospaceNames: []
    readonly property var monospaceFamilies: {
        const mono = new Set(root.monospaceNames.map(name => root.normalize(name)));
        return root.families.filter(family => mono.has(root.normalize(family)));
    }
    readonly property var nerdFamilies: root.families.filter(family => /Nerd Font|\bNF\b|Symbols Nerd/.test(family))

    function familiesFor(kind) {
        if (kind === "monospace") return root.monospaceFamilies.length > 0 ? root.monospaceFamilies : root.families;
        if (kind === "nerd") return root.nerdFamilies.length > 0 ? root.nerdFamilies : root.families;
        return root.families;
    }

    // Fonts go by several names ("JetBrains Mono NF" is "JetBrainsMono NF" to fontconfig)
    function normalize(family) {
        return (family ?? "").toLowerCase().replace(/[\s_-]/g, "");
    }
    property var allNames: []
    readonly property var normalizedNames: new Set([...root.families, ...root.allNames].map(name => root.normalize(name)))
    function installed(family) {
        return root.normalizedNames.has(root.normalize(family));
    }
    // The listed family that is `family` under another spelling, or `family` itself
    function listed(family) {
        const wanted = root.normalize(family);
        return root.families.find(name => root.normalize(name) === wanted) ?? family;
    }

    function names(text) {
        let names = new Set();
        for (const line of text.split("\n")) {
            for (const name of line.split(",")) {
                if (name.trim().length > 0) names.add(name.trim());
            }
        }
        return Array.from(names);
    }

    Process {
        running: true
        command: ["fc-list", ":spacing=mono", "family"]
        stdout: StdioCollector {
            onStreamFinished: root.monospaceNames = root.names(text)
        }
    }
    Process {
        running: true
        command: ["fc-list", ":", "family"]
        stdout: StdioCollector {
            onStreamFinished: root.allNames = root.names(text)
        }
    }
}
