import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    function folderUrl(path) {
        return path.length > 0 ? `file://${path.replace(/^~/, FileUtils.trimFileProtocol(Directories.home))}` : Directories.home;
    }

    FolderDialog {
        id: folderDialog
        property var onPicked: null
        onAccepted: if (folderDialog.onPicked) folderDialog.onPicked(FileUtils.trimFileProtocol(decodeURIComponent(selectedFolder.toString())))
    }
    function pickFolder(current, callback) {
        folderDialog.currentFolder = root.folderUrl(current);
        folderDialog.onPicked = callback;
        folderDialog.open();
    }

    FileDialog {
        id: imageDialog
        nameFilters: [Translation.tr("Images (*.png *.jpg *.jpeg *.gif *.webp *.svg)"), Translation.tr("All files (*)")]
        onAccepted: Config.options.overlay.floatingImage.imageSource = FileUtils.trimFileProtocol(decodeURIComponent(selectedFile.toString()))
    }

    ContentSection {
        icon: "screenshot_frame_2"
        title: Translation.tr("Screen selection")
        description: Translation.tr("Used for screenshots, recording a region and Google Lens")

        ContentSubsection {
            title: Translation.tr("Hint target regions")
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "select_window"
                    text: Translation.tr('Windows')
                    checked: Config.options.regionSelector.targetRegions.windows
                    onCheckedChanged: {
                        Config.options.regionSelector.targetRegions.windows = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "right_panel_open"
                    text: Translation.tr('Layers')
                    checked: Config.options.regionSelector.targetRegions.layers
                    onCheckedChanged: {
                        Config.options.regionSelector.targetRegions.layers = checked;
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "nearby"
                text: Translation.tr('Content')
                description: Translation.tr("Could be images or parts of the screen that have some containment. Might not always be accurate. This is done with an image processing algorithm run locally and no AI is used.")
                checked: Config.options.regionSelector.targetRegions.content
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.content = checked;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Google Lens")
            ConfigSelectionArray {
                currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                onSelected: newValue => {
                    Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                }
                options: [
                    { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular selection") },
                    { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "point_scan"
            text: Translation.tr("Show aim lines")
            description: Translation.tr("For rectangular selection")
            checked: Config.options.regionSelector.rect.showAimLines
            onCheckedChanged: {
                Config.options.regionSelector.rect.showAimLines = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Circle selection")
            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "eraser_size_3"
                    text: Translation.tr("Stroke width")
                    value: Config.options.regionSelector.circle.strokeWidth
                    from: 1
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.regionSelector.circle.strokeWidth = value;
                    }
                }
                ConfigSpinBox {
                    icon: "screenshot_frame_2"
                    text: Translation.tr("Padding")
                    value: Config.options.regionSelector.circle.padding
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.options.regionSelector.circle.padding = value;
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "file_open"
        title: Translation.tr("Save paths")
        description: Translation.tr("Where screenshots and recordings go")

        ConfigNavRow {
            buttonIcon: "videocam"
            title: Translation.tr("Recordings")
            description: Config.options.screenRecord.savePath
            trailingIcon: "folder_open"
            onClicked: root.pickFolder(Config.options.screenRecord.savePath, path => Config.options.screenRecord.savePath = path)
        }
        ConfigSwitch {
            buttonIcon: "screenshot"
            text: Translation.tr("Save screenshots to a folder")
            description: Translation.tr("Otherwise they are only copied to the clipboard")
            autoToggle: false
            checked: Config.options.screenSnip.savePath.length > 0
            onClicked: {
                if (checked) Config.options.screenSnip.savePath = "";
                else root.pickFolder(FileUtils.trimFileProtocol(Directories.pictures), path => Config.options.screenSnip.savePath = path);
            }
        }
        ConfigNavRow {
            visible: Config.options.screenSnip.savePath.length > 0
            buttonIcon: "folder"
            title: Translation.tr("Screenshots")
            description: Config.options.screenSnip.savePath
            trailingIcon: "folder_open"
            onClicked: root.pickFolder(Config.options.screenSnip.savePath, path => Config.options.screenSnip.savePath = path)
        }
    }

    ContentSection {
        icon: "select_window"
        title: Translation.tr("Overlay")
        description: Translation.tr("Floating widgets opened with Super+G")

        ConfigSwitch {
            buttonIcon: "high_density"
            text: Translation.tr("Enable opening zoom animation")
            checked: Config.options.overlay.openingZoomAnimation
            onCheckedChanged: {
                Config.options.overlay.openingZoomAnimation = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "texture"
            text: Translation.tr("Darken screen")
            checked: Config.options.overlay.darkenScreen
            onCheckedChanged: {
                Config.options.overlay.darkenScreen = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Crosshair")
            description: Translation.tr("Press Super+G to open the overlay and pin the crosshair")
            ConfigTextRow {
                monospace: true
                placeholderText: Translation.tr("Crosshair code (in Valorant's format)")
                value: Config.options.crosshair.code
                onValueChanged: {
                    Config.options.crosshair.code = value;
                }
            }
            RippleButtonWithIcon {
                Layout.leftMargin: 12
                Layout.bottomMargin: 6
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open editor")
                onClicked: {
                    Qt.openUrlExternally(`https://www.vcrdb.net/builder?c=${Config.options.crosshair.code}`);
                }
                StyledToolTip {
                    text: "www.vcrdb.net"
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Floating image")
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                ConfigTextRow {
                    placeholderText: Translation.tr("Image file or link")
                    description: Translation.tr("Press Enter to apply")
                    wrapMode: TextEdit.NoWrap
                    value: Config.options.overlay.floatingImage.imageSource
                    onEditingFinished: Config.options.overlay.floatingImage.imageSource = value.trim()
                }
                RippleButtonWithIcon {
                    Layout.rightMargin: 12
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    materialIcon: "image"
                    mainText: Translation.tr("Choose file")
                    onClicked: imageDialog.open()
                }
            }
        }
    }
}
