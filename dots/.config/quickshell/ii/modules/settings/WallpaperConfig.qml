import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview

SettingsDetailPage {
    id: root
    sectionTitles: ({
        motion: Translation.tr("Motion"),
        greeter: Translation.tr("Login screen wallpaper")
    })
    property string greeterOwner: ""
    FileView {
        path: "/etc/velora/greeter-wallpaper.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.greeterOwner = JSON.parse(text()).owner_name ?? ""; }
            catch (error) { root.greeterOwner = ""; }
        }
        onLoadFailed: root.greeterOwner = ""
    }

    // Detached so the download survives switching settings pages or closing the window.
    // The script reports progress and errors through notifications.
    function runRandomWallpaperScript(scriptName) {
        Quickshell.execDetached([FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/random/${scriptName}`)]);
    }

    function chooseVideo() {
        Quickshell.execDetached(["bash", "-c",
            'file=$(kdialog --getopenfilename "$1" "Videos (*.mp4 *.webm *.mkv *.mov *.avi)" --title "$2") && [ -n "$file" ] && exec "$3" --image "$file"',
            "choose-video", FileUtils.localPath(Directories.videos), Translation.tr("Choose a live wallpaper"), Directories.wallpaperSwitchScriptPath]);
    }

    function setDarkMode(dark) {
        Quickshell.execDetached(["bash", Directories.wallpaperSwitchScriptPath, "--mode", dark ? "dark" : "light", "--noswitch"]);
    }

    function dismissPreview() {
        if (!overview.shown || !gallery.chosen) return false;
        gallery.chosenKey = "";
        return true;
    }

    component DetailTile: SettingsBranchLink {
        Layout.minimumWidth: 0
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        colBackground: Appearance.colors.colLayer2
        description: summary
        valueText: ""
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        SettingsBranch {
            id: overview
            page: root
            key: "overview"

            WallpaperGallery {
                id: gallery
                pageShown: root.pageShown && overview.shown
                onBrowse: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath])
                onApplyRequested: path => Wallpapers.apply(path)
                onShaderRequested: (name, colors) => ShaderWallpaper.requestWithColors(name, colors)
                onVideoRequested: root.chooseVideo()
                onPreviewSelected: root.revealItem(gallery, false)
                onRandomRequested: provider => root.runRandomWallpaperScript(provider === "wallhaven"
                    ? "random_wallhaven_wall.sh" : "random_konachan_wall.sh")
            }
            Process { // Live wallpapers are played by mpvpaper
                id: mpvpaperCheck
                property bool found: true
                running: true
                command: ["sh", "-c", "command -v mpvpaper"]
                onExited: exitCode => mpvpaperCheck.found = exitCode === 0
            }
            NoticeBox {
                visible: !mpvpaperCheck.found
                Layout.fillWidth: true
                materialIcon: "download"
                text: Translation.tr("Live wallpapers need mpvpaper. Install it with: yay -S mpvpaper")
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 515 ? 2 : 1
                uniformCellWidths: true
                columnSpacing: 8; rowSpacing: 6
                DetailTile {
                    branch: motionBranch
                    buttonIcon: "animation"
                    tileColor: ColorUtils.mix(Appearance.colors.colPrimary, "#78699e", 0.45)
                    summary: Translation.tr("Playback and parallax")
                }
                DetailTile {
                    branch: greeterBranch
                    buttonIcon: "login"
                    tileColor: ColorUtils.mix(Appearance.colors.colPrimary, "#86613f", 0.4)
                    summary: root.greeterOwner || Translation.tr("Available with the Velora GDM theme")
                }
            }
            ContentSection {
                title: Translation.tr("Appearance")
                ConfigSelectionArray {
                    currentValue: Appearance.m3colors.darkmode
                    onSelected: value => root.setDarkMode(value)
                    options: [
                        { displayName: Translation.tr("Light"), icon: "light_mode", value: false },
                        { displayName: Translation.tr("Dark"), icon: "dark_mode", value: true }
                    ]
                }
                ConfigNavRow {
                    buttonIcon: "palette"
                    title: Translation.tr("Color palette and theming")
                    onClicked: ApplicationWindow.window?.openPage("appearance", Translation.tr("Colors"))
                }
                ConfigNavRow {
                    buttonIcon: "widgets"
                    title: Translation.tr("Desktop widgets")
                    description: Translation.tr("Clock, weather, system monitor, media, calendar, notes and more")
                    onClicked: ApplicationWindow.window?.openPage("widgets")
                }
            }
        }
        SettingsBranch {
            id: motionBranch
            page: root
            key: "motion"

            ContentSection {
                title: Translation.tr("Parallax")
                description: Translation.tr("The wallpaper shifts slightly as you move between workspaces or open sidebars")

                ConfigSwitch {
                    buttonIcon: "counter_1"
                    text: Translation.tr("Depends on workspace")
                    autoToggle: false
                    checked: Config.options.background.parallax.enableWorkspace
                    onClicked: Config.options.background.parallax.enableWorkspace = !checked
                }
                ConfigSwitch {
                    buttonIcon: "side_navigation"
                    text: Translation.tr("Depends on sidebars")
                    autoToggle: false
                    checked: Config.options.background.parallax.enableSidebar
                    onClicked: Config.options.background.parallax.enableSidebar = !checked
                }
                ConfigSwitch {
                    objectName: "verticalParallax"
                    buttonIcon: "unfold_more_double"
                    text: Translation.tr("Vertical")
                    autoToggle: false
                    checked: Config.options.background.parallax.vertical
                    onClicked: Config.options.background.parallax.vertical = !checked
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
                icon: "animation"
                title: Translation.tr("Animated wallpaper")
                visible: ShaderWallpaper.active

                ContentSubsection {
                    title: Translation.tr("Colors")
                    ConfigSelectionArray {
                        currentValue: Config.options.background.shaderWallpaper.colors.length > 0 ? "own" : "theme"
                        onSelected: newValue => {
                            Config.options.background.shaderWallpaper.colors = newValue === "own" ? (ShaderWallpaper.shader(ShaderWallpaper.name)?.colors ?? []) : [];
                        }
                        options: [
                            { displayName: Translation.tr("Its own"), icon: "palette", value: "own" },
                            { displayName: Translation.tr("From the theme"), icon: "format_color_fill", value: "theme" }
                        ]
                    }
                }
                ConfigSlider {
                    buttonIcon: "speed"
                    text: Translation.tr("Speed")
                    usePercentTooltip: false
                    from: 0.25
                    to: 3
                    defaultValue: 1
                    defaultValueText: "100%"
                    value: Config.options.background.shaderWallpaper.speed
                    valueText: `${Math.round(value * 100)}%`
                    onMoved: Config.options.background.shaderWallpaper.speed = Math.round(value * 20) / 20
                }
                ContentSubsection {
                    title: Translation.tr("Smoothness")
                    description: Translation.tr("More frames per second look smoother and use more power")
                    ConfigSelectionArray {
                        currentValue: Config.options.background.shaderWallpaper.fps
                        onSelected: newValue => Config.options.background.shaderWallpaper.fps = newValue
                        options: [
                            { displayName: Translation.tr("Calm (15)"), icon: "energy_savings_leaf", value: 15 },
                            { displayName: Translation.tr("Smooth (30)"), icon: "animation", value: 30 },
                            { displayName: Translation.tr("Fluid (60)"), icon: "bolt", value: 60 }
                        ]
                    }
                }
            }

            ContentSection {
                icon: "motion_photos_on"
                title: Translation.tr("Video playback")
                ContentSubsection {
                    title: Translation.tr("Decoding")
                    searchText: `${title} GPU CPU ${Translation.tr("Graphics chip")} ${Translation.tr("Processor")}`
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        SchemeTile {
                            id: gpuTile
                            label: Translation.tr("Graphics chip")
                            frameWidth: 112
                            frameHeight: 70
                            selected: Config.options.background.liveWallpaper.decoder !== "cpu"
                            onClicked: Config.options.background.liveWallpaper.decoder = "gpu"
                            MaterialSymbol { anchors.centerIn: parent; text: "memory"; iconSize: 32; color: gpuTile.ink }
                        }
                        SchemeTile {
                            id: cpuTile
                            label: Translation.tr("Processor")
                            frameWidth: 112
                            frameHeight: 70
                            selected: Config.options.background.liveWallpaper.decoder === "cpu"
                            onClicked: Config.options.background.liveWallpaper.decoder = "cpu"
                            MaterialSymbol { anchors.centerIn: parent; text: "developer_board"; iconSize: 32; color: cpuTile.ink }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("The graphics chip plays video smoothly and barely touches the battery. The processor works on any computer but uses more power: switch to it if the video stays black.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Pause the video")
                    searchText: `${title} ${Translation.tr("Behind any window")} ${Translation.tr("Behind fullscreen windows")} ${Translation.tr("Never")}`
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        SchemeTile {
                            id: anyWindowTile
                            label: Translation.tr("Behind any window")
                            frameWidth: 112
                            frameHeight: 70
                            selected: Config.options.background.liveWallpaper.pauseWhen === "anyWindow"
                            onClicked: Config.options.background.liveWallpaper.pauseWhen = "anyWindow"
                            Rectangle {
                                x: 14; y: 12; width: 54; height: 38; radius: 4
                                color: "transparent"; border.width: 2; border.color: anyWindowTile.ink
                            }
                            MaterialSymbol { x: 76; y: 30; text: "pause_circle"; iconSize: 22; fill: 1; color: anyWindowTile.ink }
                        }
                        SchemeTile {
                            id: fullscreenTile
                            label: Translation.tr("Behind fullscreen windows")
                            frameWidth: 112
                            frameHeight: 70
                            selected: Config.options.background.liveWallpaper.pauseWhen === "fullscreen"
                            onClicked: Config.options.background.liveWallpaper.pauseWhen = "fullscreen"
                            Rectangle {
                                anchors.fill: parent; anchors.margins: 6; radius: 4
                                color: fullscreenTile.faint; border.width: 2; border.color: fullscreenTile.ink
                            }
                            MaterialSymbol { anchors.centerIn: parent; text: "pause_circle"; iconSize: 22; fill: 1; color: fullscreenTile.ink }
                        }
                        SchemeTile {
                            id: neverTile
                            label: Translation.tr("Never")
                            frameWidth: 112
                            frameHeight: 70
                            selected: Config.options.background.liveWallpaper.pauseWhen === "never"
                            onClicked: Config.options.background.liveWallpaper.pauseWhen = "never"
                            MaterialSymbol { anchors.centerIn: parent; text: "play_circle"; iconSize: 26; fill: 1; color: neverTile.ink }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Also for animated wallpapers. On the lock screen it goes on playing behind the blur unless that's turned off on the Lock Screen page; energy saving pauses it.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                ConfigNavRow {
                    buttonIcon: "energy_savings_leaf"
                    title: Translation.tr("Energy saving")
                    description: PowerSaving.pauseLiveWallpaper ? Translation.tr("On now: the video is paused") : Translation.tr("Pauses the video while it's on")
                    onClicked: ApplicationWindow.window?.openPage("battery")
                }
            }
        }
        SettingsBranch {
            id: greeterBranch
            page: root
            key: "greeter"

            ContentSection {
                icon: "login"
                title: Translation.tr("Login screen wallpaper")
                description: Translation.tr("With the Velora GDM theme installed, this account's wallpaper is also shown before login. It is visible to everyone using this computer.")
                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Use desktop colors on the login screen")
                    enabled: root.greeterOwner.length > 0 && root.greeterOwner === SystemInfo.username
                    autoToggle: false
                    checked: Config.options.background.syncGreeterPalette
                    onClicked: Config.options.background.syncGreeterPalette = !checked
                }
                ConfigSwitch {
                    buttonIcon: "sync"
                    text: Translation.tr("Use desktop wallpaper on the login screen")
                    enabled: root.greeterOwner.length > 0 && root.greeterOwner === SystemInfo.username
                    description: root.greeterOwner.length > 0 ? Translation.tr("Wallpaper owner: %1").arg(root.greeterOwner) : Translation.tr("Available with the Velora GDM theme")
                    autoToggle: false
                    checked: Config.options.background.syncGreeterWallpaper
                    onClicked: Config.options.background.syncGreeterWallpaper = !checked
                }
                ConfigSwitch {
                    buttonIcon: "animation"
                    text: Translation.tr("Animate built-in wallpapers on the login screen")
                    enabled: Config.options.background.syncGreeterWallpaper && root.greeterOwner === SystemInfo.username && root.greeterOwner.length > 0
                    autoToggle: false
                    checked: Config.options.background.animateGreeterWallpaper
                    onClicked: Config.options.background.animateGreeterWallpaper = !checked
                }
            }
        }
    }
}
