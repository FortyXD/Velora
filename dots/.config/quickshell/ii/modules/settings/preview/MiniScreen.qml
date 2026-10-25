import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A miniature of the screen with your wallpaper, in the screen's proportions, for previews
 * that draw the bar, windows or the dock on top. Children go over the wallpaper.
 */
Item {
    id: root
    readonly property var screen: Quickshell.screens[0] ?? null
    readonly property real aspect: root.screen && root.screen.height > 0 ? root.screen.width / root.screen.height : 16 / 10
    readonly property string wallpaper: {
        const path = Config.options.background.wallpaperPath;
        const isVideo = FileUtils.isVideoPath(path);
        return isVideo ? Config.options.background.thumbnailPath : path;
    }
    property real radius: Appearance.rounding.normal
    property real scrim: 0.1 // Darkens the wallpaper a little so what's drawn on it stands out
    // "top", "bottom", "left" or "right": only that edge of the screen, its size set from outside;
    // the wallpaper keeps the whole screen's proportions, so the strip shows what really is at that edge
    property string crop: ""
    readonly property bool cropped: root.crop.length > 0
    default property alias contentData: content.data
    readonly property alias wallpaperItem: wallpaperImage // For effects that show the wallpaper through something

    implicitHeight: root.cropped ? 0 : Math.round(width / root.aspect)

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: root.radius
        color: Appearance.colors.colLayer2
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: frame.width
                height: frame.height
                radius: frame.radius
            }
        }

        StyledImage {
            id: wallpaperImage
            readonly property bool alongWidth: root.crop === "top" || root.crop === "bottom"
            width: !root.cropped ? parent.width : wallpaperImage.alongWidth ? parent.width : Math.round(parent.height * root.aspect)
            height: !root.cropped ? parent.height : wallpaperImage.alongWidth ? Math.round(parent.width / root.aspect) : parent.height
            x: root.crop === "right" ? parent.width - width : 0
            y: root.crop === "bottom" ? parent.height - height : 0
            source: root.wallpaper
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: root.width * 2
            asynchronous: true
        }
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: root.scrim
        }
        Item {
            id: content
            anchors.fill: parent
        }
    }

    Rectangle { // Outline
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }
}
