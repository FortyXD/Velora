import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
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

        ConfigTextRow {
            icon: "videocam"
            label: Translation.tr("Video Recording Path")
            value: Config.options.screenRecord.savePath
            wrapMode: TextEdit.NoWrap
            onValueChanged: {
                Config.options.screenRecord.savePath = value;
            }
        }
        ConfigTextRow {
            icon: "screenshot"
            label: Translation.tr("Screenshot path")
            description: Translation.tr("Leave empty to just copy to the clipboard")
            value: Config.options.screenSnip.savePath
            wrapMode: TextEdit.NoWrap
            onValueChanged: {
                Config.options.screenSnip.savePath = value;
            }
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
            ConfigTextRow {
                placeholderText: Translation.tr("Image source")
                value: Config.options.overlay.floatingImage.imageSource
                onValueChanged: {
                    Config.options.overlay.floatingImage.imageSource = value;
                }
            }
        }
    }
}
