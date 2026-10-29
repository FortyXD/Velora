pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Animated wallpapers drawn by the shell (Config.options.background.shaderWallpaper), as an alternative
 * to video wallpapers: they follow the theme's colors (or a look's own), need no download, and stop
 * drawing while hidden: behind windows (background.liveWallpaper.pauseWhen), with energy saving, and
 * on the lock screen unless lock.animatedWallpaper.
 * The wallpaper picture becomes a still frame of it, so colors, previews and everything else work as usual.
 */
Singleton {
    id: root

    readonly property var options: Config.options?.background.shaderWallpaper
    readonly property string name: root.options?.name ?? ""
    readonly property bool active: root.name.length > 0 && root.shaders.some(shader => shader.id === root.name)

    readonly property list<var> shaders: [
        { "id": "aurora", "name": Translation.tr("Aurora"), "icon": "nights_stay",
          "description": Translation.tr("Northern lights swaying over hills"), "colors": ["#3DFFB8", "#5B8CFF", "#C266FF", "#071226"] },
        { "id": "liquid", "name": Translation.tr("Liquid"), "icon": "water_drop",
          "description": Translation.tr("Colors flowing into each other, like a lava lamp"), "colors": ["#FF4FA3", "#FFB547", "#7A5CFF", "#1A0B2E"] },
        { "id": "grid", "name": Translation.tr("Neon grid"), "icon": "grid_4x4",
          "description": Translation.tr("A glowing grid running to a striped sun"), "colors": ["#FF2E88", "#FFC233", "#24E1FF", "#140326"] },
        { "id": "dunes", "name": Translation.tr("Dunes"), "icon": "landscape",
          "description": Translation.tr("Layers of hills drifting under a low sun"), "colors": ["#FFD27A", "#FF7A45", "#B23A48", "#2B1036"] }
    ]

    function shader(id) {
        return root.shaders.find(shader => shader.id === id) ?? null;
    }

    function framePath(name) {
        return `${FileUtils.trimFileProtocol(Directories.state)}/user/generated/shader-wallpapers/${name}.png`;
    }

    // ---- Shell only ----

    // A still frame is wanted for the wallpaper picture; Background.qml takes it and calls frameSaved()
    property bool framePending: false
    property var pendingArgs: []
    property var pendingCompletion: null

    // Makes `name` the wallpaper; `switchwallArgs` carry a look's light/dark mode and accent
    function activate(name, switchwallArgs = [], completion = null) {
        if (!root.shader(name)) {
            console.warn("[ShaderWallpaper] Unknown wallpaper", name);
            if (completion) completion();
            return;
        }
        if (root.pendingCompletion) root.pendingCompletion();
        root.pendingArgs = switchwallArgs;
        root.pendingCompletion = completion;
        root.framePending = true;
        Config.options.background.shaderWallpaper.name = name;
        Config.options.background.daily.enable = false;
        frameTimeout.restart();
    }

    function frameSaved(path) {
        if (!root.framePending || path !== root.framePath(root.name)) return;
        root.framePending = false;
        frameTimeout.stop();
        colorJob.createObject(root, {
            "command": [Directories.wallpaperSwitchScriptPath, "--image", path, "--keep-shader", ...root.pendingArgs],
            "completion": root.pendingCompletion
        });
        root.pendingCompletion = null;
    }

    Component {
        id: colorJob
        Process {
            id: job
            property var completion: null
            running: true
            onExited: {
                if (job.completion) job.completion();
                job.destroy();
            }
        }
    }

    Timer { // No background window took the frame (another panel family): keep the animation, skip the colors
        id: frameTimeout
        interval: 8000
        onTriggered: {
            root.framePending = false;
            if (root.pendingCompletion) root.pendingCompletion();
            root.pendingCompletion = null;
        }
    }

    IpcHandler {
        target: "shaderWallpaper"
        function set(name: string): void {
            root.activate(name);
        }
        function list(): string {
            return root.shaders.map(shader => shader.id).join("\n");
        }
        function current(): string {
            return root.name;
        }
    }
}
