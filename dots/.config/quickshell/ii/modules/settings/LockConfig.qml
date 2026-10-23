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
 * The lock screen: the real one in miniature to arrange by dragging, ready-made arrangements, the parts
 * to show with the settings of the one you pick, then the background, motion, password and security.
 */
ContentPage {
    id: page
    readonly property var lock: Config.options.lock
    property string selectedId: "clock" // The part whose settings show under the parts
    readonly property var selectedSpec: LockElementCatalog.get(page.selectedId)
    readonly property var selectedItem: LockLayout.items[page.selectedId]

    // A lock.* switch
    component ShowRow: ConfigSwitch {
        property string key
        autoToggle: false
        checked: page.lock[key]
        onClicked: Config.options.lock[key] = !page.lock[key]
    }

    // A small button with an icon and text
    component ToolButton: RippleButton {
        id: toolButton
        property string buttonIcon
        implicitHeight: 36
        leftPadding: 12
        rightPadding: 14
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        contentItem: RowLayout {
            spacing: 6
            MaterialSymbol {
                text: toolButton.buttonIcon
                iconSize: 18
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                text: toolButton.text
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
        }
    }

    ContentSection {
        icon: "lock"
        title: Translation.tr("Your lock screen")
        card: false
        searchText: `${title} ${Translation.tr("Preview")} ${Translation.tr("Drag")}`

        LockEditor {
            id: editor
            Layout.fillWidth: true
            visible: !page.lock.useHyprlock
            selectedId: page.selectedId
            onSelectedIdChanged: if (editor.selectedId.length > 0) page.selectedId = editor.selectedId
        }

        Flow {
            Layout.fillWidth: true
            visible: !page.lock.useHyprlock
            spacing: 6
            ToolButton {
                buttonIcon: "open_in_full"
                text: Translation.tr("Open full screen")
                onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "lockEditor", "open"])
            }
            ToolButton {
                buttonIcon: "play_arrow"
                text: Translation.tr("Play locking")
                onClicked: editor.playEntrance()
            }
            ToolButton {
                buttonIcon: "lock_open"
                text: Translation.tr("Play unlocking")
                onClicked: editor.playUnlock()
            }
            ToolButton {
                buttonIcon: "undo"
                text: Translation.tr("Undo")
                enabled: LockLayout.canUndo
                opacity: enabled ? 1 : 0.5
                onClicked: LockLayout.undo()
            }
            ToolButton {
                buttonIcon: "restart_alt"
                text: Translation.tr("Reset")
                enabled: LockLayout.isCustom
                opacity: enabled ? 1 : 0.5
                onClicked: LockLayout.reset()
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: page.lock.useHyprlock ? Translation.tr("Hyprlock is in use, so these settings don't apply. Turn it off below to use the built-in lock screen.")
                : Translation.tr("Drag parts to move them; they snap to the middle, the thirds and each other. Click one to change it below, double-click to put it back. Super+L locks the screen.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        icon: "dashboard_customize"
        title: Translation.tr("Arrangement")
        visible: !page.lock.useHyprlock

        Flow {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: LockLayout.presets
                delegate: SchemeTile {
                    id: presetTile
                    required property var modelData
                    readonly property var previewItems: LockLayout.previewItems(modelData.id)
                    label: modelData.name
                    frameWidth: 120
                    frameHeight: 75
                    selected: LockLayout.matchesPreset(modelData.id)
                    onClicked: LockLayout.applyPreset(modelData.id)

                    // Where the parts would be: blocks in the shape of each
                    Repeater {
                        model: LockElementCatalog.ids.filter(id => presetTile.previewItems[id].show && presetTile.previewItems[id].attach !== "password")
                        delegate: Rectangle {
                            required property string modelData
                            readonly property var item: presetTile.previewItems[modelData]
                            readonly property var sizes: ({ "clock": [22, 16], "greeting": [20, 5], "password": [30, 6], "user": [12, 6], "power": [14, 6],
                                "message": [18, 3], "media": [26, 10], "weather": [16, 8], "notifications": [18, 5], "timer": [12, 6] })
                            width: sizes[modelData][0] * item.size
                            height: sizes[modelData][1] * item.size
                            x: Math.max(2, Math.min(presetTile.frameWidth - width - 2, item.x * presetTile.frameWidth - width / 2))
                            y: Math.max(2, Math.min(presetTile.frameHeight - height - 2, item.y * presetTile.frameHeight - height / 2))
                            radius: Math.min(height / 2, 4)
                            color: modelData === "clock" || modelData === "password" ? presetTile.ink : presetTile.faint
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("Parts")
        visible: !page.lock.useHyprlock

        // One chip per part: click to pick it, the eye shows or hides it
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            spacing: 6
            Repeater {
                model: LockElementCatalog.elements
                delegate: RippleButton {
                    id: partChip
                    required property var modelData
                    readonly property bool shown: LockLayout.items[modelData.id].show
                    readonly property bool picked: page.selectedId === modelData.id
                    readonly property bool settingsSearchable: true
                    property string searchText: modelData.name
                    implicitHeight: 38
                    leftPadding: 10
                    rightPadding: 6
                    buttonRadius: Appearance.rounding.full
                    colBackground: partChip.picked ? Appearance.colors.colPrimaryContainer : partChip.shown ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3
                    colBackgroundHover: partChip.picked ? Appearance.colors.colPrimaryContainerHover : partChip.shown ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover
                    onClicked: {
                        page.selectedId = modelData.id;
                        editor.selectedId = modelData.id;
                    }
                    contentItem: RowLayout {
                        spacing: 6
                        MaterialSymbol {
                            text: partChip.modelData.icon
                            iconSize: 18
                            fill: partChip.shown ? 1 : 0
                            color: partChip.shown ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: partChip.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: partChip.shown ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                        }
                        RippleButton {
                            visible: partChip.modelData.hideable
                            implicitWidth: 26
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            onClicked: LockLayout.setShown(partChip.modelData.id, !partChip.shown)
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: partChip.shown ? "visibility" : "visibility_off"
                                iconSize: 16
                                color: partChip.shown ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                            }
                            StyledToolTip {
                                text: partChip.shown ? Translation.tr("Hide") : Translation.tr("Show")
                            }
                        }
                    }
                }
            }
        }

        // The picked part
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            Layout.topMargin: 6
            implicitHeight: inspector.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: inspector
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                spacing: 4

                RowLayout {
                    Layout.leftMargin: 4
                    spacing: 12
                    MaterialShapeWrappedMaterialSymbol {
                        shape: MaterialShape.Shape.Cookie7Sided
                        text: page.selectedSpec?.icon ?? ""
                        iconSize: 22
                        padding: 8
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: page.selectedSpec?.name ?? ""
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: page.selectedSpec?.description ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    ToolButton {
                        buttonIcon: "settings_backup_restore"
                        text: Translation.tr("Put back")
                        onClicked: LockLayout.resetItem(page.selectedId)
                    }
                }

                ConfigSwitch {
                    visible: page.selectedSpec?.hideable ?? false
                    buttonIcon: "visibility"
                    text: Translation.tr("Show on the lock screen")
                    autoToggle: false
                    checked: page.selectedItem?.show ?? false
                    onClicked: LockLayout.setShown(page.selectedId, !page.selectedItem.show)
                }
                ConfigSwitch {
                    visible: page.selectedSpec?.attachable ?? false
                    buttonIcon: "link"
                    text: page.selectedId === "message" ? Translation.tr("Keep it above the password field") : Translation.tr("Keep it next to the password field")
                    description: Translation.tr("Dragging it anywhere sets it loose")
                    autoToggle: false
                    checked: page.selectedItem?.attach === "password"
                    onClicked: LockLayout.setAttached(page.selectedId, page.selectedItem.attach !== "password")
                }
                ConfigSlider {
                    visible: page.selectedSpec?.scalable ?? false
                    buttonIcon: "zoom_out_map"
                    text: Translation.tr("Size")
                    from: 0.5
                    to: 2
                    value: page.selectedItem?.size ?? 1
                    valueText: `${Math.round(value * 100)}%`
                    onMoved: LockLayout.setSize(page.selectedId, Math.round(value * 20) / 20)
                }

                // Clock
                ContentSubsection {
                    visible: page.selectedId === "clock"
                    title: Translation.tr("Clock style")
                    searchText: `${title} ${Translation.tr("Cookie")} ${Translation.tr("Digital")}`
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        SchemeTile {
                            id: cookieTile
                            label: Translation.tr("Cookie")
                            frameWidth: 112
                            frameHeight: 70
                            selected: Config.options.background.widgets.clock.styleLocked === "cookie"
                            onClicked: Config.options.background.widgets.clock.styleLocked = "cookie"
                            MaterialShape {
                                anchors.centerIn: parent
                                implicitSize: 50
                                shape: MaterialShape.Shape.Cookie9Sided
                                color: cookieTile.faint
                                Rectangle { x: 24; y: 10; width: 3; height: 16; radius: 1.5; color: cookieTile.ink }
                                Rectangle { x: 24; y: 24; width: 14; height: 3; radius: 1.5; color: cookieTile.ink }
                            }
                        }
                        SchemeTile {
                            id: digitalTile
                            label: Translation.tr("Digital")
                            frameWidth: 112
                            frameHeight: 70
                            selected: Config.options.background.widgets.clock.styleLocked === "digital"
                            onClicked: Config.options.background.widgets.clock.styleLocked = "digital"
                            StyledText { anchors.centerIn: parent; text: "12:30"; font.pixelSize: 22; font.family: Appearance.font.family.expressive; color: digitalTile.ink }
                        }
                    }
                }
                ShowRow {
                    visible: page.selectedId === "clock"
                    key: "showLockedText"
                    buttonIcon: "lock"
                    text: Translation.tr("Show “Locked” under the clock")
                }

                // User and power
                ShowRow {
                    visible: page.selectedId === "user"
                    key: "showUser"
                    buttonIcon: "account_circle"
                    text: Translation.tr("Your user name")
                }
                ShowRow {
                    visible: page.selectedId === "user"
                    key: "showKeyboardLayout"
                    buttonIcon: "keyboard_alt"
                    text: Translation.tr("Keyboard layout")
                    description: Translation.tr("Helps when the password doesn't work because of the layout")
                }
                ShowRow {
                    visible: page.selectedId === "power"
                    key: "showBattery"
                    buttonIcon: "battery_android_full"
                    text: Translation.tr("Battery")
                }
                ShowRow {
                    visible: page.selectedId === "power"
                    key: "showPowerButtons"
                    buttonIcon: "power_settings_new"
                    text: Translation.tr("Sleep, power off and restart buttons")
                }

                // Message
                ConfigTextRow {
                    visible: page.selectedId === "message"
                    icon: "chat"
                    label: Translation.tr("Text")
                    description: Translation.tr("For example, who to call if this computer is found. Press Enter to save.")
                    placeholderText: Translation.tr("If found, please call…")
                    inline: true
                    value: page.lock.message
                    onEditingFinished: Config.options.lock.message = value.trim()
                }

                // Weather
                ConfigSwitch {
                    visible: page.selectedId === "weather"
                    buttonIcon: "schedule"
                    text: Translation.tr("Show the next hours")
                    autoToggle: false
                    checked: LockLayout.items.weather.hours ?? false
                    onClicked: LockLayout.setItem("weather", { "hours": !(LockLayout.items.weather.hours ?? false) })
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.bottomMargin: 4
                    visible: ["media", "notifications", "timer"].includes(page.selectedId)
                    wrapMode: Text.Wrap
                    text: Translation.tr("Shows up only when there is something: music playing, notifications waiting or a timer running. Here an example stands in.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    ContentSection {
        icon: "wallpaper"
        title: Translation.tr("Background and motion")

        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr("Blur the wallpaper")
            autoToggle: false
            checked: page.lock.blur.enable
            onClicked: Config.options.lock.blur.enable = !page.lock.blur.enable
        }
        ConfigSlider {
            visible: page.lock.blur.enable
            buttonIcon: "blur_medium"
            text: Translation.tr("Blur strength")
            usePercentTooltip: false
            from: 10
            to: 200
            value: page.lock.blur.radius
            valueText: `${Math.round(value)}`
            onMoved: Config.options.lock.blur.radius = Math.round(value)
        }
        ConfigSlider {
            buttonIcon: "brightness_6"
            text: Translation.tr("Darken")
            description: Translation.tr("Makes the clock and text easier to read on bright wallpapers")
            from: 0
            to: 0.8
            value: page.lock.dim
            valueText: `${Math.round(value * 100)}%`
            onMoved: Config.options.lock.dim = Math.round(value * 100) / 100
        }
        ConfigSlider {
            buttonIcon: "zoom_in"
            text: Translation.tr("Zoom in a little")
            usePercentTooltip: false
            from: 1
            to: 1.5
            value: page.lock.blur.extraZoom
            valueText: `${Math.round(value * 100)}%`
            onMoved: Config.options.lock.blur.extraZoom = Math.round(value * 100) / 100
        }
        ShowRow {
            key: "animatedWallpaper"
            buttonIcon: "animated_images"
            text: Translation.tr("Keep a live wallpaper moving")
            description: Translation.tr("A video or animated wallpaper goes on playing behind the lock screen, except with energy saving")
        }
        ContentSubsection {
            title: Translation.tr("Animations")
            searchText: `${title} ${Translation.tr("Lively")} ${Translation.tr("Calm")} ${Translation.tr("None")}`
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [
                        { "value": "full", "label": Translation.tr("Lively"), "hint": Translation.tr("Parts fly in one by one, the clock glides from the desktop, all fly apart on unlock") },
                        { "value": "calm", "label": Translation.tr("Calm"), "hint": Translation.tr("Everything fades in and out") },
                        { "value": "none", "label": Translation.tr("None"), "hint": Translation.tr("Shown and gone at once") }
                    ]
                    delegate: SchemeTile {
                        id: motionTile
                        required property var modelData
                        required property int index
                        label: modelData.label
                        frameWidth: 112
                        frameHeight: 70
                        selected: page.lock.animations === modelData.value
                        onClicked: Config.options.lock.animations = modelData.value
                        StyledToolTip {
                            text: motionTile.modelData.hint
                        }
                        // Three blocks: staggered for lively, faded for calm, plain for none
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                x: 22 + index * 26
                                y: motionTile.index === 0 ? 40 - index * 9 : 26
                                width: 18
                                height: 18
                                radius: 5
                                color: motionTile.ink
                                opacity: motionTile.index === 1 ? 0.35 + index * 0.3 : 1
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "password"
        title: Translation.tr("Password field")

        ContentSubsection {
            title: Translation.tr("Typed characters")
            searchText: `${title} ${Translation.tr("Shapes")} ${Translation.tr("Dots")}`
            Flow {
                Layout.fillWidth: true
                spacing: 4
                SchemeTile {
                    id: shapesTile
                    label: Translation.tr("Shapes")
                    frameWidth: 112
                    frameHeight: 70
                    selected: page.lock.materialShapeChars
                    onClicked: Config.options.lock.materialShapeChars = true
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialShape { implicitSize: 14; shape: MaterialShape.Shape.Cookie4Sided; color: shapesTile.ink }
                        MaterialShape { implicitSize: 14; shape: MaterialShape.Shape.Triangle; color: shapesTile.ink }
                        MaterialShape { implicitSize: 14; shape: MaterialShape.Shape.Clover4Leaf; color: shapesTile.ink }
                        MaterialShape { implicitSize: 14; shape: MaterialShape.Shape.Pentagon; color: shapesTile.ink }
                    }
                }
                SchemeTile {
                    id: dotsTile
                    label: Translation.tr("Dots")
                    frameWidth: 112
                    frameHeight: 70
                    selected: !page.lock.materialShapeChars
                    onClicked: Config.options.lock.materialShapeChars = false
                    Row {
                        anchors.centerIn: parent
                        spacing: 7
                        Repeater {
                            model: 4
                            Rectangle { width: 10; height: 10; radius: 5; color: dotsTile.ink }
                        }
                    }
                }
            }
        }
        ConfigSlider {
            buttonIcon: "backspace"
            text: Translation.tr("Clear a half-typed password after")
            usePercentTooltip: false
            from: 3
            to: 60
            value: page.lock.clearPasswordAfter
            valueText: Translation.tr("%1 s").arg(Math.round(value))
            onMoved: Config.options.lock.clearPasswordAfter = Math.round(value)
        }
    }

    ContentSection {
        icon: "shield_lock"
        title: Translation.tr("Security")

        ConfigSwitch {
            buttonIcon: "settings_power"
            text: Translation.tr('Require password to power off/restart')
            description: Translation.tr("Remember that on most devices one can always hold the power button to force shutdown. This only makes it a tiny bit harder for accidents to happen")
            autoToggle: false
            checked: page.lock.security.requirePasswordToPower
            onClicked: Config.options.lock.security.requirePasswordToPower = !page.lock.security.requirePasswordToPower
        }
        ConfigSwitch {
            buttonIcon: "key_vertical"
            text: Translation.tr('Also unlock keyring')
            description: Translation.tr("This is usually safe and needed for your browser and AI sidebar anyway. Mostly useful for those who use lock on startup instead of a display manager that does it (GDM, SDDM, etc.)")
            autoToggle: false
            checked: page.lock.security.unlockKeyring
            onClicked: Config.options.lock.security.unlockKeyring = !page.lock.security.unlockKeyring
        }
        ConfigSwitch {
            buttonIcon: "account_circle"
            text: Translation.tr('Launch on startup')
            description: Translation.tr("Lock the session right after logging in")
            autoToggle: false
            checked: page.lock.launchOnStartup
            onClicked: Config.options.lock.launchOnStartup = !page.lock.launchOnStartup
        }
        ConfigExpander {
            title: Translation.tr("Another lock screen")
            ConfigSwitch {
                buttonIcon: "water_drop"
                text: Translation.tr('Use Hyprlock (instead of Quickshell)')
                description: Translation.tr("If you want to somehow use fingerprint unlock...")
                autoToggle: false
                checked: page.lock.useHyprlock
                onClicked: Config.options.lock.useHyprlock = !page.lock.useHyprlock
            }
        }
    }
}
