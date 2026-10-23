import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview

ContentPage {
    id: root

    readonly property string wallpaperPath: {
        const path = Config.options.background.wallpaperPath;
        const isVideo = FileUtils.isVideoPath(path);
        return isVideo ? Config.options.background.thumbnailPath : path;
    }

    // Detached so the download survives switching settings pages or closing the window.
    // The script reports progress and errors through notifications.
    function runRandomWallpaperScript(scriptName) {
        Quickshell.execDetached([FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/random/${scriptName}`)]);
    }

    readonly property bool liveWallpaper: LiveWallpaper.isVideoPath(Config.options.background.wallpaperPath)

    function chooseVideo() {
        Quickshell.execDetached(["bash", "-c",
            `f=$(kdialog --getopenfilename "$HOME/Videos" "Videos (*.mp4 *.webm *.mkv *.mov *.avi)" --title "${Translation.tr("Choose a live wallpaper")}") && [ -n "$f" ] && "${Directories.wallpaperSwitchScriptPath}" --image "$f"`]);
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
            onClicked: ApplicationWindow.window?.openPage("appearance", Translation.tr("Colors"))
        }
    }

    ContentSection {
        icon: "animation"
        title: Translation.tr("Animated wallpaper")
        description: Translation.tr("Drawn by the shell itself: no download, sharp on any screen, in your theme's colors or its own. Like a video, it stops moving whenever you can't see it.")
        searchText: `${title} ${ShaderWallpaper.shaders.map(shader => shader.name).join(" ")}`

        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: ShaderWallpaper.shaders
                delegate: RippleButton {
                    id: shaderTile
                    required property var modelData
                    readonly property bool current: ShaderWallpaper.name === modelData.id
                    implicitWidth: 176
                    implicitHeight: 140
                    buttonRadius: Appearance.rounding.normal
                    colBackground: shaderTile.current ? Appearance.colors.colSecondaryContainer : "transparent"
                    colBackgroundHover: shaderTile.current ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                    onClicked: {
                        // Its own colors unless the theme's were chosen for the current one
                        if (Config.options.background.shaderWallpaper.colors.length > 0 || !ShaderWallpaper.active)
                            Config.options.background.shaderWallpaper.colors = shaderTile.modelData.colors;
                        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "shaderWallpaper", "set", shaderTile.modelData.id]);
                    }
                    contentItem: ColumnLayout {
                        spacing: 6
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 160
                            implicitHeight: 100
                            radius: 10
                            color: "black"
                            border.width: shaderTile.current ? 2 : 0
                            border.color: Appearance.colors.colPrimary
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: 160
                                    height: 100
                                    radius: 10
                                }
                            }
                            ShaderWallpaperView {
                                anchors.fill: parent
                                name: shaderTile.modelData.id
                                colors: shaderTile.current && Config.options.background.shaderWallpaper.colors.length === 0 ? [] : shaderTile.modelData.colors
                                running: shaderTile.hovered || shaderTile.current // Only what you look at moves
                                fps: 24
                            }
                            MaterialSymbol {
                                visible: shaderTile.current
                                anchors {
                                    right: parent.right
                                    top: parent.top
                                    margins: 6
                                }
                                text: "check_circle"
                                iconSize: 20
                                fill: 1
                                color: "white"
                            }
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: shaderTile.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: shaderTile.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        }
                    }
                    StyledToolTip {
                        text: shaderTile.modelData.description
                    }
                }
            }
        }

        ContentSubsection {
            visible: ShaderWallpaper.active
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
            visible: ShaderWallpaper.active
            buttonIcon: "speed"
            text: Translation.tr("Speed")
            usePercentTooltip: false
            from: 0.25
            to: 3
            value: Config.options.background.shaderWallpaper.speed
            valueText: `${Math.round(value * 100)}%`
            onMoved: Config.options.background.shaderWallpaper.speed = Math.round(value * 20) / 20
        }
        ContentSubsection {
            visible: ShaderWallpaper.active
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
        ConfigNavRow {
            visible: ShaderWallpaper.active
            buttonIcon: "pause_circle"
            title: Translation.tr("Stop the animation")
            description: Translation.tr("Keeps a still picture of it as the wallpaper")
            trailingIcon: ""
            onClicked: Config.options.background.shaderWallpaper.name = ""
        }
    }

    ContentSection {
        icon: "motion_photos_on"
        title: Translation.tr("Live wallpaper")
        description: Translation.tr("Any video can be the wallpaper. It plays behind your windows and stops on its current frame whenever you can't see it, so it costs almost nothing while you work.")

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

        ConfigNavRow {
            buttonIcon: root.liveWallpaper ? "play_circle" : "video_library"
            title: root.liveWallpaper ? Translation.tr("Playing %1").arg(FileUtils.fileNameForPath(Config.options.background.wallpaperPath))
                : Translation.tr("Choose a video")
            description: root.liveWallpaper ? Translation.tr("Click to pick another video")
                : Translation.tr("MP4, WebM, MKV or MOV. Short loops of 10–30 seconds look best.")
            onClicked: root.chooseVideo()
        }

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
        icon: "today"
        title: Translation.tr("Wallpaper of the day")
        description: Translation.tr("A new picture every morning, with colors made from it")

        ConfigSwitch {
            buttonIcon: "event_repeat"
            text: Translation.tr("Change the wallpaper every day")
            description: Translation.tr("Saved to ~/Pictures/Wallpapers/Daily")
            autoToggle: false
            checked: Config.options.background.daily.enable
            onClicked: Config.options.background.daily.enable = !Config.options.background.daily.enable
        }
        ContentSubsection {
            title: Translation.tr("Source")
            ConfigSelectionArray {
                currentValue: Config.options.background.daily.source
                onSelected: newValue => Config.options.background.daily.source = newValue
                options: [
                    { displayName: "Bing", icon: "today", value: "bing" },
                    { displayName: "NASA", icon: "rocket_launch", value: "nasa" },
                    { displayName: "Wikimedia", icon: "account_balance", value: "wikimedia" }
                ]
            }
        }
        ConfigSpinBox {
            icon: "auto_delete"
            text: Translation.tr("Keep pictures for (days)")
            from: 1
            to: 365
            stepSize: 1
            value: Config.options.background.daily.keepDays
            onValueChanged: if (value !== Config.options.background.daily.keepDays) Config.options.background.daily.keepDays = value
        }
        DialogButton {
            buttonText: Translation.tr("Get today's picture now")
            onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperOfTheDay", "run"])
        }
    }

    ContentSection {
        icon: "public"
        title: Translation.tr("Online sources")
        description: Translation.tr("Where the Online part of the wallpaper selector searches. Keys are kept in your keyring.")

        Component.onCompleted: KeyringStorage.fetchKeyringData() // Saving keys rewrites the whole entry, so start from the current one

        ConfigSwitch {
            buttonIcon: "fit_screen"
            text: Translation.tr("Only wallpapers that fit the screen")
            description: Translation.tr("Size and shape of the focused screen, where the source can filter by them")
            autoToggle: false
            checked: Config.options.background.online.fitScreen
            onClicked: Config.options.background.online.fitScreen = !Config.options.background.online.fitScreen
        }

        Repeater {
            model: OnlineWallpapers.providerList
            delegate: ColumnLayout {
                id: providerBlock
                required property var modelData
                readonly property bool enabledSource: !(Config.options.background.online.disabledProviders ?? []).includes(modelData.id)
                Layout.fillWidth: true
                spacing: 2

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: providerBlock.modelData.icon
                    text: providerBlock.modelData.name
                    description: Translation.tr(providerBlock.modelData.description)
                    autoToggle: false
                    checked: providerBlock.enabledSource
                    onClicked: {
                        const disabled = Config.options.background.online.disabledProviders ?? [];
                        Config.options.background.online.disabledProviders = providerBlock.enabledSource
                            ? [...disabled, providerBlock.modelData.id] : disabled.filter(id => id !== providerBlock.modelData.id);
                    }
                }
                ConfigTextRow {
                    Layout.fillWidth: true
                    visible: providerBlock.enabledSource && (providerBlock.modelData.needsKey || providerBlock.modelData.keyOptional)
                    enabled: KeyringStorage.loaded
                    icon: "key"
                    label: providerBlock.modelData.needsKey ? Translation.tr("API key") : Translation.tr("API key (optional)")
                    description: Translation.tr("Get one at %1").arg(providerBlock.modelData.homepage)
                    // The saved key is never shown; typing a new one replaces it
                    placeholderText: OnlineWallpapers.hasKey(providerBlock.modelData.id) ? Translation.tr("Saved. Paste a new key to replace it") : Translation.tr("Paste the key here")
                    value: ""
                    onEditingFinished: {
                        if (value.trim().length === 0) return;
                        KeyringStorage.setNestedField(["wallpaperKeys", providerBlock.modelData.id], value.trim());
                        value = "";
                    }
                }
                DialogButton {
                    visible: providerBlock.enabledSource && OnlineWallpapers.hasKey(providerBlock.modelData.id)
                    Layout.leftMargin: 12
                    buttonText: Translation.tr("Remove the key")
                    onClicked: KeyringStorage.setNestedField(["wallpaperKeys", providerBlock.modelData.id], "")
                }
                ConfigTextRow {
                    Layout.fillWidth: true
                    visible: providerBlock.enabledSource && providerBlock.modelData.id === "reddit"
                    icon: "forum"
                    label: Translation.tr("Subreddits")
                    placeholderText: "wallpaper+wallpapers+EarthPorn"
                    value: Config.options.background.online.subreddits
                    onEditingFinished: Config.options.background.online.subreddits = value.trim()
                }
            }
        }

        ConfigTextRow {
            icon: "folder"
            label: Translation.tr("Save downloads to")
            placeholderText: `${FileUtils.trimFileProtocol(Directories.pictures)}/Wallpapers/Online`
            value: Config.options.background.online.downloadDir
            onEditingFinished: Config.options.background.online.downloadDir = value.trim()
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
