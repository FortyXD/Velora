import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A remote image, fetched with curl into the cache first: some image hosts stall Qt's own loader,
 * and curl gives up on a stalled transfer. The URL is passed as an argument, never as code.
 * Used for online wallpaper and preset previews.
 */
Item {
    id: root

    required property string url
    readonly property string cachePath: `${OnlineWallpapers.thumbnailDir}/${Qt.md5(url)}`
    property bool failed: false
    property alias fillMode: image.fillMode
    readonly property bool ready: image.status === Image.Ready

    Process {
        id: fetch
        running: root.url.length > 0
        command: ["bash", "-c",
            '[ -s "$2" ] || { mkdir -p "$(dirname "$2")" && curl -sSL --fail --connect-timeout 8 --speed-limit 1024 --speed-time 10 --max-time 40 -A "$3" -o "$2.part" -- "$1" && mv -f "$2.part" "$2"; } || { rm -f "$2.part"; exit 1; }',
            "_", root.url, root.cachePath, OnlineWallpapers.userAgent]
        onExited: exitCode => {
            if (exitCode === 0) {
                image.source = "";
                image.source = `file://${root.cachePath}`;
            } else {
                root.failed = true;
            }
        }
    }

    StyledImage {
        id: image
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.width * 2
        sourceSize.height: root.height * 2
        opacity: root.ready ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: !root.ready
        text: root.failed ? "broken_image" : "hourglass_empty"
        iconSize: 28
        color: Appearance.colors.colSubtext
    }
}
