import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.desktop
import qs.modules.settings.preview

SettingsDetailPage {
    id: root
    sectionTitles: ({
        colors: Translation.tr("App and terminal colors"),
        windows: Translation.tr("Window style"),
        transparency: Translation.tr("Transparency & blur"),
        motion: Translation.tr("Motion"),
        fonts: Translation.tr("Fonts")
    })
    readonly property Item popupPane: root

    readonly property var theming: Config.options.appearance.wallpaperTheming
    readonly property var terminalProps: Config.options.appearance.wallpaperTheming.terminalGenerationProps
    readonly property string motion: !HyprlandSettings.get("animations:enabled", true) ? "off" : HyprlandSettings.animationProfile

    readonly property var glass: Config.options.appearance.transparency
    readonly property int cornerRadius: HyprlandSettings.get("decoration:rounding", 16)
    readonly property var motionOptions: [
        { displayName: Translation.tr("Off"), icon: "motion_photos_off", value: "off" },
        { displayName: Translation.tr("Material"), icon: "animation", value: "material" },
        { displayName: Translation.tr("Fast"), icon: "bolt", value: "fast" },
        { displayName: Translation.tr("Smooth"), icon: "waves", value: "smooth" },
        { displayName: Translation.tr("Minimal"), icon: "blur_on", value: "minimal" }
    ]
    readonly property string motionLabel: motionOptions.find(option => option.value === motion)?.displayName ?? motion
    function speedLabel(value) {
        const speed = Math.round(value * 10) / 10;
        return speed === 0 ? Translation.tr("Off")
            : speed.toLocaleString(Qt.locale(Translation.languageCode), "f", Number.isInteger(speed) ? 0 : 1) + "×";
    }
    function regenerateColors(mode = "") {
        const args = ["bash", Directories.wallpaperSwitchScriptPath, "--noswitch", "--type", Config.options.appearance.palette.type];
        if (mode.length > 0) args.push("--mode", mode);
        Quickshell.execDetached(args);
    }
    function setMotion(motion) {
        if (motion === "off") {
            HyprlandSettings.set("animations:enabled", false);
            return;
        }
        if (root.motion === "off") HyprlandSettings.set("animations:enabled", true);
        HyprlandSettings.setAnimationProfile(motion);
    }

    Timer { // Terminal colors are made again once the sliders settle
        id: terminalColorsTimer
        interval: 800
        onTriggered: root.regenerateColors()
    }

    component FontRow: ConfigFontRow {
        required property string fontKey
        value: Config.options.appearance.fonts[fontKey]
        onPicked: family => Config.options.appearance.fonts[fontKey] = family
    }

    component CornerTile: SchemeTile {
        id: corner
        required property int mode
        selected: Config.options.appearance.fakeScreenRounding === mode
        onClicked: Config.options.appearance.fakeScreenRounding = mode
        Accessible.name: label
        Accessible.checkable: true
        Accessible.checked: selected
        wrapLabel: true
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: 1
        Rectangle {
            anchors.fill: parent
            anchors.margins: 8
            radius: corner.mode === 0 ? 1 : 12
            color: "transparent"
            border.width: 2
            border.color: corner.ink
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: corner.mode === 2
            text: "fullscreen_exit"
            iconSize: 22
            color: corner.ink
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        SettingsBranch {
            id: overviewBranch
            key: "overview"
            page: root

            GridLayout {
                id: themeGrid
                Layout.fillWidth: true
                columns: width >= 570 ? 2 : 1
                uniformCellWidths: true
                columnSpacing: 16
                rowSpacing: 12

                ContentSection {
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Your desktop")
                    icon: "desktop_windows"
                    searchText: title + " " + Translation.tr("Preview")
                    card: false
                    Loader {
                        objectName: "appearanceDesktopPreview"
                        Layout.fillWidth: true
                        Layout.preferredHeight: themeGrid.columns === 2 ? themeSection.naturalCardHeight : Math.min(198, width * 0.56)
                        active: root.pageShown && overviewBranch.shown
                        sourceComponent: AppearancePreview {}
                    }
                }

                ContentSection {
                    id: themeSection
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Colors")
                    icon: "contrast"
                    searchText: [title, Translation.tr("Light or dark"), Translation.tr("Dark mode")].join(" ")
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        uniformCellWidths: true
                        columnSpacing: 4
                        AppearanceModeTile { dark: false; onClicked: root.regenerateColors("light") }
                        AppearanceModeTile { dark: true; onClicked: root.regenerateColors("dark") }
                    }
                    ConfigComboRow {
                        id: paletteRow
                        icon: "palette"
                        text: Translation.tr("Palette")
                        searchText: text + " " + Translation.tr("How colors are picked from the wallpaper") + " " + dropdown.displayText
                        maximumWidth: Math.max(120, Math.min(210, width - 140))
                        dropdown.displayIcon: paletteRow.width >= 320 ? (paletteRow.dropdown.currentOption?.icon ?? "") : ""
                        currentValue: Config.options.appearance.palette.type
                        onSelected: value => {
                            Config.options.appearance.palette.type = value;
                            root.regenerateColors();
                        }
                        options: [
                            { value: "auto", displayName: Translation.tr("Auto"), icon: "auto_awesome", description: Translation.tr("Picks one that suits the wallpaper") },
                            { value: "scheme-tonal-spot", displayName: Translation.tr("Tonal Spot"), icon: "contrast", description: Translation.tr("Calm and balanced, the Material default") },
                            { value: "scheme-content", displayName: Translation.tr("Content"), icon: "image", description: Translation.tr("Stays close to the wallpaper's own colors") },
                            { value: "scheme-fidelity", displayName: Translation.tr("Fidelity"), icon: "colorize", description: Translation.tr("Matches the wallpaper closely, even very bright colors") },
                            { value: "scheme-expressive", displayName: Translation.tr("Expressive"), icon: "brush", description: Translation.tr("Playful, moves hues away from the wallpaper") },
                            { value: "scheme-fruit-salad", displayName: Translation.tr("Fruit Salad"), icon: "nutrition", description: Translation.tr("A bold mix of shifted hues") },
                            { value: "scheme-rainbow", displayName: Translation.tr("Rainbow"), icon: "looks", description: Translation.tr("Colorful accents on a neutral base") },
                            { value: "scheme-neutral", displayName: Translation.tr("Neutral"), icon: "filter_b_and_w", description: Translation.tr("Muted, nearly gray") },
                            { value: "scheme-monochrome", displayName: Translation.tr("Monochrome"), icon: "invert_colors_off", description: Translation.tr("Shades of gray only") }
                        ]
                    }
                    ConfigNavRow {
                        buttonIcon: "auto_awesome_mosaic"
                        title: Translation.tr("Ready-made looks")
                        searchText: title + " " + Translation.tr("Change colors, the bar, the dock and motion in one click")
                        onClicked: ApplicationWindow.window?.openPage("presets")
                    }
                }
            }

            ContentSection {
                icon: "palette"
                title: Translation.tr("Theme palette")
                ThemePaletteEditor {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    pageShown: root.pageShown && overviewBranch.shown
                }
                SettingsBranchLink {
                    branch: colorsBranch
                    buttonIcon: "format_paint"
                    detail: Translation.tr("Background tint, and which apps take the colors")
                }
            }

            GridLayout {
                id: detailsGrid
                Layout.fillWidth: true
                columns: width >= 470 ? 2 : 1
                uniformCellWidths: true
                uniformCellHeights: true
                columnSpacing: 12
                rowSpacing: 10

                DesktopBranchTile {
                    id: windowTile
                    Layout.fillHeight: true
                    branch: windowsBranch
                    summary: Translation.tr("%1 px corners").arg(root.cornerRadius)
                    Rectangle {
                        anchors.centerIn: parent
                        width: 42; height: 28
                        radius: Math.min(13, root.cornerRadius * 0.34)
                        border.width: 1
                        border.color: windowTile.accent
                        color: ColorUtils.mix(windowTile.accent, Appearance.colors.colLayer2Base, 0.27)
                        Column {
                            x: 6; y: 7; spacing: 4
                            Rectangle { width: 15; height: 3; radius: 1.5; color: windowTile.accent }
                            Rectangle { width: 25; height: 2; radius: 1; color: ColorUtils.applyAlpha(windowTile.accent, 0.55) }
                        }
                    }
                }
                DesktopBranchTile {
                    id: glassTile
                    Layout.fillHeight: true
                    branch: glassBranch
                    accent: Appearance.colors.colTertiary
                    summary: root.glass.enable ? Translation.tr("Transparent panels") : Translation.tr("Opaque panels")
                    Item {
                        anchors.centerIn: parent
                        width: 44; height: 30
                        Rectangle { width: 28; height: 22; radius: 5; color: glassTile.accent }
                        Rectangle {
                            x: 13; y: 8; width: 30; height: 22; radius: 5
                            color: ColorUtils.applyAlpha(Appearance.colors.colTertiaryContainer, root.glass.enable ? 1 - Appearance.contentTransparency : 1)
                            border.width: 1
                            border.color: glassTile.accent
                        }
                    }
                }
                DesktopBranchTile {
                    id: motionTile
                    Layout.fillHeight: true
                    branch: motionBranch
                    accent: Appearance.colors.colSecondary
                    summary: {
                        const speed = Config.options.appearance.animationSpeed;
                        if (root.motion === "off")
                            return speed > 0 ? Translation.tr("Panels only · %1").arg(root.speedLabel(speed)) : Translation.tr("Off");
                        if (speed === 0) return Translation.tr("Windows only · %1").arg(root.motionLabel);
                        return root.motionLabel + " · " + root.speedLabel(speed);
                    }
                    Item {
                        anchors.centerIn: parent
                        width: 48; height: 30
                        Rectangle { x: 3; y: 9; width: 18; height: 3; radius: 1.5; color: ColorUtils.applyAlpha(motionTile.accent, 0.62) }
                        Rectangle { x: 0; y: 17; width: 16; height: 3; radius: 1.5; color: ColorUtils.applyAlpha(motionTile.accent, 0.35) }
                        Rectangle {
                            x: motionTile.hovered || motionTile.visualFocus ? 31 : 24
                            y: 5; width: 19; height: 19; radius: 6; color: motionTile.accent
                            Behavior on x { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic } }
                        }
                    }
                }
                DesktopBranchTile {
                    id: typeTile
                    Layout.fillHeight: true
                    branch: fontsBranch
                    summary: Appearance.font.family.main
                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Aa")
                        font.family: Appearance.font.family.main
                        font.pixelSize: 25
                        color: typeTile.accent
                    }
                }
            }
        }

        SettingsBranch {
            id: colorsBranch
            key: "colors"
            page: root

            ContentSection {
                icon: "wallpaper"
                title: Translation.tr("Wallpaper colors")
                ConfigSwitch {
                    buttonIcon: "format_color_fill"
                    text: Translation.tr("Tint the background with the accent color")
                    autoToggle: false
                    checked: Config.options.appearance.extraBackgroundTint
                    onClicked: Config.options.appearance.extraBackgroundTint = !Config.options.appearance.extraBackgroundTint
                }
                ConfigSwitch {
                    buttonIcon: "hardware"
                    text: Translation.tr("Make new colors when the wallpaper changes")
                    description: Translation.tr("Off keeps the current colors for the shell and every app")
                    autoToggle: false
                    checked: root.theming.enableAppsAndShell
                    onClicked: Config.options.appearance.wallpaperTheming.enableAppsAndShell = !root.theming.enableAppsAndShell
                }
                ConfigSwitch {
                    enabled: root.theming.enableAppsAndShell
                    buttonIcon: "tv_options_input_settings"
                    text: Translation.tr("Color Qt apps")
                    description: Translation.tr("Apps like Dolphin and Kate")
                    autoToggle: false
                    checked: root.theming.enableQtApps
                    onClicked: Config.options.appearance.wallpaperTheming.enableQtApps = !root.theming.enableQtApps
                }
            }
            ContentSection {
                icon: "terminal"
                title: Translation.tr("Terminal colors")
                objectName: "terminal"
                ConfigSwitch {
                    enabled: root.theming.enableAppsAndShell
                    buttonIcon: "terminal"
                    text: Translation.tr("Color the terminal")
                    autoToggle: false
                    checked: root.theming.enableTerminal
                    onClicked: Config.options.appearance.wallpaperTheming.enableTerminal = !root.theming.enableTerminal
                }
                ConfigSwitch {
                    enabled: root.theming.enableAppsAndShell && root.theming.enableTerminal
                    buttonIcon: "dark_mode"
                    text: Translation.tr("Keep the terminal dark")
                    description: Translation.tr("Even when the theme is light")
                    autoToggle: false
                    checked: root.terminalProps.forceDarkMode
                    onClicked: {
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = !root.terminalProps.forceDarkMode;
                        terminalColorsTimer.restart();
                    }
                }
            }
            ContentSection {
                icon: "tune"
                title: Translation.tr("Color adjustments")
                ConfigSlider {
                    enabled: root.theming.enableAppsAndShell && root.theming.enableTerminal
                    buttonIcon: "invert_colors"
                    text: Translation.tr("Terminal colors lean to the accent")
                    description: Translation.tr("How far red, green, blue and the rest shift toward your accent color")
                    from: 0
                    to: 1
                    defaultValue: 0.6
                    value: root.terminalProps.harmony
                    onMoved: {
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = Math.round(value * 100) / 100;
                        terminalColorsTimer.restart();
                    }
                }
                ConfigSlider {
                    enabled: root.theming.enableAppsAndShell && root.theming.enableTerminal
                    buttonIcon: "gradient"
                    text: Translation.tr("Largest shift")
                    description: Translation.tr("No terminal color moves further around the color wheel than this")
                    usePercentTooltip: false
                    from: 0
                    to: 180
                    defaultValue: 100
                    defaultValueText: "100°"
                    value: root.terminalProps.harmonizeThreshold
                    valueText: `${Math.round(value)}°`
                    onMoved: {
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = Math.round(value);
                        terminalColorsTimer.restart();
                    }
                }
                ConfigSlider {
                    enabled: root.theming.enableAppsAndShell && root.theming.enableTerminal
                    buttonIcon: "format_color_text"
                    text: Translation.tr("Terminal text contrast")
                    description: Translation.tr("Makes text stand out more from the terminal's background")
                    from: 0
                    to: 1
                    defaultValue: 0.35
                    value: root.terminalProps.termFgBoost
                    onMoved: {
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = Math.round(value * 100) / 100;
                        terminalColorsTimer.restart();
                    }
                }
            }
        }

        SettingsBranch {
            id: windowsBranch
            key: "windows"
            page: root

            ContentSection {
                icon: "rounded_corner"
                title: Translation.tr("Window shape")
                HyprSlider {
                    option: "decoration:rounding"
                    fallback: 16
                    integer: true
                    valueText: `${Math.round(value)} px`
                    defaultValueText: `${fallback} px`
                    from: 0
                    to: 40
                    buttonIcon: "rounded_corner"
                    text: Translation.tr("Corner radius")
                }
                HyprSlider {
                    option: "decoration:rounding_power"
                    fallback: 2
                    decimals: 1
                    from: 1
                    to: 10
                    buttonIcon: "line_curve"
                    text: Translation.tr("Corner smoothness")
                    description: Translation.tr("2 is a circle arc, higher values look like squircles")
                }
                HyprSwitch {
                    option: "decoration:shadow:enabled"
                    fallback: true
                    buttonIcon: "shadow"
                    text: Translation.tr("Shadows")
                }
                HyprSlider {
                    enabled: HyprlandSettings.ready && HyprlandSettings.get("decoration:shadow:enabled", true)
                    option: "decoration:shadow:range"
                    fallback: 20
                    integer: true
                    valueText: `${Math.round(value)} px`
                    defaultValueText: `${fallback} px`
                    from: 0
                    to: 60
                    buttonIcon: "blur_circular"
                    text: Translation.tr("Shadow size")
                }
            }
            ContentSection {
                icon: "select_window"
                title: Translation.tr("Window focus")
                HyprSlider {
                    option: "decoration:active_opacity"
                    fallback: 1
                    from: 0.5
                    to: 1
                    buttonIcon: "select_window"
                    text: Translation.tr("Focused window opacity")
                    defaultValueText: `${Math.round(fallback * 100)}%`
                    valueText: `${Math.round(value * 100)}%`
                }
                HyprSlider {
                    option: "decoration:inactive_opacity"
                    fallback: 1
                    from: 0.5
                    to: 1
                    buttonIcon: "tab_unselected"
                    text: Translation.tr("Other windows opacity")
                    defaultValueText: `${Math.round(fallback * 100)}%`
                    valueText: `${Math.round(value * 100)}%`
                }
                HyprSwitch {
                    option: "decoration:dim_inactive"
                    fallback: false
                    buttonIcon: "brightness_low"
                    text: Translation.tr("Dim unfocused windows")
                    description: Translation.tr("Makes it easy to see which window you're typing in")
                }
                HyprSlider {
                    enabled: HyprlandSettings.ready && HyprlandSettings.get("decoration:dim_inactive", false)
                    option: "decoration:dim_strength"
                    fallback: 0.05
                    from: 0
                    to: 0.5
                    buttonIcon: "contrast"
                    text: Translation.tr("Dim strength")
                    defaultValueText: `${Math.round(fallback * 100)}%`
                    valueText: `${Math.round(value * 100)}%`
                }
            }
            ContentSection {
                icon: "screenshot_frame"
                title: Translation.tr("Screen corners")
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    uniformCellWidths: true
                    columnSpacing: 4
                    CornerTile { mode: 0; label: Translation.tr("Square") }
                    CornerTile { mode: 1; label: Translation.tr("Rounded") }
                    CornerTile { mode: 2; label: Translation.tr("Rounded, except fullscreen") }
                }
            }
            ContentSection {
                ConfigNavRow {
                    buttonIcon: "view_quilt"
                    title: Translation.tr("Gaps, borders and tiling")
                    onClicked: ApplicationWindow.window?.openPage("desktop", Translation.tr("Windows"))
                }
            }
        }

        SettingsBranch {
            id: glassBranch
            key: "transparency"
            page: root

            ContentSection {
                icon: "layers"
                title: Translation.tr("Panels")
                ConfigSwitch {
                    buttonIcon: "opacity"
                    text: Translation.tr("Transparent panels")
                    description: Translation.tr("The bar, sidebars and popups let the wallpaper show through")
                    autoToggle: false
                    checked: Config.options.appearance.transparency.enable
                    onClicked: Config.options.appearance.transparency.enable = !Config.options.appearance.transparency.enable
                }
                ConfigSwitch {
                    enabled: Config.options.appearance.transparency.enable
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Adjust automatically")
                    description: Translation.tr("Picks the amount based on how vibrant the wallpaper is")
                    autoToggle: false
                    checked: Config.options.appearance.transparency.automatic
                    onClicked: Config.options.appearance.transparency.automatic = !Config.options.appearance.transparency.automatic
                }
                ConfigSlider {
                    enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
                    buttonIcon: "gradient"
                    text: Translation.tr("Panel background")
                    defaultValue: 0.11
                    value: Config.options.appearance.transparency.backgroundTransparency
                    onMoved: Config.options.appearance.transparency.backgroundTransparency = Math.round(value * 100) / 100
                }
                ConfigSlider {
                    enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
                    buttonIcon: "layers"
                    text: Translation.tr("Cards inside panels")
                    defaultValue: 0.57
                    value: Config.options.appearance.transparency.contentTransparency
                    onMoved: Config.options.appearance.transparency.contentTransparency = Math.round(value * 100) / 100
                }
            }
            ContentSection {
                icon: "blur_on"
                title: Translation.tr("Blur")
                HyprSwitch {
                    option: "decoration:blur:enabled"
                    fallback: true
                    buttonIcon: "blur_on"
                    text: Translation.tr("Blur")
                    description: Translation.tr("Frosted glass behind see-through windows and panels")
                }
                HyprSlider {
                    enabled: HyprlandSettings.ready && HyprlandSettings.get("decoration:blur:enabled", true)
                    option: "decoration:blur:size"
                    fallback: 10
                    integer: true
                    from: 1
                    to: 20
                    buttonIcon: "blur_medium"
                    text: Translation.tr("Blur strength")
                }
                HyprSlider {
                    enabled: HyprlandSettings.ready && HyprlandSettings.get("decoration:blur:enabled", true)
                    option: "decoration:blur:passes"
                    fallback: 3
                    integer: true
                    from: 1
                    to: 6
                    buttonIcon: "stacks"
                    text: Translation.tr("Blur passes")
                    description: Translation.tr("More passes look smoother but cost more GPU")
                }
                HyprSlider {
                    enabled: HyprlandSettings.ready && HyprlandSettings.get("decoration:blur:enabled", true)
                    option: "decoration:blur:vibrancy"
                    fallback: 0.5
                    buttonIcon: "palette"
                    text: Translation.tr("Vibrancy")
                    description: Translation.tr("How much color the blurred background keeps")
                }
                HyprSwitch {
                    enabled: HyprlandSettings.ready && HyprlandSettings.get("decoration:blur:enabled", true)
                    option: "decoration:blur:xray"
                    fallback: true
                    buttonIcon: "flip_to_back"
                    text: Translation.tr("See through to the wallpaper")
                    description: Translation.tr("Floating windows blur only the wallpaper, not the windows under them")
                }
            }
        }

        SettingsBranch {
            id: motionBranch
            key: "motion"
            page: root

            ContentSection {
                icon: "animation"
                title: Translation.tr("Panel motion")
                PanelMotionPreview { shown: root.pageShown && motionBranch.shown }
                ConfigSlider {
                    buttonIcon: "speed"
                    text: Translation.tr("Shell animation speed")
                    description: Translation.tr("Panels, popups and widgets. All the way left turns them off.")
                    from: 0
                    to: 2
                    usePercentTooltip: false
                    valueText: root.speedLabel(value)
                    defaultValue: 1
                    defaultValueText: "1×"
                    value: Config.options.appearance.animationSpeed
                    onMoved: Config.options.appearance.animationSpeed = Math.round(value * 10) / 10
                }
            }
            ContentSection {
                icon: "select_window"
                title: Translation.tr("Window animations")
                ConfigSelectionArray {
                    enabled: HyprlandSettings.ready
                    currentValue: root.motion
                    onSelected: value => root.setMotion(value)
                    options: root.motionOptions
                }
                HyprSwitch {
                    enabled: HyprlandSettings.ready && root.motion !== "off"
                    option: "misc:animate_manual_resizes"
                    buttonIcon: "open_in_full"
                    text: Translation.tr("Animate manual resizing")
                }
                HyprSwitch {
                    enabled: HyprlandSettings.ready && root.motion !== "off"
                    option: "misc:animate_mouse_windowdragging"
                    buttonIcon: "drag_pan"
                    text: Translation.tr("Animate dragging windows")
                }
            }
        }

        SettingsBranch {
            id: fontsBranch
            key: "fonts"
            page: root

            ContentSection {
                icon: "text_fields"
                title: Translation.tr("Font sample")
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    Layout.topMargin: 10
                    Layout.bottomMargin: 10
                    spacing: 16
                    StyledText {
                        text: Translation.tr("Aa")
                        font.family: Appearance.font.family.title
                        font.pixelSize: 44
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: Appearance.font.family.main
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "0123456789"
                            font.family: Appearance.font.family.numbers
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
            ContentSection {
                icon: "match_case"
                title: Translation.tr("Interface fonts")
                FontRow {
                    fontKey: "main"
                    icon: "match_case"
                    text: Translation.tr("Main font")
                    description: Translation.tr("Most text in the shell")
                }
                FontRow {
                    fontKey: "title"
                    icon: "title"
                    text: Translation.tr("Title font")
                    description: Translation.tr("Used for headings and titles")
                }
                FontRow {
                    fontKey: "numbers"
                    icon: "123"
                    text: Translation.tr("Numbers font")
                    description: Translation.tr("Used for displaying numbers")
                }
                FontRow {
                    fontKey: "monospace"
                    kind: "monospace"
                    icon: "code"
                    text: Translation.tr("Monospace font")
                    description: Translation.tr("Code and the terminal")
                }
            }
            ContentSection {
                icon: "font_download"
                title: Translation.tr("Other fonts")
                FontRow {
                    fontKey: "reading"
                    icon: "menu_book"
                    text: Translation.tr("Reading font")
                    description: Translation.tr("Used for reading large blocks of text")
                }
                FontRow {
                    fontKey: "expressive"
                    icon: "brush"
                    text: Translation.tr("Expressive font")
                    description: Translation.tr("Used for decorative/expressive text")
                }
                FontRow {
                    fontKey: "iconNerd"
                    kind: "nerd"
                    icon: "emoji_symbols"
                    text: Translation.tr("Nerd font icons")
                    description: Translation.tr("Font used for Nerd Font icons")
                }
            }
        }
    }
}
