pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services

/**
 * Energy saving: whether it is on and what it turns off (Config.options.powerSaving).
 * Shell parts read the `cut…` properties, so the settings app follows along too. Only the main shell calls
 * load(), which also changes things outside the shell: Hyprland animations, blur and shadows (evaluated at
 * runtime, nothing is written to the config files), the CPU power profile, the laptop screen's brightness,
 * the keyboard backlight and Bluetooth.
 */
Singleton {
    id: root

    readonly property var options: Config.options?.powerSaving
    readonly property string mode: root.options?.mode ?? "off"
    readonly property string override: root.options?.override ?? ""
    readonly property bool onBattery: UPower.onBattery
    // On by itself because the charger is unplugged
    readonly property bool automatic: root.mode === "battery" && root.onBattery
    readonly property bool active: root.override === "on" ? true
        : root.override === "off" ? false
        : (root.mode === "on" || root.automatic)

    readonly property bool cutAnimations: root.active && (root.options?.animations ?? true)
    readonly property bool cutBlur: root.active && (root.options?.blur ?? true)
    readonly property bool pauseLiveWallpaper: root.active && (root.options?.liveWallpaper ?? true)
    readonly property bool cutVisualizer: root.active && (root.options?.visualizer ?? true)
    readonly property bool cutLivePreviews: root.active && (root.options?.livePreviews ?? true)
    readonly property bool slowPolling: root.active && (root.options?.polling ?? true)
    readonly property bool cutCpu: root.active && (root.options?.cpuProfile ?? true)
    readonly property bool cutBrightness: root.active && (root.options?.brightness ?? true)
    readonly property real brightnessLimit: (root.options?.brightnessLimit ?? 50) / 100
    readonly property bool cutKeyboardLight: root.active && (root.options?.keyboardLight ?? true)
    readonly property bool cutBluetooth: root.active && (root.options?.bluetooth ?? true)
    readonly property real pollingFactor: root.slowPolling ? 3 : 1

    // A short line for buttons: "On", "On battery", "Off until unplugged"…
    readonly property string statusText: {
        if (root.override === "on") return Translation.tr("On until the charger changes");
        if (root.override === "off") return root.mode === "battery" && !root.onBattery
            ? Translation.tr("Off") : Translation.tr("Off until the charger changes");
        if (root.mode === "on") return Translation.tr("On");
        if (root.mode === "battery") return root.onBattery ? Translation.tr("On while unplugged") : Translation.tr("Turns on when unplugged");
        return Translation.tr("Off");
    }

    // The quick toggle: with "off" and "on" it switches between them; with "battery" it overrides the
    // automatic choice until the charger is plugged in or out
    function toggle() {
        if (root.mode === "battery") {
            Config.options.powerSaving.override = root.active ? "off" : "on";
        } else {
            Config.options.powerSaving.override = "";
            Config.options.powerSaving.mode = root.active ? "off" : "on";
        }
    }

    function setMode(newMode) {
        Config.options.powerSaving.override = "";
        Config.options.powerSaving.mode = newMode;
    }

    function openSettings() {
        Quickshell.execDetached(["env", "QS_SETTINGS_PAGE=battery", "qs", "-p", Quickshell.shellPath("settings.qml")]);
    }

    // ---- Main shell only ----

    // qs -c ii ipc call powerSaving toggle | setMode off|battery|on | status
    IpcHandler {
        target: "powerSaving"
        enabled: root.loaded

        function toggle(): void { root.toggle() }
        function setMode(mode: string): void { root.setMode(mode) }
        function status(): string { return root.active ? "on" : "off" }
    }

    property bool loaded: false
    property bool settled: false // UPower reports the power source a moment after startup; that isn't a plug or unplug
    function load() {
        root.loaded = true;
        settleTimer.restart();
        root.applyHyprland();
        root.applyCpuProfile();
    }
    Timer {
        id: settleTimer
        interval: 3000
        onTriggered: root.settled = true
    }

    onOnBatteryChanged: {
        if (!root.settled || !Config.ready) return;
        if (root.override !== "") Config.options.powerSaving.override = "";
    }
    onAutomaticChanged: {
        if (!root.settled || root.override !== "" || root.mode !== "battery") return;
        Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "battery-profile-powersave",
            root.automatic ? Translation.tr("Energy saving is on") : Translation.tr("Energy saving is off"),
            root.automatic ? Translation.tr("The charger was unplugged") : Translation.tr("The charger is plugged in")]);
    }

    // Hyprland: which cuts are in effect ("a" animations, "b" blur and shadows). Turning one back on reloads
    // the config files, which restores the user's own values; whatever is still cut gets applied again after it.
    readonly property string hyprWanted: (root.cutAnimations ? "a" : "") + (root.cutBlur ? "b" : "")
    property string hyprApplied: ""
    onHyprWantedChanged: root.applyHyprland()

    function applyHyprland() {
        if (!root.loaded) return;
        const wanted = root.hyprWanted;
        if (wanted === root.hyprApplied) return;
        if ([...root.hyprApplied].some(cut => !wanted.includes(cut))) {
            Quickshell.execDetached(["hyprctl", "reload"]); // configreloaded applies what is still wanted
            return;
        }
        let parts = [];
        if (wanted.includes("a")) parts.push("animations = { enabled = false }");
        if (wanted.includes("b")) parts.push("decoration = { blur = { enabled = false }, shadow = { enabled = false } }");
        Quickshell.execDetached(["hyprctl", "eval", `hl.config({ ${parts.join(", ")} })`]);
        root.hyprApplied = wanted;
    }

    Connections {
        target: Hyprland
        enabled: root.loaded
        function onRawEvent(event) {
            if (event.name !== "configreloaded") return;
            root.hyprApplied = "";
            root.applyHyprland();
        }
    }

    // CPU profile: power saver while energy saving is on, then back to the profile from before
    property int profileBefore: PowerProfile.Balanced
    property bool profileApplied: false
    onCutCpuChanged: root.applyCpuProfile()

    function applyCpuProfile() {
        if (!root.loaded) return;
        if (root.cutCpu && !root.profileApplied) {
            if (PowerProfiles.profile !== PowerProfile.PowerSaver) root.profileBefore = PowerProfiles.profile;
            PowerProfiles.profile = PowerProfile.PowerSaver;
            root.profileApplied = true;
        } else if (!root.cutCpu && root.profileApplied) {
            if (PowerProfiles.profile === PowerProfile.PowerSaver) PowerProfiles.profile = root.profileBefore;
            root.profileApplied = false;
        }
    }

    // Screen brightness, keyboard backlight and Bluetooth: turned down once when energy saving starts, put back
    // when it ends. Changing them by hand in between is left alone. What was changed is kept in Persistent.
    readonly property bool devicesReady: root.loaded && Persistent.ready && Config.ready
    readonly property var saved: Persistent.states.powerSaving
    onDevicesReadyChanged: Qt.callLater(() => { // Once the rest of the shell is built
        root.applyBrightness(false);
        root.applyKeyboardLight();
        root.applyBluetooth();
    })

    // The laptop screen (monitors with DDC are external)
    readonly property var panel: Brightness.monitors.find(monitor => monitor.ready && !monitor.isDdc) ?? null
    onPanelChanged: root.applyBrightness(false)
    onCutBrightnessChanged: root.applyBrightness(false)
    onBrightnessLimitChanged: root.applyBrightness(true)

    function applyBrightness(limitChanged: bool) {
        const panel = root.panel;
        if (!root.devicesReady || !panel) return;
        if (root.cutBrightness && (!root.saved.brightnessCut || limitChanged)) {
            if (panel.brightness > root.brightnessLimit + 0.005) {
                if (root.saved.brightnessBefore < 0) root.saved.brightnessBefore = panel.brightness;
                root.saved.brightnessSet = root.brightnessLimit;
                panel.setBrightness(root.brightnessLimit);
            }
            root.saved.brightnessCut = true;
        } else if (!root.cutBrightness && root.saved.brightnessCut) {
            if (root.saved.brightnessBefore >= 0 && Math.abs(panel.brightness - root.saved.brightnessSet) < 0.02)
                panel.setBrightness(root.saved.brightnessBefore);
            root.saved.brightnessBefore = -1;
            root.saved.brightnessSet = -1;
            root.saved.brightnessCut = false;
        }
    }

    onCutKeyboardLightChanged: root.applyKeyboardLight()

    function applyKeyboardLight() {
        if (!root.devicesReady) return;
        if (root.cutKeyboardLight && !root.saved.keyboardLightCut) {
            root.saved.keyboardLightCut = true;
            keyboardLightProc.running = true;
        } else if (!root.cutKeyboardLight && root.saved.keyboardLightCut) {
            root.restoreKeyboardLight(root.saved.keyboardLightBefore);
            root.saved.keyboardLightBefore = 0;
            root.saved.keyboardLightCut = false;
        }
    }
    function restoreKeyboardLight(level: int) {
        if (level <= 0) return;
        // Only while it is still off
        Quickshell.execDetached(["sh", "-c", `[ "$(brightnessctl -d '*kbd_backlight' g)" = 0 ] && brightnessctl -q -d '*kbd_backlight' s ${level}`]);
    }
    Process { // Prints the level, then turns the backlight off
        id: keyboardLightProc
        command: ["sh", "-c", "brightnessctl -d '*kbd_backlight' g && brightnessctl -q -d '*kbd_backlight' s 0"]
        stdout: StdioCollector {
            id: keyboardLightOutput
            onStreamFinished: {
                const level = parseInt(keyboardLightOutput.text);
                if (isNaN(level)) return; // No keyboard backlight
                if (root.cutKeyboardLight) root.saved.keyboardLightBefore = level;
                else root.restoreKeyboardLight(level); // Energy saving ended meanwhile
            }
        }
    }

    readonly property bool bluetoothAvailable: BluetoothStatus.available
    onBluetoothAvailableChanged: root.applyBluetooth()
    onCutBluetoothChanged: root.applyBluetooth()

    function applyBluetooth() {
        if (!root.devicesReady || !BluetoothStatus.available) return;
        if (root.cutBluetooth && !root.saved.bluetoothCut) {
            root.saved.bluetoothBefore = BluetoothStatus.enabled && !BluetoothStatus.connected;
            if (root.saved.bluetoothBefore) BluetoothStatus.setEnabled(false);
            root.saved.bluetoothCut = true;
        } else if (!root.cutBluetooth && root.saved.bluetoothCut) {
            if (root.saved.bluetoothBefore) BluetoothStatus.setEnabled(true);
            root.saved.bluetoothBefore = false;
            root.saved.bluetoothCut = false;
        }
    }
}
