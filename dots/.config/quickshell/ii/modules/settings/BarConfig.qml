import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    ContentSection {
        icon: "spoke"
        title: Translation.tr("Position & style")
        description: Translation.tr("Where the bar sits and how it's drawn")

        ConfigNavRow {
            buttonIcon: "view_column"
            title: Translation.tr("Arrange widgets")
            description: Translation.tr("Place any widget anywhere on the bar, add new ones and set each up")
            onClicked: ApplicationWindow.window?.openPage("barLayout")
        }

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar position")
                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                    options: [
                        { displayName: Translation.tr("Top"), icon: "arrow_upward", value: 0 },
                        { displayName: Translation.tr("Left"), icon: "arrow_back", value: 2 },
                        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                        { displayName: Translation.tr("Right"), icon: "arrow_forward", value: 3 }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Background")
                ConfigSelectionArray {
                    readonly property var bar: Config.options.bar
                    currentValue: bar.style.islands ? "islands" : !bar.showBackground ? "none" : bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.style.islands = newValue === "islands";
                        Config.options.bar.showBackground = newValue !== "none";
                        if (typeof newValue === "number") Config.options.bar.cornerStyle = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Hug"), icon: "line_curve", value: 0 },
                        { displayName: Translation.tr("Float"), icon: "page_header", value: 1 },
                        { displayName: Translation.tr("Rect"), icon: "toolbar", value: 2 },
                        { displayName: Translation.tr("Islands"), icon: "view_agenda", value: "islands" },
                        { displayName: Translation.tr("None"), icon: "texture", value: "none" }
                    ]
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Widget groups")
            ConfigSelectionArray {
                currentValue: Config.options.bar.borderless ? "none" : Config.options.bar.style.pillStyle
                onSelected: newValue => {
                    Config.options.bar.style.pillStyle = newValue;
                    Config.options.bar.borderless = newValue === "none";
                }
                options: [
                    { displayName: Translation.tr("Filled pills"), icon: "location_chip", value: "filled" },
                    { displayName: Translation.tr("Outlined pills"), icon: "crop_free", value: "outlined" },
                    { displayName: Translation.tr("No pills"), icon: "split_scene", value: "none" }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "opacity"
            text: Translation.tr("Own transparency")
            description: Translation.tr("Set the bar's opacity apart from the rest of the theme")
            autoToggle: false
            checked: Config.options.bar.style.backgroundOpacity >= 0
            onClicked: Config.options.bar.style.backgroundOpacity = checked ? -1 : Math.round(Appearance.colors.barOpacity * 100) / 100
        }
        ConfigSlider {
            visible: Config.options.bar.style.backgroundOpacity >= 0
            buttonIcon: "gradient"
            text: Translation.tr("Opacity")
            value: Math.max(0, Config.options.bar.style.backgroundOpacity)
            onMoved: Config.options.bar.style.backgroundOpacity = Math.round(value * 100) / 100
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Glass")
                description: Translation.tr("Blur what's behind a see-through bar")
                autoToggle: false
                checked: Config.options.bar.style.glass
                onClicked: Config.options.bar.style.glass = !Config.options.bar.style.glass
            }
            ConfigSwitch {
                buttonIcon: "format_shadow"
                text: Translation.tr("Text shadow")
                description: Translation.tr("Keeps text readable over the wallpaper")
                autoToggle: false
                checked: Config.options.bar.style.textShadow
                onClicked: Config.options.bar.style.textShadow = !Config.options.bar.style.textShadow
            }
        }
        ConfigSwitch {
            buttonIcon: "shadow"
            text: Translation.tr("Shadow under floating bars and islands")
            autoToggle: false
            checked: Config.options.bar.floatStyleShadow
            onClicked: Config.options.bar.floatStyleShadow = !Config.options.bar.floatStyleShadow
        }

        ContentSubsection {
            title: Translation.tr("Sizes")
            description: Translation.tr("Leave a size at its default to follow the theme")

            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Thickness")
                from: 24
                to: 96
                stepSize: 1
                value: Config.options.bar.vertical ? Appearance.sizes.baseVerticalBarWidth : Appearance.sizes.baseBarHeight
                onValueChanged: {
                    const current = Config.options.bar.vertical ? Appearance.sizes.baseVerticalBarWidth : Appearance.sizes.baseBarHeight;
                    if (value !== current) Config.options.bar.style.thickness = value;
                }
            }
            ConfigSpinBox {
                icon: "padding"
                text: Translation.tr("Space at the screen edges")
                from: 0
                to: 80
                stepSize: 1
                value: Config.options.bar.style.edgePadding >= 0 ? Config.options.bar.style.edgePadding : Appearance.rounding.screenRounding
                onValueChanged: if (value !== (Config.options.bar.style.edgePadding >= 0 ? Config.options.bar.style.edgePadding : Appearance.rounding.screenRounding)) Config.options.bar.style.edgePadding = value
            }
            ConfigSpinBox {
                icon: "margin"
                text: Translation.tr("Gap around a floating bar")
                from: 0
                to: 60
                stepSize: 1
                value: Appearance.sizes.barFloatMargin
                onValueChanged: if (value !== Appearance.sizes.barFloatMargin) Config.options.bar.style.floatMargin = value
            }
            ConfigSpinBox {
                icon: "rounded_corner"
                text: Translation.tr("Corner radius of floating bars and islands")
                from: 0
                to: 60
                stepSize: 1
                value: Config.options.bar.style.radius >= 0 ? Config.options.bar.style.radius : Appearance.rounding.windowRounding
                onValueChanged: if (value !== (Config.options.bar.style.radius >= 0 ? Config.options.bar.style.radius : Appearance.rounding.windowRounding)) Config.options.bar.style.radius = value
            }
            DialogButton {
                buttonText: Translation.tr("Default sizes")
                onClicked: {
                    Config.options.bar.style.thickness = -1;
                    Config.options.bar.style.edgePadding = -1;
                    Config.options.bar.style.floatMargin = -1;
                    Config.options.bar.style.radius = -1;
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "visibility_off"
            text: Translation.tr("Automatically hide")
            description: Translation.tr("The bar appears when you move the pointer to its edge")
            autoToggle: false
            checked: Config.options.bar.autoHide.enable
            onClicked: Config.options.bar.autoHide.enable = !Config.options.bar.autoHide.enable
        }
    }

    ContentSection {
        icon: "workspaces"
        title: Translation.tr("Workspaces")
        description: Translation.tr("The workspace indicator in the middle of the bar")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "counter_1"
                text: Translation.tr('Always show numbers')
                checked: Config.options.bar.workspaces.alwaysShowNumbers
                onCheckedChanged: {
                    Config.options.bar.workspaces.alwaysShowNumbers = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "award_star"
                text: Translation.tr('Show app icons')
                checked: Config.options.bar.workspaces.showAppIcons
                onCheckedChanged: {
                    Config.options.bar.workspaces.showAppIcons = checked;
                }
            }
        }
        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr('Tint app icons')
            checked: Config.options.bar.workspaces.monochromeIcons
            onCheckedChanged: {
                Config.options.bar.workspaces.monochromeIcons = checked;
            }
        }
        ConfigSpinBox {
            icon: "view_column"
            text: Translation.tr("Workspaces shown")
            value: Config.options.bar.workspaces.shown
            from: 1
            to: 30
            stepSize: 1
            onValueChanged: {
                Config.options.bar.workspaces.shown = value;
            }
        }
        ConfigSpinBox {
            icon: "touch_long"
            text: Translation.tr("Number show delay when pressing Super (ms)")
            value: Config.options.bar.workspaces.showNumberDelay
            from: 0
            to: 1000
            stepSize: 50
            onValueChanged: {
                Config.options.bar.workspaces.showNumberDelay = value;
            }
        }
        ContentSubsection {
            title: Translation.tr("Number style")
            ConfigSelectionArray {
                currentValue: JSON.stringify(Config.options.bar.workspaces.numberMap)
                onSelected: newValue => {
                    Config.options.bar.workspaces.numberMap = JSON.parse(newValue)
                }
                options: [
                    { displayName: Translation.tr("Normal"), icon: "timer_10", value: '[]' },
                    { displayName: Translation.tr("Han chars"), icon: "square_dot", value: '["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]' },
                    { displayName: Translation.tr("Roman"), icon: "account_balance", value: '["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII","XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX"]' }
                ]
            }
        }
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("Utility buttons")
        description: Translation.tr("Small shortcut buttons next to the clock")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "content_cut"
                text: Translation.tr("Screen snip")
                checked: Config.options.bar.utilButtons.showScreenSnip
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenSnip = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "colorize"
                text: Translation.tr("Color picker")
                checked: Config.options.bar.utilButtons.showColorPicker
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showColorPicker = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Keyboard toggle")
                checked: Config.options.bar.utilButtons.showKeyboardToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showKeyboardToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "mic"
                text: Translation.tr("Mic toggle")
                checked: Config.options.bar.utilButtons.showMicToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showMicToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("Dark/Light toggle")
                checked: Config.options.bar.utilButtons.showDarkModeToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showDarkModeToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "speed"
                text: Translation.tr("Performance Profile toggle")
                checked: Config.options.bar.utilButtons.showPerformanceProfileToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showPerformanceProfileToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "videocam"
                text: Translation.tr("Record")
                checked: Config.options.bar.utilButtons.showScreenRecord
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenRecord = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "developer_board"
                text: Translation.tr("GPU mode toggle")
                description: Translation.tr("supergfxctl, if installed")
                checked: Config.options.bar.utilButtons.showSupergfxctlToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showSupergfxctlToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "coffee"
                text: Translation.tr("Keep awake")
                checked: Config.options.bar.utilButtons.showIdleInhibitor
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showIdleInhibitor = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "bedtime"
                text: Translation.tr("Night Light")
                checked: Config.options.bar.utilButtons.showNightLight
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showNightLight = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "notifications_paused"
                text: Translation.tr("Do not disturb")
                checked: Config.options.bar.utilButtons.showDoNotDisturb
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showDoNotDisturb = checked;
                }
            }
        }
    }

    ContentSection {
        icon: "dynamic_feed"
        title: Translation.tr("Live activities")
        description: Translation.tr("The media slot shows what's going on right now, then returns to music")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "screen_record"
                text: Translation.tr("Screen recording")
                checked: Config.options.bar.island.showRecording
                onCheckedChanged: {
                    Config.options.bar.island.showRecording = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "target"
                text: Translation.tr("Pomodoro")
                checked: Config.options.bar.island.showPomodoro
                onCheckedChanged: {
                    Config.options.bar.island.showPomodoro = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Stopwatch")
                checked: Config.options.bar.island.showStopwatch
                onCheckedChanged: {
                    Config.options.bar.island.showStopwatch = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "album"
                text: Translation.tr("Track change card")
                description: Translation.tr("Cover and title for 3 seconds")
                checked: Config.options.bar.island.trackToast
                onCheckedChanged: {
                    Config.options.bar.island.trackToast = checked;
                }
            }
        }
    }

    ContentSection {
        icon: "notifications"
        title: Translation.tr("Indicators")
        description: Translation.tr("Status icons on the right side of the bar")

        ConfigNavRow {
            buttonIcon: "notifications"
            title: Translation.tr("Notification indicator")
            onClicked: ApplicationWindow.window?.openPage("notifications")
        }
        ConfigSwitch {
            buttonIcon: "privacy_tip"
            text: Translation.tr("Privacy indicator")
            description: Translation.tr("Shows when apps use the microphone, a camera or capture the screen")
            checked: Config.options.bar.indicators.privacy
            onCheckedChanged: {
                Config.options.bar.indicators.privacy = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "bluetooth"
            text: Translation.tr("Bluetooth device battery")
            description: Translation.tr("Charge of connected headphones and other devices that report it")
            checked: Config.options.bar.indicators.bluetoothBattery
            onCheckedChanged: {
                Config.options.bar.indicators.bluetoothBattery = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "partly_cloudy_day"
            text: Translation.tr("Weather")
            description: Translation.tr("Location and units are set in Widgets › Weather")
            autoToggle: false
            checked: Config.options.bar.weather.enable
            onClicked: Config.options.bar.weather.enable = !Config.options.bar.weather.enable
        }
    }

    ContentSection {
        icon: "shelf_auto_hide"
        title: Translation.tr("Tray")
        description: Translation.tr("Icons of background apps")

        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr('Make icons pinned by default')
            checked: Config.options.tray.invertPinnedItems
            onCheckedChanged: {
                Config.options.tray.invertPinnedItems = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr('Tint icons')
            checked: Config.options.tray.monochromeIcons
            onCheckedChanged: {
                Config.options.tray.monochromeIcons = checked;
            }
        }
    }

    ContentSection {
        icon: "animation"
        title: Translation.tr("Motion")

        ConfigSwitch {
            buttonIcon: "motion_play"
            text: Translation.tr("Micro-animations")
            description: Translation.tr("Rolling numbers, popup transitions, press feedback and scrolling titles. Turn off on slow hardware")
            checked: Config.options.bar.microAnimations
            onCheckedChanged: {
                Config.options.bar.microAnimations = checked;
            }
        }
    }

    ContentSection {
        icon: "tooltip"
        title: Translation.tr("Tooltips")

        ConfigSwitch {
            buttonIcon: "ads_click"
            text: Translation.tr("Click to show")
            description: Translation.tr("Popups of bar items open on click instead of hover")
            checked: Config.options.bar.tooltips.clickToShow
            onCheckedChanged: {
                Config.options.bar.tooltips.clickToShow = checked;
            }
        }
    }
}
