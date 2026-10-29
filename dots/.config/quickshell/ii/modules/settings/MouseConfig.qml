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
            fallback: true
            buttonIcon: "touch_app"
            text: Translation.tr("Tap to click")
            description: Translation.tr("Two-finger tap for right click, independently of physical click method")
        }
        HyprChoice {
            option: "input:touchpad:clickfinger_behavior"
            fallback: false
            title: Translation.tr("Physical right click")
            choices: [
                { displayName: Translation.tr("Bottom-right corner"), icon: "ads_click", value: false },
                { displayName: Translation.tr("Two-finger click"), icon: "touch_app", value: true }
            ]
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
        description: Translation.tr("Four fingers: sideways for workspaces, up for the overview, toward you for all apps. Hold a key for more.")

        Repeater {
            model: GestureSettings.gestures

            delegate: ConfigComboRow {
                id: gestureRow
                required property var modelData
                readonly property string action: modelData.action
                icon: ({ "up": "swipe_up", "down": "swipe_down", "left": "swipe_left", "right": "swipe_right", "horizontal": "swipe",
                    "vertical": "swipe_vertical", "pinchin": "pinch_zoom_in", "pinchout": "pinch_zoom_out", "pinch": "pinch" })[modelData.direction] ?? "gesture"
                text: GestureSettings.shape(modelData)
                description: Translation.tr(modelData.description)
                options: GestureSettings.actions
                currentValue: gestureRow.action
                customLabel: Translation.tr("Run a command")
                customPlaceholder: "kitty"
                customActive: gestureRow.action === "command"
                customValue: modelData.command ?? ""
                onSelected: value => GestureSettings.setAction(gestureRow.modelData.id, value)
                onCustomEntered: text => GestureSettings.setAction(gestureRow.modelData.id, "command", text)
            }
        }
        RippleButtonWithIcon {
            visible: Object.keys(GestureSettings.overrides).length > 0
            Layout.alignment: Qt.AlignRight
            materialIcon: "restart_alt"
            mainText: Translation.tr("Reset gestures")
            onClicked: GestureSettings.reset()
        }

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
