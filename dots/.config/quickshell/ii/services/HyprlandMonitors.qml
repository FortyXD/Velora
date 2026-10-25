pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions

/**
 * Displays as edited from the settings app. The live state comes from `hyprctl monitors all -j`.
 * Choices are kept per output in ~/.config/hypr/custom/monitors.json and written as hl.monitor() calls
 * to custom/monitors.lua, which hyprland.lua loads after monitors.lua; Hyprland is then reloaded.
 * Changes that can leave a screen unusable go back on their own unless they are kept in time.
 */
Singleton {
    id: root

    readonly property string jsonPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/monitors.json`)
    readonly property string luaPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/monitors.lua`)
    readonly property int confirmSeconds: 15

    property var monitors: []          // hyprctl monitors all -j
    property var overrides: ({})       // output name -> { mode, position, scale, transform, vrr?, mirror?, disabled? }
    property var previousOverrides: null
    property int secondsLeft: 0
    readonly property bool confirming: root.previousOverrides !== null
    property bool ready: false

    function refresh() {
        monitorsProc.running = false;
        monitorsProc.running = true;
    }

    function monitorByName(name) {
        return root.monitors.find(monitor => monitor.name === name) ?? null;
    }

    // "2880x1800@120.00Hz" -> { width: 2880, height: 1800, rate: "120.00" }
    function parseMode(text) {
        const match = (text ?? "").match(/^(\d+)x(\d+)(?:@([\d.]+))?/);
        return match ? { width: parseInt(match[1]), height: parseInt(match[2]), rate: match[3] ?? "" } : null;
    }
    function modes(monitor) {
        return (monitor?.availableModes ?? []).map(text => root.parseMode(text)).filter(mode => mode !== null);
    }

    // What the output uses now: the saved choice, otherwise what Hyprland reports
    function spec(monitor) {
        if (!monitor) return null;
        const saved = root.overrides[monitor.name];
        if (saved) return Object.assign({}, saved);
        if (!(monitor.width > 0)) { // Turned off elsewhere: start from its best mode
            const best = root.modes(monitor)[0];
            return { mode: best ? `${best.width}x${best.height}@${best.rate}` : "preferred", position: "auto",
                     scale: 1, transform: 0, disabled: !!monitor.disabled, mirror: "" };
        }
        return {
            mode: `${monitor.width}x${monitor.height}@${Number(monitor.refreshRate).toFixed(2)}`,
            position: `${monitor.x}x${monitor.y}`,
            scale: Math.round(monitor.scale * 1000000) / 1000000,
            transform: monitor.transform ?? 0,
            disabled: !!monitor.disabled,
            mirror: monitor.mirrorOf && monitor.mirrorOf !== "none" ? monitor.mirrorOf : ""
        };
    }

    // Size on the desktop, in logical pixels
    function logicalSize(spec) {
        const mode = root.parseMode(spec?.mode) ?? { width: 1920, height: 1080 };
        const scale = Number(spec?.scale) > 0 ? Number(spec.scale) : 1;
        const rotated = (spec?.transform ?? 0) % 2 === 1;
        const width = Math.round(mode.width / scale);
        const height = Math.round(mode.height / scale);
        return rotated ? { width: height, height: width } : { width: width, height: height };
    }
    function position(spec) {
        const match = (spec?.position ?? "").match(/^(-?\d+)x(-?\d+)$/);
        return match ? { x: parseInt(match[1]), y: parseInt(match[2]) } : { x: 0, y: 0 };
    }

    // Scales Hyprland can use for a mode: whole logical pixels, in steps of 1/120
    function scalesFor(modeText) {
        const mode = root.parseMode(modeText);
        if (!mode) return [1];
        const candidates = [1, 1.25, 4 / 3, 1.5, 1.6, 5 / 3, 1.75, 2, 2.25, 2.5, 3];
        return candidates.filter(scale => {
            const width = mode.width / scale;
            const height = mode.height / scale;
            return Math.abs(width - Math.round(width)) < 0.01 && Math.abs(height - Math.round(height)) < 0.01;
        }).map(scale => Math.round(scale * 1000000) / 1000000);
    }

    // Changes to one output. `confirm` asks to keep them, for things that can black out a screen.
    function change(name, changes, confirm = true) {
        const monitor = root.monitorByName(name);
        if (!monitor) return;
        let next = Object.assign({}, root.overrides);
        next[name] = Object.assign(root.spec(monitor), changes);
        root.apply(next, confirm);
    }
    // New positions for several outputs at once: { name: "XxY" }
    function arrange(positions) {
        let next = Object.assign({}, root.overrides);
        for (const name of Object.keys(positions)) {
            const monitor = root.monitorByName(name);
            if (!monitor) continue;
            next[name] = Object.assign(root.spec(monitor), { position: positions[name] });
        }
        root.apply(next, false);
    }
    function resetAll() {
        root.apply({}, true);
    }

    function apply(next, confirm) {
        if (confirm && root.previousOverrides === null) {
            root.previousOverrides = JSON.parse(JSON.stringify(root.overrides));
        }
        root.overrides = next;
        root.write();
        if (confirm || root.confirming) {
            root.secondsLeft = root.confirmSeconds;
            countdown.restart();
        }
    }
    function keep() {
        countdown.stop();
        root.previousOverrides = null;
    }
    function revert() {
        countdown.stop();
        const previous = root.previousOverrides ?? {};
        root.previousOverrides = null;
        root.overrides = previous;
        root.write();
    }

    function luaString(text) {
        return `"${String(text).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
    }
    function buildLua() {
        let lines = [
            "-- Generated by the Velora settings app (Displays). Edits here are overwritten;",
            "-- put manual monitor rules in monitors.lua instead.",
            ""
        ];
        for (const name of Object.keys(root.overrides).sort()) {
            const spec = root.overrides[name];
            lines.push("hl.monitor({");
            lines.push(`    output = ${root.luaString(name)},`);
            if (spec.disabled) {
                lines.push("    disabled = true,");
            } else {
                lines.push(`    mode = ${root.luaString(spec.mode)},`);
                lines.push(`    position = ${root.luaString(spec.position)},`);
                lines.push(`    scale = ${Number(spec.scale)},`);
                lines.push(`    transform = ${spec.transform ?? 0},`);
                if (spec.vrr !== undefined && spec.vrr !== null) lines.push(`    vrr = ${spec.vrr},`);
                if (spec.mirror) lines.push(`    mirror = ${root.luaString(spec.mirror)},`);
            }
            lines.push("})");
        }
        return lines.join("\n") + "\n";
    }

    function write() {
        jsonFile.setText(JSON.stringify(root.overrides, null, 4) + "\n");
        luaFile.setText(root.buildLua());
        reloadTimer.restart();
    }

    Timer {
        id: reloadTimer
        interval: 150 // Lets the files land first
        onTriggered: Quickshell.execDetached(HyprlandSettings.reloadCommand)
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.secondsLeft -= 1;
            if (root.secondsLeft <= 0) root.revert();
        }
    }

    FileView {
        id: jsonFile
        path: root.jsonPath
        blockLoading: true
        onLoaded: {
            try {
                root.overrides = JSON.parse(jsonFile.text()) ?? {};
            } catch (e) {
                root.overrides = {};
            }
        }
        onLoadFailed: root.overrides = {}
    }
    FileView {
        id: luaFile
        path: root.luaPath
    }

    Process {
        id: monitorsProc
        running: true
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(monitorsCollector.text);
                    root.ready = true;
                } catch (e) {
                    console.warn("[HyprlandMonitors] Couldn't read monitors:", e);
                }
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 300 // Several events come at once while outputs change
        onTriggered: root.refresh()
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].includes(event.name))
                refreshTimer.restart();
        }
    }
}
