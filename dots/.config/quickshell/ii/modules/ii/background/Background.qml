pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.systemMonitor
import qs.modules.ii.background.widgets.media
import qs.modules.ii.background.widgets.calendar
import qs.modules.ii.background.widgets.countdown
import qs.modules.ii.background.widgets.note
import qs.modules.ii.background.widgets.pomodoro

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: bgRoot

        required property var modelData
        Component.onDestruction: WallpaperTransition.remove(modelData.name)

        // Behind a fullscreen window the widgets stop drawing. The window itself stays mapped with the
        // wallpaper: unmapping it made the empty screen flash while it mapped again on leaving fullscreen.
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == bgRoot.modelData.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        readonly property bool coveredByFullscreen: !GlobalStates.screenLocked && activeWorkspaceWithFullscreen !== undefined && Config.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10
        property int workspaceChunkSize: Config?.options.bar.workspaces.shown ?? 10
        property int totalWorkspaces: Math.ceil(lastWorkspaceId / workspaceChunkSize) * workspaceChunkSize
        // Wallpaper
        property bool wallpaperIsVideo: CF.FileUtils.isVideoPath(Config.options.background.wallpaperPath)
        // Locked and not on the way out: blur, zoom and darkening are on (they fade while unlocking)
        readonly property bool lockedLook: GlobalStates.screenLocked && !GlobalStates.lockExiting
        // A video wallpaper keeps playing behind the lock screen (mpvpaper under this window pauses then)
        readonly property bool lockVideo: GlobalStates.screenLocked && bgRoot.wallpaperIsVideo && Config.options.lock.animatedWallpaper && !PowerSaving.pauseLiveWallpaper
        // An animated wallpaper drawn by the shell moves while it can be seen and is wanted
        readonly property bool shaderPlaying: ShaderWallpaper.active && !PowerSaving.pauseLiveWallpaper && !bgRoot.coveredByFullscreen
            && (GlobalStates.screenLocked ? Config.options.lock.animatedWallpaper : !LiveWallpaper.coveredOn(bgRoot.modelData.name))
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
        // switchwall sets a video first and makes its still frame after; until then the frame is an older video's.
        // Frames are named after their video.
        readonly property bool thumbnailMatches: !wallpaperIsVideo
            || CF.FileUtils.fileNameForPath(Config.options.background.thumbnailPath).startsWith(CF.FileUtils.fileNameForPath(Config.options.background.wallpaperPath) + ".")
        onThumbnailMatchesChanged: if (thumbnailMatches) wallpaper.show()
        // A video plays under this window. Its still frame stays over it until mpvpaper has surely started
        // (it doesn't tell), so switching to a video, or between two, fades instead of flashing the empty screen.
        property bool videoShown: false
        Connections {
            target: Config.options.background
            function onWallpaperPathChanged() {
                bgRoot.videoShown = false;
                videoTakeover.restart();
            }
        }
        Timer {
            id: videoTakeover
            interval: 1600
            running: true
            onTriggered: bgRoot.videoShown = bgRoot.wallpaperIsVideo
        }
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        readonly property real parallaxRation: Config.options.background.parallax.workspaceZoom
        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
        // WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        // Typing into a desktop widget (the note) needs keyboard focus; otherwise the wallpaper never takes it
        WlrLayershell.keyboardFocus: GlobalStates.desktopWidgetEditing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Measures a wallpaper before it's shown (see `wallpaper.measured`), one process per picture
        Component {
            id: sizeProbe
            Process {
                id: probe
                required property string path
                property bool preload: false
                running: true
                command: ["magick", "identify", "-ping", "-format", "%w %h", `${probe.path}[0]`] // [0]: the first frame of an animation
                stdout: StdioCollector {
                    onStreamFinished: {
                        const [width, height] = text.trim().split(/\s+/).map(Number);
                        if (width > 0 && height > 0) wallpaper.sizes[probe.path] = { width: width, height: height };
                        if (probe.preload) wallpaper.preloadMeasured(probe.path, width, height);
                        else wallpaper.measured(probe.path, width, height);
                        probe.destroy();
                    }
                }
            }
        }

        Item {
            anchors.fill: parent

            // Wallpaper
            Item {
                id: wallpaper
                visible: opacity > 0 // Also under the blur, which fades out when unlocking
                // A video plays under this window (LiveWallpaper); its still frame stands in on the lock screen, where it pauses
                // An animated wallpaper draws inside this item, so it stays shown for it
                opacity: ((wallpaper.ready && (!bgRoot.videoShown || GlobalStates.screenLocked)) || ShaderWallpaper.active) ? 1 : 0
                // Fades out onto a video that has started; comes back at once, as the video under it may have stopped
                Behavior on opacity {
                    enabled: wallpaper.opacity === 1
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                readonly property bool ready: wallpaperFader.ready

                property string newestPath: ""
                readonly property string wanted: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                onWantedChanged: wallpaper.show()
                Component.onCompleted: wallpaper.show()
                function show() {
                    if (!bgRoot.thumbnailMatches || wallpaper.wanted === wallpaper.newestPath) return;
                    wallpaper.newestPath = wallpaper.wanted;
                    wallpaperFader.cancelPending();
                    WallpaperTransition.begin(bgRoot.modelData.name, wallpaper.wanted);
                    if (wallpaper.wanted.length === 0) {
                        wallpaperFader.clear();
                        WallpaperTransition.finish(bgRoot.modelData.name, wallpaper.wanted);
                        return;
                    }
                    const size = wallpaper.sizes[wallpaper.wanted];
                    if (size) wallpaper.measured(wallpaper.wanted, size.width, size.height);
                    else sizeProbe.createObject(wallpaper, { "path": wallpaper.wanted });
                }
                function measured(path, width, height) {
                    if (path !== wallpaper.newestPath) return;
                    if (!(width > 0 && height > 0)) {
                        WallpaperTransition.finish(bgRoot.modelData.name, path);
                        return;
                    }
                    wallpaperFader.show(path, width, height);
                }

                // Sizes already measured, so switching to a picture decoded ahead needs no process
                property var sizes: ({})
                // A preset decodes its picture before it covers the screen (WallpaperTransition.preload)
                Connections {
                    target: WallpaperTransition
                    function onPreloadRequested(path) {
                        if (bgRoot.wallpaperSafetyTriggered || path === wallpaper.newestPath) {
                            WallpaperTransition.reportPreloaded(bgRoot.modelData.name, path);
                            return;
                        }
                        const size = wallpaper.sizes[path];
                        if (size) wallpaper.preloadMeasured(path, size.width, size.height);
                        else sizeProbe.createObject(wallpaper, { "path": path, "preload": true });
                    }
                }
                function preloadMeasured(path, width, height) {
                    if (width > 0 && height > 0) wallpaperFader.preload(path, width, height);
                    else WallpaperTransition.reportPreloaded(bgRoot.modelData.name, path); // Nothing to wait for
                }

                WallpaperFader {
                    id: wallpaperFader
                    anchors.fill: parent
                    duration: ThemeTransition.presetTransition && ThemeTransition.phase === "holding" ? 0 : Appearance.scaledDuration(700)
                    devicePixelRatio: bgRoot.devicePixelRatio
                    zoom: bgRoot.parallaxRation
                    workspaceParallax: Config.options.background.parallax.enableWorkspace
                    autoVertical: Config.options.background.parallax.autoVertical
                    vertical: Config.options.background.parallax.vertical
                    workspaceFraction: wallpaper.fraction
                    sidebarOffset: Config.options.background.parallax.enableSidebar
                        ? bgRoot.parallaxRation / bgRoot.workspaceChunkSize / 2 * (GlobalStates.sidebarRightOpen - GlobalStates.sidebarLeftOpen) : 0
                    onPresented: path => WallpaperTransition.present(bgRoot.modelData.name, path, duration)
                    onFinished: path => {
                        WallpaperTransition.finish(bgRoot.modelData.name, path);
                        if (bgRoot.wallpaperIsVideo) videoTakeover.restart();
                    }
                    onFailed: path => WallpaperTransition.finish(bgRoot.modelData.name, path)
                    onPreloadReady: path => WallpaperTransition.reportPreloaded(bgRoot.modelData.name, path)
                }

                property int workspaceIndex: (bgRoot.monitor.activeWorkspace?.id ?? 1) - 1
                property real middleFraction: 0.5
                property real fraction: {
                    // 0 - start of the picture
                    // 1 - end of the picture
                    if (bgRoot.totalWorkspaces <= 1) {
                        return middleFraction;
                    }
                    return Math.max(0, Math.min(1, workspaceIndex / (bgRoot.totalWorkspaces - 1)));
                }

                width: bgRoot.width
                height: bgRoot.height

                // Animated wallpaper (ShaderWallpaper); on the first screen it also takes the still frame when one is wanted
                FadeLoader {
                    id: shaderLoader
                    z: 2
                    anchors.fill: parent
                    shown: ShaderWallpaper.active && !bgRoot.wallpaperSafetyTriggered
                    animation: NumberAnimation {
                        duration: Appearance.scaledDuration(1400)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standard
                    }
                    // The last animated wallpaper, still drawn while it fades out
                    property string shownName: ""
                    readonly property string activeName: ShaderWallpaper.active ? ShaderWallpaper.name : ""
                    onActiveNameChanged: if (activeName.length > 0) shownName = activeName
                    Component.onCompleted: if (activeName.length > 0) shownName = activeName
                    sourceComponent: ShaderWallpaperView {
                        id: shaderView
                        name: shaderLoader.shownName
                        running: bgRoot.shaderPlaying
                        speed: Config.options.background.shaderWallpaper.speed
                        fps: Config.options.background.shaderWallpaper.fps
                        colors: Config.options.background.shaderWallpaper.colors

                        readonly property bool takesFrame: ShaderWallpaper.framePending && bgRoot.modelData === Quickshell.screens[0]
                        onTakesFrameChanged: if (takesFrame) frameTimer.restart()
                        Component.onCompleted: if (takesFrame) frameTimer.restart()
                        Timer {
                            id: frameTimer
                            interval: 900 // Once it has drawn, at full resolution for the picture
                            onTriggered: {
                                shaderView.renderScale = 1;
                                Qt.callLater(() => {
                                    const ratio = bgRoot.modelData.devicePixelRatio ?? 1;
                                    shaderView.grabToImage(result => {
                                        const path = ShaderWallpaper.framePath(shaderView.name);
                                        Quickshell.execDetached(["mkdir", "-p", path.substring(0, path.lastIndexOf("/"))]);
                                        saveTimer.result = result;
                                        saveTimer.path = path;
                                        saveTimer.restart();
                                        shaderView.renderScale = 0.5;
                                    }, Qt.size(bgRoot.screen.width * ratio, bgRoot.screen.height * ratio));
                                });
                            }
                        }
                        Timer {
                            id: saveTimer
                            property var result
                            property string path
                            interval: 200 // After the folder exists
                            onTriggered: {
                                saveTimer.result.saveToFile(saveTimer.path);
                                ShaderWallpaper.frameSaved(saveTimer.path);
                            }
                        }
                    }
                }

                Loader {
                    z: 2
                    anchors.fill: parent
                    active: bgRoot.lockVideo
                    sourceComponent: Video {
                        source: `file://${Config.options.background.wallpaperPath}`
                        autoPlay: true
                        loops: MediaPlayer.Infinite
                        muted: true
                        fillMode: VideoOutput.PreserveAspectCrop
                    }
                }
            }

            Loader {
                id: blurLoader
                active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
                anchors.fill: wallpaper
                scale: bgRoot.lockedLook ? Config.options.lock.blur.extraZoom : 1
                opacity: bgRoot.lockedLook ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: Appearance.scaledDuration(400)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                // A playing video is blurred the cheap way (downscaled passes); a still picture renders once
                sourceComponent: (bgRoot.lockVideo || bgRoot.shaderPlaying) ? videoBlur : stillBlur
                Component {
                    id: stillBlur
                    GaussianBlur {
                        source: wallpaper
                        radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                        samples: radius * 2 + 1
                    }
                }
                Component {
                    id: videoBlur
                    MultiEffect {
                        source: wallpaper
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 64
                        blur: Math.min(1, Config.options.lock.blur.radius / 64)
                        blurMultiplier: Math.max(0, Config.options.lock.blur.radius / 64 - 1)
                    }
                }
            }
            Rectangle { // Darkens the wallpaper on the lock screen (Config.options.lock.dim)
                anchors.fill: wallpaper
                visible: opacity > 0
                opacity: bgRoot.lockedLook ? 1 : 0
                color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 1 - Math.max(0, Math.min(0.8, Config.options.lock.dim)))
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                visible: !bgRoot.coveredByFullscreen
                width: parent.width
                height: parent.height
                readonly property real parallaxFactor: {
                    var f = Config.options.background.parallax.widgetsFactor;
                    return f / bgRoot.parallaxRation;
                }
                readonly property bool locked: GlobalStates.screenLocked
                x: wallpaperFader.offsetX * parallaxFactor * !locked
                y: wallpaperFader.offsetY * parallaxFactor * !locked
                Behavior on x { NumberAnimation { duration: Appearance.scaledDuration(600); easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: Appearance.scaledDuration(600); easing.type: Easing.OutCubic } }

                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable && Config.options.background.widgets.weather.style !== "card"
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable && Config.options.background.widgets.weather.style === "card"
                    sourceComponent: WeatherCardWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.systemMonitor.enable
                    sourceComponent: SystemMonitorWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.media.enable
                    sourceComponent: MediaWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.calendar.enable
                    sourceComponent: CalendarDesktopWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.countdown.enable
                    sourceComponent: CountdownWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.note.enable
                    sourceComponent: NoteWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.pomodoro.enable
                    sourceComponent: PomodoroDesktopWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                    sourceComponent: ClockWidget {
                        screenName: bgRoot.modelData.name
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
            }
        }
    }
}
