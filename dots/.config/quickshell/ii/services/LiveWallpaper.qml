pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Video wallpapers: one mpvpaper per screen, under the transparent background window (Background.qml).
 * The video pauses on its current frame while it can't be seen or isn't wanted: behind windows (as set in
 * Config.options.background.liveWallpaper.pauseWhen), on the lock screen and with energy saving. Pausing goes
 * through mpv's IPC socket and only reacts to events, nothing is polled.
 * switchwall.sh still sets the path and makes the first-frame picture used for colors and the lock screen.
 */
Singleton {
    id: root

    readonly property var options: Config.options?.background.liveWallpaper
    readonly property string decoder: root.options?.decoder ?? "gpu"
    readonly property string pauseWhen: root.options?.pauseWhen ?? "anyWindow"
    property string pathOverride: "" // For trying a video without making it the wallpaper
    readonly property string path: root.pathOverride || (Config.options?.background.wallpaperPath ?? "")
    readonly property bool isVideo: root.isVideoPath(root.path)
    readonly property bool hasMpvpaper: mpvpaperCheck.found

    function isVideoPath(path) {
        return FileUtils.isVideoPath(path);
    }

    // Whether windows hide the wallpaper on this screen enough to pause it
    function coveredOn(screenName) {
        if (root.pauseWhen === "never") return false;
        const monitor = HyprlandData.monitors.find(m => m.name === screenName);
        if (!monitor) return false;
        if ((monitor.specialWorkspace?.name ?? "").length > 0) return true; // A scratchpad is open over it
        const windows = HyprlandData.windowList.filter(w => w.workspace?.id === monitor.activeWorkspace?.id && w.mapped && !w.hidden);
        if (root.pauseWhen === "anyWindow") return windows.length > 0;
        return windows.some(w => w.fullscreen > 0); // Fullscreen or maximized
    }

    // ---- Main shell only ----

    property bool loaded: false
    property bool started: false // After leftovers from an older session are gone
    readonly property bool active: root.started && Config.ready && root.isVideo && root.hasMpvpaper
    // Bumped to restart the players when the video or the decoder changes
    property int generation: 0
    onPathChanged: root.generation++
    onDecoderChanged: root.generation++

    function load() {
        if (root.loaded) return;
        root.loaded = true;
        cleanupProc.running = true; // A login script of older versions may have started its own mpvpaper
    }

    Process {
        id: cleanupProc
        command: ["pkill", "-x", "mpvpaper"]
        onExited: root.started = true
    }

    Process {
        id: mpvpaperCheck
        property bool found: false
        running: root.loaded
        command: ["sh", "-c", "command -v mpvpaper"]
        onExited: exitCode => mpvpaperCheck.found = exitCode === 0
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: player
            required property ShellScreen modelData
            readonly property string screenName: player.modelData.name
            readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/folis-wallpaper-${player.screenName}.sock`
            readonly property bool shouldPlay: !GlobalStates.screenLocked && !PowerSaving.pauseLiveWallpaper && !root.coveredOn(player.screenName)
            property int runningGeneration: -1
            property int failures: 0

            function sendPause() {
                if (!socket.connected) return;
                socket.write(JSON.stringify({ "command": ["set_property", "pause", !player.shouldPlay] }) + "\n");
                socket.flush();
            }
            onShouldPlayChanged: player.sendPause()

            // Starts or stops the player to match what's wanted (running is set here only, never bound)
            function sync() {
                const wanted = root.active && player.failures < 3;
                if (wanted && !proc.running) restartTimer.restart();
                else if (!wanted && proc.running) proc.running = false;
            }
            Component.onCompleted: player.sync()

            Connections {
                target: root
                function onActiveChanged() { player.sync() }
                function onGenerationChanged() {
                    player.failures = 0;
                    // Stop, then start again with the new video or decoder
                    if (proc.running) proc.running = false;
                    else player.sync();
                }
            }

            Process {
                id: proc
                command: {
                    const options = [
                        "no-audio", "loop", "load-scripts=no", "really-quiet",
                        // VA-API only, never "auto": probing NVDEC or the CUDA interop loads libcuda, which wakes a sleeping NVIDIA GPU
                        root.decoder === "cpu" ? "hwdec=no" : "hwdec=vaapi",
                        root.decoder === "cpu" ? "gpu-hwdec-interop=no" : "gpu-hwdec-interop=vaapi",
                        "scale=bilinear", "interpolation=no", "panscan=1.0", "video-align-x=0.5", "video-align-y=0.5",
                        `input-ipc-server=${player.socketPath}`,
                    ];
                    // Keep the player on the integrated GPU's EGL, so it doesn't wake a hybrid laptop's dGPU either
                    return ["sh", "-c", 'if [ -f "$1" ]; then export __EGL_VENDOR_LIBRARY_FILENAMES="$1"; fi; shift; exec mpvpaper "$@"', "sh",
                        "/usr/share/glvnd/egl_vendor.d/50_mesa.json", "-o", options.join(" "), player.screenName, root.path];
                }
                onRunningChanged: {
                    if (proc.running) {
                        player.runningGeneration = root.generation;
                        connectTimer.restart();
                    } else {
                        socket.connected = false;
                        player.sync(); // Started again for a new video, or after a crash
                    }
                }
                onExited: (exitCode, exitStatus) => {
                    if (player.runningGeneration === root.generation && root.active) player.failures++;
                }
            }

            Timer { // A short pause before starting, so an old player's surface is gone first
                id: restartTimer
                interval: 400
                onTriggered: if (root.active && player.failures < 3 && !proc.running) proc.running = true
            }

            Timer { // mpv opens its socket a moment after starting
                id: connectTimer
                interval: 300
                repeat: true
                onTriggered: {
                    if (!proc.running || socket.connected) {
                        stop();
                        return;
                    }
                    socket.connected = true;
                }
            }

            Socket {
                id: socket
                path: player.socketPath
                onConnectedChanged: if (socket.connected) player.sendPause()
            }
        }
    }
}
