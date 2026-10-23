import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview

ContentPage {
    id: page

    // One thing energy saving turns off: a switch bound to Config.options.powerSaving[key]
    component CutRow: ConfigSwitch {
        property string key
        autoToggle: false
        checked: Config.options.powerSaving[key]
        onClicked: Config.options.powerSaving[key] = !checked
    }

    ContentSection {
        icon: "energy_savings_leaf"
        title: Translation.tr("Energy saving")
        description: Translation.tr("Turns off what costs the most battery: animations, blur, the live wallpaper and more. The rest of the system works as usual.")

        Rectangle { // Live status
            Layout.fillWidth: true
            implicitHeight: statusRow.implicitHeight + 28
            radius: Appearance.rounding.normal
            color: PowerSaving.active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RowLayout {
                id: statusRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 16
                    rightMargin: 16
                }
                spacing: 14

                Rectangle {
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: 24
                    color: PowerSaving.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "energy_savings_leaf"
                        iconSize: 28
                        fill: PowerSaving.active ? 1 : 0
                        color: PowerSaving.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: PowerSaving.active ? Translation.tr("Energy saving is on") : Translation.tr("Energy saving is off")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.variableAxes: ({ "wght": 600 })
                        color: PowerSaving.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: {
                            const power = !Battery.available ? Translation.tr("No battery")
                                : PowerSaving.onBattery ? Translation.tr("On battery, %1%").arg(Math.round(Battery.percentage * 100))
                                : Translation.tr("Plugged in, %1%").arg(Math.round(Battery.percentage * 100));
                            if (PowerSaving.mode === "off" && PowerSaving.override === "") return power;
                            return `${PowerSaving.statusText} · ${power}`;
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                RippleButton { // Same as the quick toggle
                    implicitHeight: 36
                    leftPadding: 16
                    rightPadding: 16
                    buttonRadius: Appearance.rounding.full
                    colBackground: PowerSaving.active ? Appearance.colors.colLayer1 : Appearance.colors.colPrimary
                    colBackgroundHover: PowerSaving.active ? Appearance.colors.colLayer1Hover : Appearance.colors.colPrimaryHover
                    onClicked: PowerSaving.toggle()
                    contentItem: StyledText {
                        text: PowerSaving.active ? Translation.tr("Turn off") : Translation.tr("Turn on")
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: PowerSaving.active ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnPrimary
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("When it's on")
            searchText: `${title} ${Translation.tr("Off")} ${Translation.tr("On battery")} ${Translation.tr("Always")}`
            Flow {
                Layout.fillWidth: true
                spacing: 4
                SchemeTile {
                    id: offTile
                    label: Translation.tr("Off")
                    frameWidth: 112
                    frameHeight: 70
                    selected: PowerSaving.mode === "off"
                    onClicked: PowerSaving.setMode("off")
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "electric_bolt"
                        iconSize: 30
                        color: offTile.ink
                    }
                }
                SchemeTile {
                    id: batteryTile
                    label: Translation.tr("On battery")
                    frameWidth: 112
                    frameHeight: 70
                    selected: PowerSaving.mode === "battery"
                    onClicked: PowerSaving.setMode("battery")
                    Row {
                        anchors.centerIn: parent
                        spacing: 2
                        MaterialSymbol { text: "battery_android_3"; iconSize: 26; color: batteryTile.ink; anchors.verticalCenter: parent.verticalCenter }
                        MaterialSymbol { text: "arrow_forward"; iconSize: 16; color: batteryTile.faint; anchors.verticalCenter: parent.verticalCenter }
                        MaterialSymbol { text: "energy_savings_leaf"; iconSize: 26; color: batteryTile.ink; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                SchemeTile {
                    id: alwaysTile
                    label: Translation.tr("Always")
                    frameWidth: 112
                    frameHeight: 70
                    selected: PowerSaving.mode === "on"
                    onClicked: PowerSaving.setMode("on")
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "energy_savings_leaf"
                        iconSize: 32
                        fill: 1
                        color: alwaysTile.ink
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("“On battery” turns it on by itself when you unplug the charger and off when you plug it back in. The button in the bar or the sidebar overrides it until the next plug or unplug.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        ContentSubsection {
            title: Translation.tr("What it turns off")
            CutRow {
                key: "animations"
                buttonIcon: "animation"
                text: Translation.tr("Animations")
                description: Translation.tr("Windows, panels and menus appear at once")
            }
            CutRow {
                key: "blur"
                buttonIcon: "blur_on"
                text: Translation.tr("Blur and shadows")
                description: Translation.tr("Flat panels and windows: much less work for the graphics chip")
            }
            CutRow {
                key: "liveWallpaper"
                buttonIcon: "motion_photos_paused"
                text: Translation.tr("Live wallpaper")
                description: Translation.tr("A video wallpaper stops on its current frame")
            }
            CutRow {
                key: "visualizer"
                buttonIcon: "graphic_eq"
                text: Translation.tr("Music visualizer")
                description: Translation.tr("The bars that move with the music")
            }
            CutRow {
                key: "livePreviews"
                buttonIcon: "preview"
                text: Translation.tr("Live window previews")
                description: Translation.tr("The dock and workspace previews show still pictures")
            }
            CutRow {
                key: "polling"
                buttonIcon: "timer"
                text: Translation.tr("Fewer background updates")
                description: Translation.tr("System stats refresh three times less often, clocks drop the seconds")
            }
            CutRow {
                key: "cpuProfile"
                buttonIcon: "speed"
                text: Translation.tr("Processor power saver")
                description: Translation.tr("The processor runs cooler and slower; the previous profile comes back afterwards")
            }
            CutRow {
                key: "brightness"
                buttonIcon: "brightness_medium"
                text: Translation.tr("Screen brightness")
                description: Translation.tr("A brighter screen dims to the limit below; the old brightness comes back afterwards")
            }
            ConfigSpinBox {
                icon: "brightness_low"
                text: Translation.tr("Brightness limit (%)")
                enabled: Config.options.powerSaving.brightness
                value: Config.options.powerSaving.brightnessLimit
                from: 5
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.powerSaving.brightnessLimit = value;
                }
            }
            CutRow {
                key: "keyboardLight"
                buttonIcon: "keyboard"
                text: Translation.tr("Keyboard backlight")
                description: Translation.tr("Turns off; the old level comes back afterwards")
            }
            CutRow {
                key: "bluetooth"
                buttonIcon: "bluetooth_disabled"
                text: Translation.tr("Bluetooth")
                description: Translation.tr("Turns off when nothing is connected, and back on afterwards")
            }
        }

        ConfigNavRow {
            buttonIcon: "toast"
            title: Translation.tr("Energy saving button")
            description: Translation.tr("Add it to the bar (Bar → widgets) or to the quick toggles in the right sidebar (edit mode)")
            onClicked: ApplicationWindow.window?.openPage("bar")
        }
    }

    ContentSection {
        title: Translation.tr("Status")
        visible: Battery.available

        ConfigNavRow {
            buttonIcon: Battery.isCharging ? "battery_charging_full" : "battery_android_full"
            title: Translation.tr("Charge")
            valueText: `${Math.round(Battery.percentage * 100)}%`
            trailingIcon: ""
            rippleEnabled: false
            pointingHandCursor: false
            colBackgroundHover: "transparent"
        }
    }

    ContentSection {
        title: Translation.tr("Warnings")
        description: Translation.tr("A notification is shown when the charge reaches these levels. Set the full warning to 101 to turn it off.")

        ConfigSpinBox {
            icon: "warning"
            text: Translation.tr("Low warning (%)")
            value: Config.options.battery.low
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.battery.low = value;
            }
        }
        ConfigSpinBox {
            icon: "dangerous"
            text: Translation.tr("Critical warning (%)")
            value: Config.options.battery.critical
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.battery.critical = value;
            }
        }
        ConfigSpinBox {
            icon: "charger"
            text: Translation.tr("Full warning (%)")
            value: Config.options.battery.full
            from: 0
            to: 101
            stepSize: 5
            onValueChanged: {
                Config.options.battery.full = value;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Suspend")
        description: Translation.tr("Automatically suspends the system when battery is low")

        ConfigSwitch {
            buttonIcon: "bedtime"
            text: Translation.tr("Automatic suspend")
            checked: Config.options.battery.automaticSuspend
            onCheckedChanged: {
                Config.options.battery.automaticSuspend = checked;
            }
        }
        ConfigSpinBox {
            enabled: Config.options.battery.automaticSuspend
            icon: "battery_alert"
            text: Translation.tr("Suspend at (%)")
            value: Config.options.battery.suspend
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.battery.suspend = value;
            }
        }
    }
}
