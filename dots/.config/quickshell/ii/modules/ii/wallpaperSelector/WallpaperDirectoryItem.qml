import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

MouseArea {
    id: root
    required property var fileModelData
    property bool isDirectory: fileModelData.fileIsDir
    property bool isVideo: !isDirectory && LiveWallpaper.isVideoPath(fileModelData.fileName)
    property bool useThumbnail: !isDirectory && (Images.isValidImageByName(fileModelData.fileName) || isVideo)

    property alias colBackground: background.color
    property alias colText: wallpaperItemName.color
    property alias radius: background.radius
    property alias margins: background.anchors.margins
    property alias padding: wallpaperItemColumnLayout.anchors.margins
    margins: Appearance.sizes.wallpaperSelectorItemMargins
    padding: Appearance.sizes.wallpaperSelectorItemPadding

    signal activated()

    hoverEnabled: true
    onClicked: root.activated()

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Appearance.rounding.normal
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            id: wallpaperItemColumnLayout
            anchors.fill: parent
            spacing: 4

            Item {
                id: wallpaperItemImageContainer
                Layout.fillHeight: true
                Layout.fillWidth: true

                Loader {
                    id: thumbnailShadowLoader
                    active: thumbnailImageLoader.active && thumbnailImageLoader.item.status === Image.Ready
                    anchors.fill: thumbnailImageLoader
                    sourceComponent: StyledRectangularShadow {
                        target: thumbnailImageLoader
                        anchors.fill: undefined
                        radius: Appearance.rounding.small
                    }
                }

                Loader {
                    id: thumbnailImageLoader
                    anchors.fill: parent
                    active: root.useThumbnail
                    sourceComponent: ThumbnailImage {
                        id: thumbnailImage
                        generateThumbnail: false
                        sourcePath: fileModelData.filePath

                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        clip: true

                        Connections {
                            target: Wallpapers
                            function onThumbnailGenerated(directory) {
                                if (thumbnailImage.status !== Image.Error) return;
                                if (FileUtils.parentDirectory(thumbnailImage.sourcePath) !== FileUtils.trimFileProtocol(directory)) return;
                                thumbnailImage.source = "";
                                thumbnailImage.source = thumbnailImage.thumbnailPath;
                            }
                            function onThumbnailGeneratedFile(filePath) {
                                if (thumbnailImage.status !== Image.Error) return;
                                if (Qt.resolvedUrl(thumbnailImage.sourcePath) !== Qt.resolvedUrl(filePath)) return;
                                thumbnailImage.source = "";
                                thumbnailImage.source = thumbnailImage.thumbnailPath;
                            }
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: wallpaperItemImageContainer.width
                                height: wallpaperItemImageContainer.height
                                radius: Appearance.rounding.small
                            }
                        }
                    }
                }

                Rectangle { // Videos become live wallpapers
                    visible: root.isVideo
                    anchors {
                        left: parent.left
                        top: parent.top
                        margins: 6
                    }
                    implicitWidth: liveRow.implicitWidth + 12
                    implicitHeight: liveRow.implicitHeight + 4
                    radius: Appearance.rounding.full
                    color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.15)
                    Row {
                        id: liveRow
                        anchors.centerIn: parent
                        spacing: 2
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "play_circle"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Live")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.variableAxes: ({ "wght": 600 })
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }

                Loader {
                    id: iconLoader
                    active: !root.useThumbnail
                    anchors.fill: parent
                    sourceComponent: root.isDirectory ? folderIcon : fileIcon
                    Component {
                        id: folderIcon
                        MaterialSymbol {
                            text: "folder"
                            fill: 1
                            iconSize: Math.min(width, height) * 0.65
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: root.colText
                        }
                    }
                    Component {
                        id: fileIcon
                        DirectoryIcon {
                            fileModelData: root.fileModelData
                            color: root.colText
                        }
                    }
                }
            }

            StyledText {
                id: wallpaperItemName
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                text: fileModelData.fileName
            }
        }
    }
}
