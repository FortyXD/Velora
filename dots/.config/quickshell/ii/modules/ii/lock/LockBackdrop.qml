import QtQuick
import QtQuick.Effects
import QtMultimedia
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The lock screen and editor share this wallpaper: blurred, zoomed and darkened as in Config.options.lock.
 * A video wallpaper plays here when `playVideo` is enabled.
 */
Item {
    id: root
    property bool playVideo: false
    readonly property var lock: Config.options.lock
    readonly property string path: root.lock.backgroundPath || Config.options.background.wallpaperPath
    readonly property bool animatedImage: /\.(gif|webp)$/i.test(path)
    function mediaUrl(value) {
        if (!value || value.startsWith("file:")) return value;
        return value.startsWith("/") ? "file://" + value.split("/").map(encodeURIComponent).join("/") : Qt.resolvedUrl(value);
    }
    readonly property bool motion: root.playVideo && root.visible && root.lock.animatedWallpaper && !PowerSaving.pauseLiveWallpaper
    readonly property bool isVideo: FileUtils.isVideoPath(root.path)
    readonly property string still: root.isVideo ? (root.lock.backgroundPath ? "" : Config.options.background.thumbnailPath) : root.path
    readonly property var safety: Config.options.workSafety
    readonly property bool hideWallpaper: safety.enable.wallpaper
        && StringUtils.stringListContainsSubstring(path.toLowerCase(), safety.triggerCondition.fileKeywords)
        && StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), safety.triggerCondition.networkNameKeywords)
    clip: true

    Item {
        id: picture
        anchors.fill: parent
        layer.enabled: true
        scale: root.lock.blur.enable ? root.lock.blur.extraZoom : 1
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: root.lock.blur.enable
            blurMax: 64
            blur: Math.min(1, root.lock.blur.radius / 64)
            blurMultiplier: Math.max(0, root.lock.blur.radius / 64 - 1)
        }

        Image {
            anchors.fill: parent
            source: root.hideWallpaper || !root.still ? "" : root.mediaUrl(root.still)
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: Math.min(2560, root.width)
            asynchronous: true
            cache: false
        }
        AnimatedImage {
            anchors.fill: parent
            source: root.animatedImage && root.motion && !root.hideWallpaper ? root.mediaUrl(root.path) : ""
            fillMode: Image.PreserveAspectCrop
            playing: root.motion
            cache: false
            asynchronous: true
        }
        ShaderWallpaperView {
            anchors.fill: parent
            visible: !root.lock.backgroundPath && !root.hideWallpaper && ShaderWallpaper.active
            name: visible ? ShaderWallpaper.name : ""
            running: root.motion
            speed: Config.options.background.shaderWallpaper.speed
            fps: Config.options.background.shaderWallpaper.fps
            colors: Config.options.background.shaderWallpaper.colors
        }
        Loader {
            anchors.fill: parent
            active: root.isVideo && !root.hideWallpaper && (root.motion || !!root.lock.backgroundPath)
            sourceComponent: Item {
                VideoOutput { id: videoOutput; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
                MediaPlayer {
                    id: player
                    source: root.mediaUrl(root.path)
                    videoOutput: videoOutput
                    loops: MediaPlayer.Infinite
                    autoPlay: true
                }
                Connections {
                    target: videoOutput.videoSink
                    function onVideoFrameChanged() { if (!root.motion && player.playbackState === MediaPlayer.PlayingState) player.pause(); }
                }
                Connections {
                    target: root
                    function onMotionChanged() { if (root.motion) player.play(); else player.pause(); }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        opacity: Math.max(0, Math.min(0.8, root.lock.dim))
    }
}
