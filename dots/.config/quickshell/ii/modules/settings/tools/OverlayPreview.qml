import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.preview
import qs.modules.ii.overlay.crosshair

MiniScreen {
    id: root
    required property real progress
    readonly property real opening: Config.options.overlay.openingZoomAnimation ? progress : 1
    readonly property string selectedImage: Config.options.overlay.floatingImage.imageSource
    readonly property bool localImage: selectedImage.startsWith("/") || selectedImage.startsWith("file://") || selectedImage.startsWith("~/")
    radius: Appearance.rounding.small
    scrim: 0.06 + (Config.options.overlay.darkenScreen ? 0.50 * opening : 0)
    wallpaperItem.sourceSize: Qt.size(880, 0)

    Item {
        anchors.fill: parent
        opacity: root.opening
        scale: 0.79 + 0.21 * root.opening

        Rectangle {
            x: parent.width * 0.12; y: parent.height * 0.18
            width: parent.width * 0.29; height: parent.height * 0.46
            radius: 7
            color: Appearance.colors.colLayer2Base
            border.width: 1; border.color: Appearance.colors.colOutlineVariant
            Column {
                x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                Repeater {
                    model: [0.37, 0.74, 0.56]
                    Rectangle {
                        required property real modelData
                        width: (parent.parent.width - 16) * modelData; height: 3; radius: 2
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
        Rectangle {
            x: parent.width * 0.60; y: parent.height * 0.32
            width: parent.width * 0.26; height: parent.height * 0.51
            radius: 6
            color: ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colLayer2Base, 0.22)
            border.width: 1; border.color: Appearance.colors.colTertiary
            Image {
                id: referenceImage
                anchors { fill: parent; margins: 4 }
                asynchronous: true
                sourceSize: Qt.size(260, 180)
                fillMode: Image.PreserveAspectFit
                source: root.localImage ? root.selectedImage.replace(/^~/, FileUtils.trimFileProtocol(Directories.home)) : ""
            }
            MaterialSymbol {
                visible: referenceImage.status !== Image.Ready
                anchors.centerIn: parent
                text: "landscape"; iconSize: Math.min(38, parent.height * 0.7); color: Appearance.colors.colTertiary
            }
            MaterialSymbol {
                x: parent.width - width - 3; y: 3
                text: "keep"; fill: 1; iconSize: 13; color: Appearance.colors.colOnLayer2
            }
        }
        Item {
            anchors.centerIn: parent
            width: 42; height: 42; clip: true
            CrosshairContent { anchors.centerIn: parent }
        }
    }
}
