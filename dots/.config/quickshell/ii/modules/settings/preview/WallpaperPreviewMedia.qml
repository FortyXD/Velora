pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// A preview owns its player. Leaving its page releases the decoder and freezes shader time.
Rectangle {
    id: root
    required property bool active
    property string picture: currentPicture
    readonly property string currentPicture: FileUtils.wallpaperPicture(Config.options.background.wallpaperPath,
        Config.options.background.thumbnailPath)
    property string video: FileUtils.isVideoPath(Config.options.background.wallpaperPath) ? Config.options.background.wallpaperPath : ""
    property string shaderName: ShaderWallpaper.active ? ShaderWallpaper.name : ""
    property var shaderColors: Config.options.background.shaderWallpaper.colors
    property real speed: Config.options.background.shaderWallpaper.speed
    property int fps: Config.options.background.shaderWallpaper.fps
    property bool playVideo: false
    property bool crossfadePictures: false
    property real zoom: 1
    property real fractionX: 0.5
    property real fractionY: 0.5
    readonly property real offsetX: pictureItem.x - (width - pictureItem.width) / 2
    readonly property real offsetY: pictureItem.y - (height - pictureItem.height) / 2
    readonly property bool portrait: pictureItem.implicitHeight > pictureItem.implicitWidth
    readonly property bool motionAllowed: active && Appearance.animationSpeed > 0 && !PowerSaving.pauseLiveWallpaper
    readonly property bool remote: /^https?:\/\//.test(picture)
    readonly property bool hasShader: !!ShaderWallpaper.shader(shaderName)
    readonly property bool unavailable: !remote && !hasShader && (pictureItem.status === Image.Error || !picture) && !movie.item?.hasVideo
    readonly property bool settled: hasShader || (remote ? (remoteImages.itemAt(0)?.ready || remoteImages.itemAt(0)?.failed || false)
        : !picture || pictureItem.status === Image.Ready || pictureItem.status === Image.Error)
    signal playbackFailed()

    clip: true
    color: Appearance.colors.colLayer3

    WallpaperGeometry {
        id: geometry
        viewportWidth: root.width
        viewportHeight: root.height
        imageWidth: pictureItem.implicitWidth
        imageHeight: pictureItem.implicitHeight
        zoom: root.zoom
    }
    Image {
        id: pictureItem
        objectName: "wallpaperPreviewPicture"
        source: root.remote ? "" : FileUtils.fileUrl(root.picture)
        asynchronous: true
        retainWhileLoading: true
        autoTransform: true
        // Resizing or dragging the divider should not queue a new image decode for each pixel.
        sourceSize: Qt.size(root.width <= 400 ? 800 : 1536, 0)
        width: geometry.scaledWidth
        height: geometry.scaledHeight
        x: -(width - root.width) * ColorUtils.clamp01(root.fractionX)
        y: -(height - root.height) * ColorUtils.clamp01(root.fractionY)
        property string lastReady: ""
        onStatusChanged: {
            if (status !== Image.Ready) return;
            const next = source.toString();
            if (root.crossfadePictures && root.motionAllowed && !root.hasShader && lastReady && next !== lastReady) {
                dissolve.stop();
                previous.source = lastReady;
                dissolve.start();
            }
            lastReady = next;
        }
    }
    WallpaperGeometry {
        id: previousGeometry
        viewportWidth: root.width; viewportHeight: root.height
        imageWidth: previous.implicitWidth; imageHeight: previous.implicitHeight
        zoom: root.zoom
    }
    Image {
        id: previous
        visible: opacity > 0
        opacity: 0
        autoTransform: true
        sourceSize: pictureItem.sourceSize
        width: previousGeometry.scaledWidth; height: previousGeometry.scaledHeight
        x: -(width - root.width) * ColorUtils.clamp01(root.fractionX)
        y: -(height - root.height) * ColorUtils.clamp01(root.fractionY)
    }
    NumberAnimation {
        id: dissolve
        target: previous; property: "opacity"; from: 1; to: 0
        duration: Appearance.scaledDuration(300); easing.type: Easing.InOutSine
        onStopped: { previous.opacity = 0; previous.source = ""; }
    }
    onMotionAllowedChanged: if (!motionAllowed) dissolve.stop()
    Repeater {
        id: remoteImages
        model: root.remote ? [root.picture] : []
        delegate: RemoteImage {
            required property string modelData
            anchors.fill: parent
            url: modelData
        }
    }
    MaterialSymbol {
        visible: root.unavailable
        anchors.centerIn: parent
        text: "hide_image"
        iconSize: 34
        color: Appearance.colors.colSubtext
        Accessible.name: Translation.tr("Wallpaper preview unavailable")
    }
    Loader {
        anchors.fill: parent
        active: root.hasShader
        sourceComponent: ShaderWallpaperView {
            name: root.shaderName
            colors: root.shaderColors
            speed: root.speed
            fps: root.fps
            running: root.motionAllowed
        }
    }
    Loader {
        id: movie
        objectName: "wallpaperPreviewPlayer"
        anchors.fill: parent
        active: root.motionAllowed && root.playVideo && !root.hasShader && root.video.length > 0
        sourceComponent: Video {
            source: FileUtils.fileUrl(root.video)
            autoPlay: true
            muted: true
            loops: MediaPlayer.Infinite
            fillMode: VideoOutput.PreserveAspectCrop
            visible: hasVideo && playbackState === MediaPlayer.PlayingState
            onErrorOccurred: {
                const failedVideo = root.video;
                Qt.callLater(() => { if (root.playVideo && root.video === failedVideo) root.playbackFailed(); });
            }
        }
    }
}
