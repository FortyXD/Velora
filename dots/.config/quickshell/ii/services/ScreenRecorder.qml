pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/** State belongs to the recording controller, not to arbitrary wf-recorder processes. */
Singleton {
    id: root

    property string phase: "idle"
    property real startedAt: 0
    property string file: ""
    property string error: ""
    property int remaining: 0
    readonly property bool recording: phase === "recording"
    property bool regionSelecting: false
    readonly property bool active: regionSelecting || launchTimer.running || ["selecting", "countdown", "starting", "recording", "stopping"].includes(phase)
    readonly property bool busy: active && !recording
    readonly property string tooltip: phase === "countdown" ? Translation.tr("Cancel recording countdown (%1 s)").arg(remaining)
        : recording ? Translation.tr("Stop recording")
        : active ? Translation.tr("Cancel recording") : Translation.tr("Record screen")
    readonly property string savePath: {
        const configured = Config.options.screenRecord.savePath;
        const home = FileUtils.trimFileProtocol(Directories.home);
        const videos = FileUtils.trimFileProtocol(Directories.videos);
        return configured.length > 0 ? configured.replace(/^~/, home) : (videos && videos !== home ? videos : home + "/Videos");
    }
    property var pendingArgs: []
    property bool pendingRegion: false
    property string pendingSound: ""
    signal regionRequested(string sound)

    function refresh() {
        if (!stateProcess.running) stateProcess.running = true;
    }
    function stop() {
        launchTimer.stop();
        if (root.regionSelecting) {
            GlobalStates.regionSelectorOpen = false;
            root.regionSelecting = false;
        }
        Quickshell.execDetached([Directories.recordScriptPath, "stop"]);
        refresh();
    }
    function toggle(mode = "", sound = "") {
        if (active) { stop(); return; }
        GlobalStates.closeSidebars();
        GlobalStates.overlayOpen = false;
        GlobalStates.regionSelectorOpen = false;
        let args = [Directories.recordScriptPath];
        if (mode === "screen") args.push("--fullscreen");
        if (mode === "region") args.push("--select-region");
        if (sound === "none") args.push("--silent");
        if (sound === "system") args.push("--sound");
        if (sound === "both") args.push("--mic");
        root.pendingRegion = false;
        root.pendingArgs = args;
        // Config writes debounce for 50 ms; also let the initiating panel close.
        launchTimer.restart();
    }
    function selectRegion(sound = "") {
        if (active) { stop(); return; }
        root.pendingRegion = true;
        root.pendingSound = sound;
        launchTimer.restart();
    }
    Connections {
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (!GlobalStates.regionSelectorOpen) root.regionSelecting = false;
        }
    }
    function openFolder() {
        Qt.openUrlExternally("file://" + root.savePath);
    }

    Timer {
        id: launchTimer
        interval: 180
        onTriggered: {
            if (root.pendingRegion) {
                root.regionRequested(root.pendingSound);
            } else {
                Quickshell.execDetached(root.pendingArgs);
                root.phase = "starting";
                root.refresh();
            }
        }
    }
    IpcHandler {
        target: "recorder"
        function toggle(): void { root.toggle(); }
        function stop(): void { root.stop(); }
        function screenSilent(): void { root.toggle("screen", "none"); }
        function screenWithSound(): void { root.toggle("screen", "system"); }
        function screenWithMic(): void { root.toggle("screen", "both"); }
        function status(): string { return JSON.stringify({ state: root.regionSelecting ? "selecting" : root.phase, file: root.file, error: root.error, startedAt: root.startedAt }); }
    }
    Process {
        id: stateProcess
        command: [Directories.recordScriptPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text);
                    root.phase = state.state || "idle";
                    root.startedAt = state.startedAt || 0;
                    root.file = state.file || "";
                    root.error = state.error || "";
                    root.remaining = state.remaining || 0;
                } catch (e) { console.warn("Recorder status:", e); }
            }
        }
    }
    Component.onCompleted: refresh()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
