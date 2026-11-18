import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.mouse

SettingsDetailPage {
    id: pageRoot
    property bool editingTouchpad: false
    property string demoId: ""
    readonly property var demoGesture: featuredGestures.find(g => g.id === demoId) ?? featuredGestures[0] ?? null
    property string gestureId: ""
    readonly property var selectedGesture: GestureSettings.gestures.find(g => g.id === gestureId) ?? GestureSettings.gestures[0] ?? null
    readonly property var basicGestures: GestureSettings.gestures.filter(g => !g.mods)
    readonly property var modifiedGestures: GestureSettings.gestures.filter(g => g.mods)
    readonly property var selectedRule: selectedGesture ? GestureSettings.overrides[selectedGesture.id] : undefined
    readonly property string selectedAction: selectedGesture ? actionFor(selectedGesture) : ""
    sectionTitles: ({
        wheel: Translation.tr("Mouse wheel and acceleration"),
        touchpad: Translation.tr("Touchpad"),
        gestures: Translation.tr("Gestures"),
        modified: Translation.tr("Gestures with a modifier key"),
        gestureAction: selectedGesture ? GestureSettings.shape(selectedGesture) : Translation.tr("Gesture action"),
        cursor: Translation.tr("Focus and cursor")
    })
    sectionParents: ({modified: "gestures", gestureAction: selectedGesture?.mods ? "modified" : "gestures"})
    readonly property var featuredGestures: {
        const preferred = ["workspaces", "overview", "app_library"].map(key => basicGestures.find(g => g.id === key)).filter(Boolean);
        return preferred.concat(basicGestures.filter(g => !preferred.includes(g))).slice(0, 3);
    }
    onBasicGesturesChanged: searchContentChanged()
    onModifiedGesturesChanged: searchContentChanged()

    function actionFor(gesture) {
        const rule = GestureSettings.overrides[gesture.id];
        return rule === false ? "none" : (rule?.action ?? gesture.default_action ?? gesture.action);
    }
    component GestureRow: ConfigNavRow {
        required property var modelData
        buttonIcon: modelData.direction.startsWith("pinch") ? "pinch" : "swipe"
        title: GestureSettings.shape(modelData)
        description: pageRoot.actionFor(modelData) === "command" ? Translation.tr("Run a command") : GestureSettings.actionName(pageRoot.actionFor(modelData))
        searchText: title + " " + description + " " + Translation.tr(modelData.description)
        onClicked: {
            forceActiveFocus();
            pageRoot.gestureId = modelData.id;
            pageRoot.tab = "gestureAction";
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        SettingsBranch {
            id: overviewBranch
            key: "overview"
            page: pageRoot

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Input test")
                        color: Appearance.colors.colOnLayer1
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                    }
                    ConfigSelectionArray {
                        objectName: "inputDeviceSelector"
                        Layout.fillWidth: false
                        Layout.leftMargin: 0; Layout.rightMargin: 0; Layout.bottomMargin: 0
                        currentValue: pageRoot.editingTouchpad
                        options: [
                            {displayName: Translation.tr("Mouse"), icon:"mouse", value:false},
                            {displayName: Translation.tr("Touchpad"), icon:"touchpad_mouse", value:true}
                        ]
                        onSelected: value => pageRoot.editingTouchpad = value
                    }
                }
                GridLayout {
                    id: inputLab
                    Layout.fillWidth: true
                    columns: width >= 510 ? 2 : 1
                    columnSpacing: 18
                    rowSpacing: 6
                    Item {
                        Layout.preferredWidth: 266
                        Layout.fillWidth: true
                        Layout.minimumWidth: 150
                        implicitHeight: 174
                        PointerPreview { anchors.fill: parent; visible: !pageRoot.editingTouchpad }
                        TouchpadPreview { anchors.fill: parent; visible: pageRoot.editingTouchpad }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: 305
                        spacing: 4
                        HyprSlider {
                            visible: !pageRoot.editingTouchpad
                            option: "input:sensitivity"
                            fallback: 0
                            from: -1; to: 1
                            textWidth: 62
                            buttonIcon: "speed"
                            text: Translation.tr("Pointer speed")
                            defaultHint: Translation.tr("0 is the device's own speed")
                        }
                        HyprSwitch {
                            visible: !pageRoot.editingTouchpad
                            option: "input:natural_scroll"
                            buttonIcon: "swap_vert"
                            text: Translation.tr("Natural scrolling for mice")
                        }
                        SettingsBranchLink { visible: !pageRoot.editingTouchpad; branch: wheelBranch; title: Translation.tr("Wheel and acceleration"); buttonIcon: "tune" }
                        HyprSwitch {
                            visible: pageRoot.editingTouchpad
                            option: "input:touchpad:tap_to_click"
                            fallback: true
                            buttonIcon: "touch_app"
                            text: Translation.tr("Tap to click")
                        }
                        HyprSwitch {
                            visible: pageRoot.editingTouchpad
                            option: "input:touchpad:natural_scroll"
                            fallback: true
                            buttonIcon: "swap_vert"
                            text: Translation.tr("Natural scrolling")
                        }
                        SettingsBranchLink { visible: pageRoot.editingTouchpad; branch: touchpadBranch; title: Translation.tr("Clicks and scrolling"); buttonIcon: "tune" }
                    }
                }
            }

            ContentSection {
                card: false
                title: Translation.tr("Gesture shortcuts")
                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 430 ? 2 : 1
                    columnSpacing: 14; rowSpacing: 4
                    visible: !!pageRoot.demoGesture
                    GesturePreview {
                        Layout.margins: 0
                        Layout.preferredWidth: 180
                        Layout.minimumWidth: 110
                        gesture: pageRoot.demoGesture
                        shown: pageRoot.pageShown && overviewBranch.shown
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 305
                        spacing: 2
                        Repeater {
                            model: pageRoot.featuredGestures
                            delegate: RippleButton {
                                id: shortcut
                                required property var modelData
                                readonly property string assignment: pageRoot.actionFor(modelData)
                                readonly property string label: assignment === "command" ? Translation.tr("Run a command") : GestureSettings.actionName(assignment)
                                Layout.fillWidth: true
                                implicitHeight: Math.max(36, contentItem.implicitHeight + 9)
                                horizontalPadding: 10; verticalPadding: 3
                                buttonRadius: Appearance.rounding.small
                                colBackground: pageRoot.demoGesture?.id === modelData.id ? Appearance.colors.colLayer2 : "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                Accessible.name: label + " · " + GestureSettings.shape(modelData)
                                onHoveredChanged: if (hovered) pageRoot.demoId = modelData.id
                                onActiveFocusChanged: if (activeFocus) pageRoot.demoId = modelData.id
                                onClicked: {
                                    forceActiveFocus();
                                    pageRoot.gestureId = modelData.id;
                                    pageRoot.tab = "gestureAction";
                                }
                                contentItem: RowLayout {
                                    spacing: 5
                                    StyledText { Layout.fillWidth: true; text: shortcut.label; wrapMode: Text.Wrap; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer2 }
                                    StyledText { text: GestureSettings.shape(shortcut.modelData); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                                    MaterialSymbol { text: "chevron_right"; iconSize: 14; color: Appearance.colors.colSubtext }
                                }
                            }
                        }
                    }
                }
                SettingsBranchLink {
                    branch: gesturesBranch
                    title: Translation.tr("All gestures")
                    buttonIcon: "swipe"
                    summary: GestureSettings.gestures.length ? String(GestureSettings.gestures.length) : ""
                    detail: Translation.tr("Actions, modifier keys and workspace swipes")
                }
            }
            ContentSection {
                SettingsBranchLink { branch: cursorBranch; buttonIcon: "arrow_selector_tool"; detail: Translation.tr("Window focus and when to hide the pointer") }
            }
        }
        SettingsBranch {
            id: wheelBranch
            page: pageRoot
            key: "wheel"
            ContentSection {
                title: pageRoot.sectionTitles.wheel
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
        }
        SettingsBranch {
            id: touchpadBranch
            page: pageRoot
            key: "touchpad"
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
                    description: Translation.tr("Tap with one finger for left click or two for right click. Turn off to click only by physically pressing the touchpad.")
                }
                HyprChoice {
                    option: "input:touchpad:clickfinger_behavior"
                    fallback: true
                    title: Translation.tr("Physical right click")
                    description: Translation.tr("Two-finger mode: press with one finger for left click or two for right click anywhere. Works with tap to click off.")
                    choices: [
                        { displayName: Translation.tr("Two-finger click"), icon: "touch_app", value: true },
                        { displayName: Translation.tr("Bottom-right corner"), icon: "ads_click", value: false }
                    ]
                }
                HyprSwitch {
                    option: "input:touchpad:disable_while_typing"
                    buttonIcon: "keyboard_hide"
                    text: Translation.tr("Ignore touchpad while typing")
                }
                HyprSlider {
                    option: "input:touchpad:scroll_factor"
                    fallback: 0.5
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
                    defaultValue: 10
                    defaultValueText: "10×"
                    value: Config.options.interactions.scrolling.touchpadSpeed
                    onMoved: Config.options.interactions.scrolling.touchpadSpeed = Math.round(value)
                }
            }
        }
        SettingsBranch {
            id: gesturesBranch
            page: pageRoot
            key: "gestures"
            ContentSection {
                title: Translation.tr("Gestures")
                Repeater { model: pageRoot.basicGestures; delegate: GestureRow {} }
                StyledText {
                    visible: GestureSettings.gestures.length === 0
                    Layout.margins: 12
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("No gestures have been reported by Hyprland.")
                    color: Appearance.colors.colSubtext
                }
                SettingsBranchLink { visible: pageRoot.modifiedGestures.length > 0; branch: modifiedBranch; buttonIcon: "keyboard"; detail: Translation.tr("Swipes and pinches with a key held down") }
            }
            ContentSection {
                title: Translation.tr("Workspace swipes")
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
                visible: Object.keys(GestureSettings.overrides).length > 0
                ConfigNavRow {
                    buttonIcon: "restart_alt"
                    title: Translation.tr("Reset gestures")
                    trailingIcon: ""
                    onClicked: GestureSettings.reset()
                }
            }
        }
        SettingsBranch {
            id: modifiedBranch
            page: pageRoot
            key: "modified"
            ContentSection {
                title: pageRoot.sectionTitles.modified
                Repeater { model: pageRoot.modifiedGestures; delegate: GestureRow {} }
            }
        }
        SettingsBranch {
            page: pageRoot
            key: "gestureAction"
            ContentSection {
                title: pageRoot.sectionTitles.gestureAction
                GesturePreview { shown: pageRoot.pageShown && pageRoot.tab === "gestureAction"; gesture: pageRoot.selectedGesture }
                ConfigComboRow {
                    id: gestureAction
                    objectName: "gestureActionPicker"
                    enabled: !!pageRoot.selectedGesture
                    text: Translation.tr("Gesture action")
                    description: pageRoot.selectedGesture ? Translation.tr("Default action: %1").arg(GestureSettings.actionName(pageRoot.selectedGesture.default_action ?? pageRoot.selectedGesture.action)) : ""
                    icon: "gesture"
                    options: GestureSettings.actions
                    currentValue: pageRoot.selectedAction
                    customLabel: Translation.tr("Run a command")
                    customPlaceholder: "kitty"
                    customActive: pageRoot.selectedAction === "command"
                    customValue: pageRoot.selectedRule?.command ?? pageRoot.selectedGesture?.command ?? ""
                    onSelected: value => GestureSettings.setAction(pageRoot.selectedGesture.id, value)
                    onCustomEntered: text => GestureSettings.setAction(pageRoot.selectedGesture.id, "command", text)
                }
                ConfigNavRow {
                    visible: pageRoot.selectedRule !== undefined
                    buttonIcon: "restart_alt"
                    title: Translation.tr("Restore default action")
                    trailingIcon: ""
                    onClicked: GestureSettings.reset(pageRoot.selectedGesture.id)
                }
            }
        }
        SettingsBranch {
            id: cursorBranch
            page: pageRoot
            key: "cursor"
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
    }
}
