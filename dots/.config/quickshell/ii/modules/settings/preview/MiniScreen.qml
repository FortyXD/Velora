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
    default property alias contentData: content.data
    readonly property alias wallpaperItem: wallpaperImage // For effects that show the wallpaper through something

    implicitHeight: Math.round(width / root.aspect)

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
            anchors.fill: parent
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
