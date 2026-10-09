import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root

    readonly property string wallpaperPath: {
        const path = Config.options.background.wallpaperPath;
        const isVideo = [".mp4", ".webm", ".mkv", ".avi", ".mov"].some(ext => path.endsWith(ext));
        return isVideo ? Config.options.background.thumbnailPath : path;
    }

    // Detached so the download survives switching settings pages or closing the window.
    // The script reports progress and errors through notifications.
    function runRandomWallpaperScript(scriptName) {
        Quickshell.execDetached([FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/random/${scriptName}`)]);
    }

    function setDarkMode(dark) {
        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "dark" : "light"} --noswitch`]);
    }

    // Button on top of the wallpaper preview
    component HeroButton: RippleButton {
        id: heroButton
        property string buttonIcon
        property string label
        implicitHeight: 38
        leftPadding: 12
        rightPadding: 14
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.12)
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.04)
        colRipple: Appearance.colors.colLayer1Active
        contentItem: RowLayout {
            spacing: 8
            MaterialSymbol {
                text: heroButton.buttonIcon
                iconSize: 20
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                text: heroButton.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
            }
        }
    }

    ContentSection {
        title: Translation.tr("Current wallpaper")
        description: Translation.tr("The colors of the whole desktop are generated from it")

        Item { // Preview with actions on top
            id: hero
            Layout.fillWidth: true
            implicitHeight: Math.min(340, Math.round(width * 9 / 16))

            StyledImage {
                id: wallpaperPreview
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: root.wallpaperPath
                sourceSize.width: hero.width * 2
                cache: false
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: wallpaperPreview.width
                        height: wallpaperPreview.height
                        radius: Appearance.rounding.normal - 4
                    }
                }
            }
            Rectangle { // Shade so the buttons stay readable
                anchors.fill: parent
                radius: Appearance.rounding.normal - 4
                gradient: Gradient {
                    GradientStop { position: 0.45; color: "transparent" }
                    GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.45) }
                }
            }

            // Light / dark
            Rectangle {
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 12
                }
                implicitWidth: modeRow.implicitWidth + 8
                implicitHeight: modeRow.implicitHeight + 8
                radius: Appearance.rounding.full
                color: ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.12)
                RowLayout {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: [
                            { dark: false, icon: "light_mode", name: Translation.tr("Light") },
                            { dark: true, icon: "dark_mode", name: Translation.tr("Dark") }
                        ]
                        delegate: RippleButton {
                            id: modeButton
                            required property var modelData
                            readonly property bool selected: Appearance.m3colors.darkmode === modelData.dark
                            implicitHeight: 34
                            leftPadding: 12
                            rightPadding: 14
                            buttonRadius: Appearance.rounding.full
                            toggled: selected
                            colBackgroundToggled: Appearance.colors.colPrimary
                            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                            onClicked: root.setDarkMode(modelData.dark)
                            contentItem: RowLayout {
                                spacing: 6
                                MaterialSymbol {
                                    text: modeButton.modelData.icon
                                    iconSize: 20
                                    fill: modeButton.selected ? 1 : 0
                                    color: modeButton.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    text: modeButton.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: modeButton.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                                }
                            }
                        }
                    }
                }
            }

            Flow {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    margins: 12
                }
                spacing: 6
                HeroButton {
                    buttonIcon: "wallpaper"
                    label: Translation.tr("Choose wallpaper")
                    onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath])
                    StyledToolTip {
                        text: Translation.tr("Pick a wallpaper image on your system")
                    }
                }
                HeroButton {
                    visible: Config.options.policies.weeb === 1
                    buttonIcon: "ifl"
                    label: Translation.tr("Random: Wallhaven")
                    onClicked: root.runRandomWallpaperScript("random_wallhaven_wall.sh")
                    StyledToolTip {
                        text: Translation.tr("Random SFW anime wallpaper from Wallhaven\nImage is saved to ~/Pictures/Wallpapers")
                    }
                }
                HeroButton {
                    visible: Config.options.policies.weeb === 1
                    buttonIcon: "ifl"
                    label: Translation.tr("Random: Konachan")
                    onClicked: root.runRandomWallpaperScript("random_konachan_wall.sh")
                    StyledToolTip {
                        text: Translation.tr("Random SFW anime wallpaper from Konachan (may need a VPN)\nImage is saved to ~/Pictures/Wallpapers")
                    }
                }
            }
        }

        ConfigNavRow {
            buttonIcon: "palette"
            title: Translation.tr("Color palette and theming")
            onClicked: ApplicationWindow.window?.openPage("appearance", Translation.tr("Theme"))
        }
    }

    ContentSection {
        title: Translation.tr("Choosing wallpapers")

        ConfigSwitch {
            buttonIcon: "ad"
            text: Translation.tr("Use system file picker")
            description: Translation.tr("For the wallpaper selector instead of the built-in grid")
            checked: Config.options.wallpaperSelector.useSystemFileDialog
            onCheckedChanged: {
                Config.options.wallpaperSelector.useSystemFileDialog = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "fullscreen"
            text: Translation.tr("Hide wallpaper and widgets behind fullscreen windows")
            checked: Config.options.background.hideWhenFullscreen
            onCheckedChanged: {
                Config.options.background.hideWhenFullscreen = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Parallax")
        description: Translation.tr("The wallpaper shifts slightly as you move between workspaces or open sidebars")

        ConfigSwitch {
            buttonIcon: "counter_1"
            text: Translation.tr("Depends on workspace")
            checked: Config.options.background.parallax.enableWorkspace
            onCheckedChanged: {
                Config.options.background.parallax.enableWorkspace = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "side_navigation"
            text: Translation.tr("Depends on sidebars")
            checked: Config.options.background.parallax.enableSidebar
            onCheckedChanged: {
                Config.options.background.parallax.enableSidebar = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "unfold_more_double"
            text: Translation.tr("Vertical")
            checked: Config.options.background.parallax.vertical
            onCheckedChanged: {
                Config.options.background.parallax.vertical = checked;
            }
        }
        ConfigSpinBox {
            icon: "loupe"
            text: Translation.tr("Preferred wallpaper zoom (%)")
            value: Config.options.background.parallax.workspaceZoom * 100
            from: 10
            to: 200
            stepSize: 1
            onValueChanged: {
                Config.options.background.parallax.workspaceZoom = value / 100;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Widgets on the wallpaper")

        ConfigNavRow {
            buttonIcon: "widgets"
            title: Translation.tr("Desktop widgets")
            description: Translation.tr("Clock, weather, system monitor, media, calendar, notes and more")
            onClicked: ApplicationWindow.window?.openPage("widgets")
        }
    }
}
