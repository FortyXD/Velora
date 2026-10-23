import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview

/**
 * Colors, windows, transparency, motion and fonts, under a live miniature that shows every change.
 * Each group keeps the few choices most people make in sight and folds the fine-tuning away.
 */
ContentPage {
    id: root

    readonly property var theming: Config.options.appearance.wallpaperTheming
    readonly property var terminalProps: Config.options.appearance.wallpaperTheming.terminalGenerationProps
    readonly property string motion: !HyprlandSettings.get("animations:enabled", true) ? "off" : HyprlandSettings.animationProfile

    function setDarkMode(dark) {
        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "dark" : "light"} --noswitch`]);
    }
    function regenerateColors() {
        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch`]);
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

    // A light or dark window in the current accent
    component ModeSketch: Rectangle {
        property bool dark
        readonly property color line: dark ? "#57545d" : "#cbc6d2"
        anchors.fill: parent
        anchors.margins: 2
        radius: 6
        color: dark ? "#1b1b1f" : "#f3f0f6"
        Rectangle {
            x: 5
            y: 5
            width: parent.width - 10
            height: 8
            radius: 4
            color: parent.dark ? "#2c2b31" : "#e2dfe7"
        }
        Rectangle {
            x: 14
            y: 18
            width: parent.width - 28
            height: parent.height - 24
            radius: 5
            color: parent.dark ? "#2c2b31" : "#ffffff"
            Rectangle { x: 6; y: 7; width: parent.width * 0.45; height: 5; radius: 2.5; color: Appearance.colors.colPrimary }
            Rectangle { x: 6; y: 16; width: parent.width * 0.75; height: 4; radius: 2; color: parent.parent.line }
            Rectangle { x: 6; y: 24; width: parent.width * 0.55; height: 4; radius: 2; color: parent.parent.line }
        }
    }

    // The screen's outline, square or rounded
    component ScreenSketch: Rectangle {
        property color ink
        property bool rounded
        anchors.fill: parent
        anchors.margins: 8
        radius: rounded ? 12 : 1
        color: "transparent"
        border.width: 2
        border.color: ink
    }

    ContentSection {
        icon: "palette"
        card: false
        searchText: `${Translation.tr("Preview")} ${Translation.tr("Appearance")}`

        AppearancePreview {
            Layout.fillWidth: true
        }
    }

    ContentSection {
        icon: "contrast"
        title: Translation.tr("Colors")
        description: Translation.tr("Colors are made from your wallpaper. A palette decides how bold they are.")

        ContentSubsection {
            title: Translation.tr("Light or dark")
            searchText: `${title} ${Translation.tr("Mode")} ${Translation.tr("Dark mode")}`
            Flow {
                Layout.fillWidth: true
                spacing: 4
                SchemeTile {
                    label: Translation.tr("Light")
                    frameWidth: 112
                    frameHeight: 70
                    selected: !Appearance.m3colors.darkmode
                    onClicked: root.setDarkMode(false)
                    ModeSketch { dark: false }
                }
                SchemeTile {
                    label: Translation.tr("Dark")
                    frameWidth: 112
                    frameHeight: 70
                    selected: Appearance.m3colors.darkmode
                    onClicked: root.setDarkMode(true)
                    ModeSketch { dark: true }
                }
            }
        }
        ConfigComboRow {
            icon: "palette"
            text: Translation.tr("Palette")
            description: Translation.tr("How colors are picked from the wallpaper")
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
        ConfigExpander {
            title: Translation.tr("More color options")
            description: Translation.tr("Background tint, and which apps take the colors")
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
            ConfigSlider {
                enabled: root.theming.enableAppsAndShell && root.theming.enableTerminal
                buttonIcon: "invert_colors"
                text: Translation.tr("Terminal colors lean to the accent")
                description: Translation.tr("How far red, green, blue and the rest shift toward your accent color")
                from: 0
                to: 1
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
                value: root.terminalProps.termFgBoost
                onMoved: {
                    Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = Math.round(value * 100) / 100;
                    terminalColorsTimer.restart();
                }
            }
        }
        ConfigNavRow {
            buttonIcon: "auto_awesome_mosaic"
            title: Translation.tr("Ready-made looks")
            description: Translation.tr("Change colors, the bar, the dock and motion in one click")
            onClicked: ApplicationWindow.window?.openPage("presets")
        }
    }

    ContentSection {
        icon: "select_window"
        title: Translation.tr("Windows")

        HyprSlider {
            option: "decoration:rounding"
            fallback: 18
            integer: true
            from: 0
            to: 40
            buttonIcon: "rounded_corner"
            text: Translation.tr("Corner radius")
        }
        HyprSwitch {
            option: "decoration:shadow:enabled"
            fallback: true
            buttonIcon: "shadow"
            text: Translation.tr("Shadows")
        }
        HyprSwitch {
            option: "decoration:dim_inactive"
            fallback: false
            buttonIcon: "brightness_low"
            text: Translation.tr("Dim unfocused windows")
            description: Translation.tr("Makes it easy to see which window you're typing in")
        }
        ConfigExpander {
            title: Translation.tr("More window options")
            description: Translation.tr("Corner shape, shadow size, opacity and dimming strength")
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
            HyprSlider {
                enabled: HyprlandSettings.get("decoration:shadow:enabled", true)
                option: "decoration:shadow:range"
                fallback: 20
                integer: true
                from: 0
                to: 60
                buttonIcon: "blur_circular"
                text: Translation.tr("Shadow size")
            }
            HyprSlider {
                option: "decoration:active_opacity"
                fallback: 1
                from: 0.5
                to: 1
                buttonIcon: "select_window"
                text: Translation.tr("Focused window opacity")
                valueText: `${Math.round(value * 100)}%`
            }
            HyprSlider {
                option: "decoration:inactive_opacity"
                fallback: 1
                from: 0.5
                to: 1
                buttonIcon: "tab_unselected"
                text: Translation.tr("Other windows opacity")
                valueText: `${Math.round(value * 100)}%`
            }
            HyprSlider {
                enabled: HyprlandSettings.get("decoration:dim_inactive", false)
                option: "decoration:dim_strength"
                fallback: 0.05
                from: 0
                to: 0.5
                buttonIcon: "contrast"
                text: Translation.tr("Dim strength")
                valueText: `${Math.round(value * 100)}%`
            }
        }
        ContentSubsection {
            title: Translation.tr("Screen corners")
            description: Translation.tr("Rounds the corners of the screen itself, like on a phone")
            Flow {
                Layout.fillWidth: true
                spacing: 4
                readonly property int current: Config.options.appearance.fakeScreenRounding
                SchemeTile {
                    id: squareTile
                    label: Translation.tr("Square")
                    selected: parent.current === 0
                    onClicked: Config.options.appearance.fakeScreenRounding = 0
                    ScreenSketch { ink: squareTile.ink; rounded: false }
                }
                SchemeTile {
                    id: roundedTile
                    label: Translation.tr("Rounded")
                    selected: parent.current === 1
                    onClicked: Config.options.appearance.fakeScreenRounding = 1
                    ScreenSketch { ink: roundedTile.ink; rounded: true }
                }
                SchemeTile {
                    id: notFullscreenTile
                    label: Translation.tr("Rounded, except fullscreen")
                    selected: parent.current === 2
                    onClicked: Config.options.appearance.fakeScreenRounding = 2
                    ScreenSketch { ink: notFullscreenTile.ink; rounded: true }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "fullscreen_exit"
                        iconSize: 22
                        color: notFullscreenTile.ink
                    }
                }
            }
        }
        ConfigNavRow {
            buttonIcon: "view_quilt"
            title: Translation.tr("Gaps, borders and tiling")
            onClicked: ApplicationWindow.window?.openPage("desktop", Translation.tr("Windows"))
        }
    }

    ContentSection {
        icon: "blur_on"
        title: Translation.tr("Transparency & blur")

        ConfigSwitch {
            buttonIcon: "opacity"
            text: Translation.tr("Transparent panels")
            description: Translation.tr("The bar, sidebars and popups let the wallpaper show through")
            autoToggle: false
            checked: Config.options.appearance.transparency.enable
            onClicked: Config.options.appearance.transparency.enable = !Config.options.appearance.transparency.enable
        }
        HyprSwitch {
            option: "decoration:blur:enabled"
            fallback: true
            buttonIcon: "blur_on"
            text: Translation.tr("Blur")
            description: Translation.tr("Frosted glass behind see-through windows and panels")
        }
        ConfigExpander {
            title: Translation.tr("Fine-tune")
            description: Translation.tr("How see-through panels are, and how strong the blur is")
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
                value: Config.options.appearance.transparency.backgroundTransparency
                onMoved: Config.options.appearance.transparency.backgroundTransparency = Math.round(value * 100) / 100
            }
            ConfigSlider {
                enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
                buttonIcon: "layers"
                text: Translation.tr("Cards inside panels")
                value: Config.options.appearance.transparency.contentTransparency
                onMoved: Config.options.appearance.transparency.contentTransparency = Math.round(value * 100) / 100
            }
            HyprSlider {
                enabled: HyprlandSettings.get("decoration:blur:enabled", true)
                option: "decoration:blur:size"
                fallback: 10
                integer: true
                from: 1
                to: 20
                buttonIcon: "blur_medium"
                text: Translation.tr("Blur strength")
            }
            HyprSlider {
                enabled: HyprlandSettings.get("decoration:blur:enabled", true)
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
                enabled: HyprlandSettings.get("decoration:blur:enabled", true)
                option: "decoration:blur:vibrancy"
                fallback: 0.5
                buttonIcon: "palette"
                text: Translation.tr("Vibrancy")
                description: Translation.tr("How much color the blurred background keeps")
            }
            HyprSwitch {
                enabled: HyprlandSettings.get("decoration:blur:enabled", true)
                option: "decoration:blur:xray"
                fallback: true
                buttonIcon: "flip_to_back"
                text: Translation.tr("See through to the wallpaper")
                description: Translation.tr("Floating windows blur only the wallpaper, not the windows under them")
            }
        }
    }

    ContentSection {
        icon: "animation"
        title: Translation.tr("Motion")

        ContentSubsection {
            title: Translation.tr("Window animations")
            description: Translation.tr("Opening, closing and moving windows and workspaces")
            ConfigSelectionArray {
                currentValue: root.motion
                onSelected: newValue => root.setMotion(newValue)
                options: [
                    { displayName: Translation.tr("Off"), icon: "motion_photos_off", value: "off" },
                    { displayName: Translation.tr("Material"), icon: "animation", value: "material" },
                    { displayName: Translation.tr("Fast"), icon: "bolt", value: "fast" },
                    { displayName: Translation.tr("Smooth"), icon: "waves", value: "smooth" },
                    { displayName: Translation.tr("Minimal"), icon: "blur_on", value: "minimal" }
                ]
            }
        }
        ConfigSlider {
            buttonIcon: "speed"
            text: Translation.tr("Shell animation speed")
            description: Translation.tr("Panels, popups and widgets. All the way left turns them off.")
            from: 0
            to: 2
            usePercentTooltip: false
            valueText: value <= 0.01 ? Translation.tr("Off") : `${value.toFixed(1)}×`
            value: Config.options.appearance.animationSpeed
            onMoved: Config.options.appearance.animationSpeed = Math.round(value * 10) / 10
        }
        ConfigExpander {
            enabled: root.motion !== "off"
            title: Translation.tr("More motion options")
            HyprSwitch {
                option: "misc:animate_manual_resizes"
                buttonIcon: "open_in_full"
                text: Translation.tr("Animate manual resizing")
            }
            HyprSwitch {
                option: "misc:animate_mouse_windowdragging"
                buttonIcon: "drag_pan"
                text: Translation.tr("Animate dragging windows")
            }
        }
    }

    ContentSection {
        icon: "match_case"
        title: Translation.tr("Fonts")

        FontRow {
            fontKey: "main"
            icon: "match_case"
            text: Translation.tr("Main font")
            description: Translation.tr("Most text in the shell")
        }
        FontRow {
            fontKey: "monospace"
            kind: "monospace"
            icon: "code"
            text: Translation.tr("Monospace font")
            description: Translation.tr("Code and the terminal")
        }
        ConfigExpander {
            title: Translation.tr("More fonts")
            description: Translation.tr("Headings, numbers, icons, long reading and decorative text")
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
                fontKey: "iconNerd"
                kind: "nerd"
                icon: "emoji_symbols"
                text: Translation.tr("Nerd font icons")
                description: Translation.tr("Font used for Nerd Font icons")
            }
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
        }
    }
}
