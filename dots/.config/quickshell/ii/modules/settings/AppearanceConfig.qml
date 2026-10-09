import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    component FontRow: ConfigTextRow {
        required property string fontKey
        inline: true
        inlineFieldWidth: 260
        wrapMode: TextEdit.NoWrap
        value: Config.options.appearance.fonts[fontKey]
        onValueChanged: Config.options.appearance.fonts[fontKey] = value
    }

    ContentSection {
        title: Translation.tr("Theme")
        description: Translation.tr("Colors are generated from the wallpaper with Material You")

        ContentSubsection {
            title: Translation.tr("Mode")
            ConfigSelectionArray {
                currentValue: Appearance.m3colors.darkmode
                onSelected: newValue => {
                    Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${newValue ? "dark" : "light"} --noswitch`]);
                }
                options: [
                    { displayName: Translation.tr("Light"), icon: "light_mode", value: false },
                    { displayName: Translation.tr("Dark"), icon: "dark_mode", value: true }
                ]
            }
        }
        ContentSubsection {
            title: Translation.tr("Palette")
            description: Translation.tr("How colors are picked from the wallpaper. Auto chooses based on the image.")
            ConfigSelectionArray {
                currentValue: Config.options.appearance.palette.type
                onSelected: newValue => {
                    Config.options.appearance.palette.type = newValue;
                    Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch`]);
                }
                options: [
                    { "value": "auto", "displayName": Translation.tr("Auto"), "icon": "auto_awesome" },
                    { "value": "scheme-content", "displayName": Translation.tr("Content") },
                    { "value": "scheme-expressive", "displayName": Translation.tr("Expressive") },
                    { "value": "scheme-fidelity", "displayName": Translation.tr("Fidelity") },
                    { "value": "scheme-fruit-salad", "displayName": Translation.tr("Fruit Salad") },
                    { "value": "scheme-monochrome", "displayName": Translation.tr("Monochrome") },
                    { "value": "scheme-neutral", "displayName": Translation.tr("Neutral") },
                    { "value": "scheme-rainbow", "displayName": Translation.tr("Rainbow") },
                    { "value": "scheme-tonal-spot", "displayName": Translation.tr("Tonal Spot") }
                ]
            }
        }
        ConfigSwitch {
            buttonIcon: "format_color_fill"
            text: Translation.tr("Tint the background with the accent color")
            checked: Config.options.appearance.extraBackgroundTint
            onCheckedChanged: {
                Config.options.appearance.extraBackgroundTint = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Transparency & blur")
        description: Translation.tr("Panels let the wallpaper show through. Blur applies to translucent windows and panels.")

        ConfigSwitch {
            buttonIcon: "opacity"
            text: Translation.tr("Transparent panels")
            autoToggle: false
            checked: Config.options.appearance.transparency.enable
            onClicked: Config.options.appearance.transparency.enable = !Config.options.appearance.transparency.enable
        }
        ConfigSwitch {
            enabled: Config.options.appearance.transparency.enable
            buttonIcon: "auto_awesome"
            text: Translation.tr("Adjust automatically")
            description: Translation.tr("Picks the amount based on how vibrant the wallpaper is")
            checked: Config.options.appearance.transparency.automatic
            onCheckedChanged: {
                Config.options.appearance.transparency.automatic = checked;
            }
        }
        ConfigSlider {
            enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
            buttonIcon: "gradient"
            text: Translation.tr("Background")
            value: Config.options.appearance.transparency.backgroundTransparency
            onMoved: {
                Config.options.appearance.transparency.backgroundTransparency = Math.round(value * 100) / 100;
            }
        }
        ConfigSlider {
            enabled: Config.options.appearance.transparency.enable && !Config.options.appearance.transparency.automatic
            buttonIcon: "layers"
            text: Translation.tr("Content")
            value: Config.options.appearance.transparency.contentTransparency
            onMoved: {
                Config.options.appearance.transparency.contentTransparency = Math.round(value * 100) / 100;
            }
        }
        HyprSwitch {
            option: "decoration:blur:enabled"
            fallback: true
            buttonIcon: "blur_on"
            text: Translation.tr("Blur")
        }
        HyprSlider {
            enabled: HyprlandSettings.get("decoration:blur:enabled", true)
            option: "decoration:blur:size"
            fallback: 10
            integer: true
            from: 1
            to: 20
            buttonIcon: "blur_medium"
            text: Translation.tr("Blur radius")
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

    ContentSection {
        title: Translation.tr("Windows")
        description: Translation.tr("Rounding of the shell itself follows its own style; these apply to app windows")

        HyprSlider {
            option: "decoration:rounding"
            fallback: 18
            integer: true
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
        }
        HyprSlider {
            option: "decoration:inactive_opacity"
            fallback: 1
            from: 0.5
            to: 1
            buttonIcon: "tab_unselected"
            text: Translation.tr("Other windows opacity")
        }
        HyprSwitch {
            option: "decoration:dim_inactive"
            fallback: false
            buttonIcon: "brightness_low"
            text: Translation.tr("Dim unfocused windows")
        }
        HyprSlider {
            enabled: HyprlandSettings.get("decoration:dim_inactive", false)
            option: "decoration:dim_strength"
            fallback: 0.05
            from: 0
            to: 0.5
            buttonIcon: "contrast"
            text: Translation.tr("Dim strength")
        }
    }

    ContentSection {
        title: Translation.tr("Motion")

        HyprSwitch {
            option: "animations:enabled"
            fallback: true
            buttonIcon: "animation"
            text: Translation.tr("Window animations")
            description: Translation.tr("Opening, closing and moving windows and workspaces")
        }
        HyprSwitch {
            enabled: HyprlandSettings.get("animations:enabled", true)
            option: "misc:animate_manual_resizes"
            buttonIcon: "open_in_full"
            text: Translation.tr("Animate manual resizing")
        }
        HyprSwitch {
            enabled: HyprlandSettings.get("animations:enabled", true)
            option: "misc:animate_mouse_windowdragging"
            buttonIcon: "drag_pan"
            text: Translation.tr("Animate dragging windows")
        }
    }

    ContentSection {
        title: Translation.tr("Screen corners")
        description: Translation.tr("Draws rounded corners on the edges of the screen")

        ConfigSelectionArray {
            Layout.topMargin: 10
            currentValue: Config.options.appearance.fakeScreenRounding
            onSelected: newValue => {
                Config.options.appearance.fakeScreenRounding = newValue;
            }
            options: [
                { displayName: Translation.tr("No"), icon: "close", value: 0 },
                { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                { displayName: Translation.tr("When not fullscreen"), icon: "fullscreen_exit", value: 2 }
            ]
        }
    }

    ContentSection {
        title: Translation.tr("App theming")
        description: Translation.tr("Which apps get colors generated from the wallpaper")

        ConfigSwitch {
            buttonIcon: "hardware"
            text: Translation.tr("Shell & utilities")
            checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked;
            }
        }
        ConfigSwitch {
            enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
            buttonIcon: "tv_options_input_settings"
            text: Translation.tr("Qt apps")
            checked: Config.options.appearance.wallpaperTheming.enableQtApps
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableQtApps = checked;
            }
        }
        ConfigSwitch {
            enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
            buttonIcon: "terminal"
            text: Translation.tr("Terminal")
            checked: Config.options.appearance.wallpaperTheming.enableTerminal
            onCheckedChanged: {
                Config.options.appearance.wallpaperTheming.enableTerminal = checked;
            }
        }
        ContentSubsection {
            title: Translation.tr("Terminal colors")
            enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell && Config.options.appearance.wallpaperTheming.enableTerminal
            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("Force dark mode in terminal")
                checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
                onCheckedChanged: {
                    Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = checked;
                }
            }
            ConfigSpinBox {
                icon: "invert_colors"
                text: Translation.tr("Terminal: Harmony (%)")
                value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
                from: 0
                to: 100
                stepSize: 10
                onValueChanged: {
                    Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = value / 100;
                }
            }
            ConfigSpinBox {
                icon: "gradient"
                text: Translation.tr("Terminal: Harmonize threshold")
                value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
                from: 0
                to: 100
                stepSize: 10
                onValueChanged: {
                    Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = value;
                }
            }
            ConfigSpinBox {
                icon: "format_color_text"
                text: Translation.tr("Terminal: Foreground boost (%)")
                value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100
                from: 0
                to: 100
                stepSize: 10
                onValueChanged: {
                    Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = value / 100;
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Fonts")
        description: Translation.tr("Font family names as installed on your system")

        FontRow {
            fontKey: "main"
            icon: "match_case"
            label: Translation.tr("Main font")
            description: Translation.tr("Used for general UI text")
            placeholderText: "Google Sans Flex"
        }
        FontRow {
            fontKey: "title"
            icon: "title"
            label: Translation.tr("Title font")
            description: Translation.tr("Used for headings and titles")
            placeholderText: "Google Sans Flex"
        }
        FontRow {
            fontKey: "numbers"
            icon: "123"
            label: Translation.tr("Numbers font")
            description: Translation.tr("Used for displaying numbers")
            placeholderText: "Google Sans Flex"
        }
        FontRow {
            fontKey: "monospace"
            icon: "code"
            label: Translation.tr("Monospace font")
            description: Translation.tr("Used for code and terminal")
            placeholderText: "JetBrains Mono NF"
        }
        FontRow {
            fontKey: "iconNerd"
            icon: "emoji_symbols"
            label: Translation.tr("Nerd font icons")
            description: Translation.tr("Font used for Nerd Font icons")
            placeholderText: "JetBrains Mono NF"
        }
        FontRow {
            fontKey: "reading"
            icon: "menu_book"
            label: Translation.tr("Reading font")
            description: Translation.tr("Used for reading large blocks of text")
            placeholderText: "Readex Pro"
        }
        FontRow {
            fontKey: "expressive"
            icon: "brush"
            label: Translation.tr("Expressive font")
            description: Translation.tr("Used for decorative/expressive text")
            placeholderText: "Space Grotesk"
        }
    }
}
