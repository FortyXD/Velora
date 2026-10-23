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

        // Behind a fullscreen window the widgets stop drawing. The window itself stays mapped with the
        // wallpaper: unmapping it made the empty screen flash while it mapped again on leaving fullscreen.
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
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
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        readonly property real parallaxRation: Config.options.background.parallax.workspaceZoom
        property real minSuitableScale: 1 // Some reasonable init, to be updated
        property real effectiveWallpaperScale: minSuitableScale * parallaxRation
        property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
        property real scaledWallpaperWidth: wallpaperWidth * effectiveWallpaperScale
        property real scaledWallpaperHeight: wallpaperHeight * effectiveWallpaperScale
        property real parallaxTotalPixelsX: Math.max(0, scaledWallpaperWidth - screen.width)
        property real parallaxTotalPixelsY: Math.max(0, scaledWallpaperHeight - screen.height)
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Colors
        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

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

        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated
        }

        // Wallpaper zoom scale
        function updateZoomScale() {
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            command: ["magick", "identify", "-format", "%w %h", path]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    const [screenWidth, screenHeight] = [bgRoot.screen.width, bgRoot.screen.height];
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;

                    // Perfect image; scale = 1
                    // Small picture; scale > 1; will zoom in the picture
                    // Big picture; scale < 1; will zoom out the picture
                    // Choose max number so every side will fit
                    bgRoot.minSuitableScale = Math.max(screenWidth / width, screenHeight / height);
                }
            }
        }

        Item {
            anchors.fill: parent

            // Wallpaper
            StyledImage {
                id: wallpaper
                visible: opacity > 0 // Also under the blur, which fades out when unlocking
                // A video plays under this window (LiveWallpaper); its first frame stands in on the lock screen, where it pauses
                // An animated wallpaper draws inside this item, so it stays shown for it
                opacity: ((status === Image.Ready && (!bgRoot.wallpaperIsVideo || GlobalStates.screenLocked)) || ShaderWallpaper.active) ? 1 : 0
                cache: false
                smooth: false

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

                property real usedFractionX: {
                    let usedFraction = middleFraction;
                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                        usedFraction = fraction;
                    }
                    if (Config.options.background.parallax.enableSidebar) {
                        let sidebarFraction = bgRoot.parallaxRation / bgRoot.workspaceChunkSize / 2;
                        usedFraction += (sidebarFraction * GlobalStates.sidebarRightOpen - sidebarFraction * GlobalStates.sidebarLeftOpen);
                    }
                    return Math.max(0, Math.min(1, usedFraction));
                }
                property real usedFractionY: {
                    let usedFraction = middleFraction;
                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                        usedFraction = fraction;
                    }
                    return Math.max(0, Math.min(1, usedFraction));
                }

                x: {
                    if (bgRoot.screen.width > width) {
                        // Center the picture
                        return (bgRoot.screen.width - width) / 2;
                    }
                    return - bgRoot.parallaxTotalPixelsX * usedFractionX;
                }
                y: {
                    if (bgRoot.screen.height > height) {
                        // Center the picture
                        return (bgRoot.screen.height - height) / 2;
                    }
                    return - bgRoot.parallaxTotalPixelsY * usedFractionY;
                }

                source: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                fillMode: Image.PreserveAspectCrop
                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.scaledDuration(600)
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: Appearance.scaledDuration(600)
                        easing.type: Easing.OutCubic
                    }
                }
                width: bgRoot.scaledWallpaperWidth
                height: bgRoot.scaledWallpaperHeight

                // Animated wallpaper (ShaderWallpaper); on the first screen it also takes the still frame when one is wanted
                Loader {
                    id: shaderLoader
                    anchors.fill: parent
                    active: ShaderWallpaper.active && !bgRoot.wallpaperSafetyTriggered
                    sourceComponent: ShaderWallpaperView {
                        id: shaderView
                        name: ShaderWallpaper.name
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
                readonly property real baseWallpaperOffsetX: (bgRoot.screen.width - wallpaper.width) / 2
                readonly property real baseWallpaperOffsetY: (bgRoot.screen.height - wallpaper.height) / 2
                readonly property real wallpaperTotalOffsetX: wallpaper.x - baseWallpaperOffsetX
                readonly property real wallpaperTotalOffsetY: wallpaper.y - baseWallpaperOffsetY
                readonly property bool locked: GlobalStates.screenLocked
                x: wallpaperTotalOffsetX * parallaxFactor * !locked
                y: wallpaperTotalOffsetY * parallaxFactor * !locked

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
