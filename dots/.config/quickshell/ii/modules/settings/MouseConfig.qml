import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    ContentSection {
        title: Translation.tr("Pointer")

        HyprSlider {
            option: "input:sensitivity"
            fallback: 0
            from: -1
            to: 1
            buttonIcon: "speed"
            text: Translation.tr("Speed")
            description: Translation.tr("0 is the device's own speed")
        }
        HyprChoice {
            option: "input:accel_profile"
            fallback: ""
            title: Translation.tr("Acceleration")
            choices: [
                { displayName: Translation.tr("Default"), icon: "restart_alt", value: "" },
                { displayName: Translation.tr("Adaptive"), icon: "trending_up", value: "adaptive" },
                { displayName: Translation.tr("Flat"), icon: "trending_flat", value: "flat" }
            ]
        }
        HyprSwitch {
            option: "input:natural_scroll"
            buttonIcon: "swap_vert"
            text: Translation.tr("Natural scrolling for mice")
            description: Translation.tr("Content moves the same way as the wheel")
        }
        HyprSlider {
            option: "input:scroll_factor"
            fallback: 1
            decimals: 1
            from: 0.1
            to: 5
            buttonIcon: "unfold_more"
            text: Translation.tr("Scroll speed")
        }
    }

    ContentSection {
        title: Translation.tr("Touchpad")

        HyprSwitch {
            option: "input:touchpad:natural_scroll"
            fallback: true
            buttonIcon: "swap_vert"
            text: Translation.tr("Natural scrolling")
        }
        HyprSwitch {
            option: "input:touchpad:tap_to_click"
            buttonIcon: "touch_app"
            text: Translation.tr("Tap to click")
        }
        HyprSwitch {
            option: "input:touchpad:clickfinger_behavior"
            fallback: true
            buttonIcon: "ads_click"
            text: Translation.tr("Two-finger click for right click")
            description: Translation.tr("Instead of clicking in the bottom right corner")
        }
        HyprSwitch {
            option: "input:touchpad:disable_while_typing"
            buttonIcon: "keyboard_hide"
            text: Translation.tr("Ignore touchpad while typing")
        }
        HyprSlider {
            option: "input:touchpad:scroll_factor"
            fallback: 1
            decimals: 1
            from: 0.1
            to: 5
            buttonIcon: "unfold_more"
            text: Translation.tr("Scroll speed")
        }
        ConfigSlider {
            buttonIcon: "speed"
            text: Translation.tr("Scroll speed in the shell")
            description: Translation.tr("Settings, sidebars and lists. Browsers and Electron apps scroll about 10× the speed above, so 10 matches them.")
            from: 1
            to: 20
            usePercentTooltip: false
            valueText: `${Math.round(value)}×`
            value: Config.options.interactions.scrolling.touchpadSpeed
            onMoved: Config.options.interactions.scrolling.touchpadSpeed = Math.round(value)
        }
    }

    ContentSection {
        title: Translation.tr("Gestures")
        description: Translation.tr("Swipe with four fingers sideways to switch workspaces, up for the overview")

        HyprSlider {
            option: "gestures:workspace_swipe_distance"
            fallback: 700
            integer: true
            from: 100
            to: 1500
            buttonIcon: "swipe"
            text: Translation.tr("Swipe distance")
            description: Translation.tr("How far you need to swipe to change workspace")
        }
        HyprSwitch {
            option: "gestures:workspace_swipe_create_new"
            fallback: true
            buttonIcon: "add_box"
            text: Translation.tr("Swiping past the last workspace creates a new one")
        }
    }

    ContentSection {
        title: Translation.tr("Focus")

        HyprChoice {
            option: "input:follow_mouse"
            fallback: 1
            title: Translation.tr("Focus follows the pointer")
            description: Translation.tr("Always: hovering a window focuses it. On click: the pointer and the keyboard focus separately until you click. Separate: clicking doesn't move keyboard focus either.")
            choices: [
                { displayName: Translation.tr("Never"), icon: "block", value: 0 },
                { displayName: Translation.tr("Always"), icon: "arrow_selector_tool", value: 1 },
                { displayName: Translation.tr("On click"), icon: "ads_click", value: 2 },
                { displayName: Translation.tr("Separate"), icon: "call_split", value: 3 }
            ]
        }
    }

    ContentSection {
        title: Translation.tr("Cursor")

        HyprSpinBox {
            option: "cursor:inactive_timeout"
            fallback: 0
            from: 0
            to: 60
            stepSize: 1
            icon: "timer"
            text: Translation.tr("Hide after inactivity (s)")
            description: Translation.tr("0 never hides it")
        }
        HyprSwitch {
            option: "cursor:hide_on_key_press"
            buttonIcon: "keyboard"
            text: Translation.tr("Hide while typing")
        }
    }
}
