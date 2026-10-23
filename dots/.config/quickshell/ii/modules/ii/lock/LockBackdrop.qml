import QtQuick
import QtQuick.Effects
import QtMultimedia
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The lock screen's wallpaper for previews: blurred, zoomed and darkened as in Config.options.lock.
 * A video wallpaper plays here when `playVideo` (the real lock screen does this in Background.qml).
 */
Item {
    id: root
    property bool playVideo: false
    readonly property var lock: Config.options.lock
    readonly property string path: Config.options.background.wallpaperPath
    readonly property bool isVideo: FileUtils.isVideoPath(root.path)
    readonly property string still: root.isVideo ? Config.options.background.thumbnailPath : root.path
    clip: true

    Item {
        id: picture
        anchors.fill: parent
        visible: false

        Image {
            anchors.fill: parent
            source: root.still.length === 0 ? "" : root.still.startsWith("/") ? `file://${root.still}` : root.still
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: Math.min(2560, root.width)
            asynchronous: true
            cache: false
        }
        ShaderWallpaperView {
            anchors.fill: parent
            visible: ShaderWallpaper.active
            name: ShaderWallpaper.active ? ShaderWallpaper.name : ""
            running: root.playVideo && root.lock.animatedWallpaper && !PowerSaving.pauseLiveWallpaper
            speed: Config.options.background.shaderWallpaper.speed
            fps: Config.options.background.shaderWallpaper.fps
            colors: Config.options.background.shaderWallpaper.colors
        }
        Loader {
            anchors.fill: parent
            active: root.playVideo && root.isVideo && root.lock.animatedWallpaper && !PowerSaving.pauseLiveWallpaper
            sourceComponent: Video {
                source: root.path.startsWith("/") ? `file://${root.path}` : root.path
                autoPlay: true
                loops: MediaPlayer.Infinite
                muted: true
                fillMode: VideoOutput.PreserveAspectCrop
            }
        }
    }

    MultiEffect {
        anchors.fill: picture
        source: picture
        autoPaddingEnabled: false
        blurEnabled: root.lock.blur.enable
        blurMax: 64
        blur: Math.min(1, root.lock.blur.radius / 64)
        blurMultiplier: Math.max(0, root.lock.blur.radius / 64 - 1) // Past 64 px the blur gets coarser, as on the lock screen
        scale: root.lock.blur.enable ? root.lock.blur.extraZoom : 1
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        opacity: Math.max(0, Math.min(0.8, root.lock.dim))
    }
}
