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

    property var monitors: []          // hyprctl monitors all -j, as reported
    // Hyprland's virtual output appears when no real screen is enabled. It is not a display:
    // counting it as one hid that the built-in panel was off, and the picture went nowhere
    // after unplugging the external monitor.
    readonly property string virtualOutput: "FALLBACK"
    readonly property var displays: monitors.filter(monitor => monitor.name !== root.virtualOutput)
    property var overrides: ({})       // output name -> { mode, position, scale, transform, vrr?, mirror?, disabled? }
    property var previousOverrides: null
    property int secondsLeft: 0
    // Only the shell watches outputs; the settings window is a reader. Without this the
    // singleton existed just while settings were open, so unplugging the only lit screen
    // with settings closed left every output disabled and the picture gone.
    property bool watching: false
    property bool fallbackWritten: false
    readonly property bool confirming: root.previousOverrides !== null
    property bool ready: false

    function refresh() {
        monitorsProc.running = false;
        monitorsProc.running = true;
    }
    function watch() {
        root.watching = true;
        root.refresh();
    }

    // Write the presence decision out: the safe built-in configuration while nothing else is
    // lit, the saved intent again as soon as an external display comes back.
    function syncFallback() {
        if (!root.watching || root.fallbackActive === root.fallbackWritten) return;
        root.fallbackWritten = root.fallbackActive;
        root.write();
    }

    // Lookups are for the user-facing list: the virtual output cannot be configured.
    function monitorByName(name) {
        return root.displays.find(monitor => monitor.name === name) ?? null;
    }

    // "2880x1800@120.00Hz" -> { width: 2880, height: 1800, rate: "120.00" }
    function parseMode(text) {
        const match = (text ?? "").match(/^(\d+)x(\d+)(?:@([\d.]+))?/);
        return match ? { width: parseInt(match[1]), height: parseInt(match[2]), rate: match[3] ?? "" } : null;
    }
    function modes(monitor) {
        return (monitor?.availableModes ?? []).map(text => root.parseMode(text)).filter(mode => mode !== null);
    }

    // Hyprland reports the *scaled* size of an enabled output, so the mode has to be found
    // back among the available ones: same panel, same refresh rate. Rebuilding the mode from
    // the reported size instead would divide by the scale twice and invent a mode that is not
    // in the list (1512x1008 for a 2520x1680@1.6667 display).
    function modeText(monitor) {
        const available = monitor?.availableModes ?? [];
        if (!monitor || available.length === 0) return "preferred";
        const scale = Number(monitor.scale) > 0 ? Number(monitor.scale) : 1;
        const rotated = (monitor.transform ?? 0) % 2 === 1;
        const factor = monitor.disabled ? 1 : scale; // a disabled output reports its mode size
        const wantWidth = Number(monitor.width) * factor;
        const wantHeight = Number(monitor.height) * factor;
        const rate = Number(monitor.refreshRate);
        // Normalized the way the settings page writes it: the raw list carries a trailing
        // "Hz", which Hyprland's monitor mode parser does not accept.
        const name = mode => `${mode.width}x${mode.height}` + (mode.rate ? `@${mode.rate}` : "");
        const parsed = available.map(text => ({ text: text, mode: root.parseMode(text) }))
            .filter(item => item.mode !== null);
        const sameRate = item => !(rate > 0) || Math.abs(parseFloat(item.mode.rate) - rate) < 0.6;
        const exact = parsed.find(item => {
            const width = rotated ? item.mode.height : item.mode.width;
            const height = rotated ? item.mode.width : item.mode.height;
            return Math.abs(width - wantWidth) <= 2 && Math.abs(height - wantHeight) <= 2 && sameRate(item);
        });
        if (exact) return name(exact.mode);
        const byRate = parsed.filter(sameRate)
            .sort((a, b) => b.mode.width * b.mode.height - a.mode.width * a.mode.height);
        const fallback = byRate[0] ?? parsed[0];
        return fallback ? name(fallback.mode) : "preferred";
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
            mode: root.modeText(monitor),
            position: `${monitor.x}x${monitor.y}`,
            scale: Math.round(monitor.scale * 1000000) / 1000000,
            transform: monitor.transform ?? 0,
            disabled: !!monitor.disabled,
            mirror: monitor.mirrorOf && monitor.mirrorOf !== "none" ? monitor.mirrorOf : ""
        };
    }

    readonly property var builtin: root.displays.find(monitor => /^(eDP|LVDS|DSI)/.test(monitor.name)) ?? null

    // The laptop panel, on with the settings app never invented for it: the panel's own
    // preferred mode at 0,0, keeping only the scale the user chose for it.
    function safeSpec(monitor) {
        const saved = root.overrides[monitor.name] ?? {};
        const scale = Number(saved.scale) > 0 ? Number(saved.scale) : (Number(monitor.scale) > 0 ? Number(monitor.scale) : 1);
        return { mode: "preferred", position: "0x0", scale: scale, transform: 0, disabled: false, mirror: "" };
    }

    // True when every connected output is switched off by the saved choices, which is what
    // unplugging the only enabled screen while the built-in is disabled would leave behind.
    // What Hyprland lights right now, ignoring its virtual output. An unplugged screen is
    // either gone or still listed as disabled, so "is anything lit" has to be read from the
    // live state; asking the saved intent instead would keep saying "the external is on".
    readonly property var litOutputs: root.displays.filter(monitor => !monitor.disabled)
    // Outputs that are lit and that the user actually asked for: while there is none, the
    // built-in panel must come on. The panel itself never counts, or switching it on would
    // clear the fallback and switch it off again in a loop.
    readonly property var litWanted: litOutputs.filter(monitor => !root.spec(monitor).disabled
        && !(root.builtin && monitor.name === root.builtin.name && root.fallbackWritten))
    readonly property bool nothingLit: root.ready && litWanted.length === 0
    readonly property bool fallbackActive: root.nothingLit && root.builtin !== null

    // What the settings page should show and the lua should write: the saved choice, or the
    // safe built-in configuration while nothing else is lit.
    function effectiveSpec(monitor) {
        if (root.fallbackActive && monitor && root.builtin && monitor.name === root.builtin.name)
            return root.safeSpec(monitor);
        return root.spec(monitor);
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
        const specs = Object.assign({}, root.overrides);
        if (root.fallbackActive && root.builtin) specs[root.builtin.name] = root.safeSpec(root.builtin);
        for (const name of Object.keys(specs).sort()) {
            const spec = specs[name];
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

    // Same pattern as the other services: lets the user (and the tests) see what the
    // shell actually knows about the outputs, instead of guessing from a black screen.
    IpcHandler {
        target: "monitors"
        function status(): string {
            return JSON.stringify({
                watching: root.watching,
                ready: root.ready,
                outputs: root.monitors.map(monitor => ({
                    name: monitor.name, disabled: !!monitor.disabled,
                    width: monitor.width, height: monitor.height, scale: monitor.scale
                })),
                intent: Object.keys(root.overrides).map(name => ({
                    name: name, disabled: !!root.overrides[name].disabled
                })),
                nothingLit: root.nothingLit,
                builtin: root.builtin?.name ?? null,
                fallbackActive: root.fallbackActive,
                fallbackWritten: root.fallbackWritten
            });
        }
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
                    root.syncFallback();
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
