import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale
    required property Item placementCanvas
    property bool visibleWhenLocked: false
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    // A fixed priority avoids feedback loops. Later widgets avoid the actual
    // bounds of earlier ones, including widgets using a different strategy.
    readonly property list<string> autoPlacementOrder: ["clock", "weather", "systemMonitor", "media", "calendar", "countdown", "note", "pomodoro"]
    readonly property string placementObstacles: {
        if (!root.placementCanvas || root.placementStrategy === "free") return "[]";
        const priority = root.autoPlacementOrder.indexOf(root.configEntryName);
        const rectangles = [];
        for (const loader of root.placementCanvas.children) {
            const peer = loader.item;
            if (!loader.shown || !peer || peer === root || !peer.configEntryName) continue;
            if (peer.placementStrategy !== "free" && root.autoPlacementOrder.indexOf(peer.configEntryName) >= priority) continue;
            // Target coordinates change once per placement/drag, not on every
            // animation frame. Loader, size and strategy changes are reactive too.
            rectangles.push([peer.targetX, peer.targetY, peer.width, peer.height]);
        }
        return JSON.stringify(rectangles);
    }
    property real targetX: Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width))
    property real targetY : Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height))
    x: targetX
    y: targetY
    visible: opacity > 0
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (draggable && containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    draggable: placementStrategy === "free"
    onReleased: {
        root.targetX = root.x;
        root.targetY = root.y;
        configEntry.x = root.targetX;
        configEntry.y = root.targetY;
        root.refreshPlacementIfNeeded();
    }

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property real textLightness: dominantColorIsDark ? 0.8 : 0.12
    Behavior on textLightness {
        NumberAnimation {
            duration: WallpaperTransition.remainingDuration(Appearance.scaledDuration(350))
            easing.type: Easing.InOutQuad
        }
    }
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, root.textLightness)
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: FileUtils.isVideoPath(Config.options.background.wallpaperPath)
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    readonly property string wallpaperScreenName: (QsWindow.window as QsWindow)?.screen?.name ?? ""
    property int analysisGeneration: 0
    property var analysisJob: null
    property var analysisResult: null

    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    onPlacementObstaclesChanged: refreshPlacementIfNeeded()
    onWidthChanged: refreshPlacementIfNeeded()
    onHeightChanged: refreshPlacementIfNeeded()
    onNeedsColTextChanged: refreshPlacementIfNeeded()
    onScaledScreenWidthChanged: refreshPlacementIfNeeded()
    onScaledScreenHeightChanged: refreshPlacementIfNeeded()
    Component.onCompleted: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { root.refreshPlacementIfNeeded() }
    }
    Connections {
        target: WallpaperTransition
        function onPresented(screenName, path) {
            if (screenName === root.wallpaperScreenName) root.commitAnalysis();
        }
    }
    function refreshPlacementIfNeeded() {
        root.analysisGeneration++;
        analysisTimer.restart();
    }
    function commitAnalysis() {
        const result = root.analysisResult;
        if (!result || result.generation !== root.analysisGeneration || result.path !== root.wallpaperPath) return;
        const state = WallpaperTransition.screens[root.wallpaperScreenName];
        if (state && state.path !== result.path) return; // The old picture is still visible.
        root.dominantColor = result.data.dominant_color;
        if (root.placementStrategy === "free") return;
        root.targetX = Math.max(0, Math.min(root.scaledScreenWidth - root.width, result.data.center_x * root.wallpaperScale - root.width / 2));
        root.targetY = Math.max(0, Math.min(root.scaledScreenHeight - root.height, result.data.center_y * root.wallpaperScale - root.height / 2));
    }
    function acceptAnalysis(generation, path, output) {
        if (generation !== root.analysisGeneration || path !== root.wallpaperPath) return;
        try {
            const data = JSON.parse(output);
            if (!/^#[0-9a-f]{6}$/i.test(data.dominant_color ?? "")) return;
            if (root.placementStrategy !== "free" && (!Number.isFinite(data.center_x) || !Number.isFinite(data.center_y))) return;
            root.analysisResult = { generation: generation, path: path, data: data };
            root.commitAnalysis();
        } catch (error) {
            console.warn("[Background] Invalid wallpaper analysis:", error);
        }
    }
    Timer {
        id: analysisTimer
        interval: 40
        onTriggered: {
            if (root.analysisJob) {
                root.analysisJob.running = false;
                root.analysisJob.destroy();
                root.analysisJob = null;
            }
            if (!Config.ready || root.wallpaperPath.length === 0) return;
            if (root.placementStrategy === "free" && !root.needsColText) return;
            const command = [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh"),
                "--screen-width", Math.round(root.scaledScreenWidth),
                "--screen-height", Math.round(root.scaledScreenHeight),
                "--width", Math.max(1, Math.round(root.width || 300)),
                "--height", Math.max(1, Math.round(root.height || 300)),
                "--horizontal-padding", 100, "--vertical-padding", 100, root.wallpaperPath,
                ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : []),
                "--avoid-rects", root.placementObstacles,
                ...(root.placementStrategy === "free" ? ["--sample-x", Math.round(root.x), "--sample-y", Math.round(root.y)] : [])];
            root.analysisJob = analysisComponent.createObject(root, {
                "generation": root.analysisGeneration, "path": root.wallpaperPath, "command": command
            });
        }
    }
    Component {
        id: analysisComponent
        Process {
            id: job
            required property int generation
            required property string path
            running: true
            stdout: StdioCollector {
                onStreamFinished: root.acceptAnalysis(job.generation, job.path, text)
            }
            onExited: {
                if (root.analysisJob === job) root.analysisJob = null;
                job.destroy();
            }
        }
    }
}
