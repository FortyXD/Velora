import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview
import qs.modules.settings.power

SettingsDetailPage {
    id: rootPage
    sectionTitles: ({
        saving: Translation.tr("Effects and devices"),
        warnings: Translation.tr("Full charge and suspend"),
        analytics: Translation.tr("Power analytics")
    })

    // One thing energy saving turns off: a switch bound to Config.options.powerSaving[key]
    component CutRow: ConfigSwitch {
        property string key
        autoToggle: false
        checked: Config.options.powerSaving[key]
        onClicked: Config.options.powerSaving[key] = !checked
    }

    component ModePicker: GridLayout {
        Layout.fillWidth: true
        columns: 3
        uniformCellWidths: true
        columnSpacing: 4
        SchemeTile {
            Layout.fillWidth: true
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
            Layout.fillWidth: true
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
            Layout.fillWidth: true
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

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        SettingsBranch {
            id: overviewBranch
            key: "overview"
            page: rootPage

            BatteryStatusCard {}
            ContentSection {
                title: Translation.tr("Energy saving")
                ModePicker {}
                SettingsBranchLink {
                    branch: savingBranch
                    buttonIcon: "energy_savings_leaf"
                    detail: Translation.tr("Choose which effects and devices to turn off")
                }
            }
            ContentSection {
                title: Translation.tr("Charge warnings")
                PowerThresholds {}
                SettingsBranchLink {
                    branch: warningsBranch
                    buttonIcon: "bedtime"
                    detail: Config.options.battery.automaticSuspend ? Translation.tr("Suspend at %1%").arg(Config.options.battery.suspend) : Translation.tr("Automatic suspend is off")
                }
            }
            ContentSection {
                SettingsBranchLink {
                    branch: analyticsBranch
                    buttonIcon: "monitoring"
                    detail: Translation.tr("Battery power, voltage and charge history")
                    summary: PowerAnalytics.enabled ? Translation.tr("On") : Translation.tr("Off")
                }
            }
        }

        SettingsBranch {
            id: savingBranch
            key: "saving"
            page: rootPage

            ContentSection {
                icon: "motion_photos_paused"
                title: Translation.tr("Desktop effects")
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
            }
            ContentSection {
                icon: "devices"
                title: Translation.tr("Power and devices")
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

                ConfigNavRow {
                    buttonIcon: "toast"
                    title: Translation.tr("Energy saving button")
                    description: Translation.tr("Add it to the bar (Bar → widgets) or to the quick toggles in the right sidebar (edit mode)")
                    onClicked: ApplicationWindow.window?.openPage("bar")
                }
            }
        }

        SettingsBranch {
            id: warningsBranch
            key: "warnings"
            page: rootPage

            ContentSection {
                title: Translation.tr("Full charge notification")
                ConfigSwitch {
                    id: fullAlert
                    property int lastThreshold: 100
                    buttonIcon: "battery_charging_full"
                    text: Translation.tr("Notify when fully charged")
                    autoToggle: false
                    checked: Config.options.battery.full <= 100
                    onClicked: {
                        if (checked) {
                            lastThreshold = Config.options.battery.full;
                            Config.options.battery.full = 101;
                        } else Config.options.battery.full = lastThreshold;
                    }
                }
                ConfigSpinBox {
                    visible: fullAlert.checked
                    icon: "charger"
                    text: Translation.tr("Full warning (%)")
                    value: fullAlert.checked ? Config.options.battery.full : fullAlert.lastThreshold
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueChanged: if (fullAlert.checked) Config.options.battery.full = value
                }
            }

            ContentSection {
                title: Translation.tr("Suspend")

                ConfigSwitch {
                    buttonIcon: "bedtime"
                    text: Translation.tr("Automatic suspend")
                    autoToggle: false
                    checked: Config.options.battery.automaticSuspend
                    onClicked: Config.options.battery.automaticSuspend = !checked
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

        SettingsBranch {
            id: analyticsBranch
            key: "analytics"
            page: rootPage
            header: ContentSection {
                title: Translation.tr("Power analytics")
                icon: "monitoring"
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 14
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Record power history")
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colOnLayer2
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Sample every 2 seconds and keep up to 8 hours on this device. Turning this off stops sampling and deletes all recorded measurements.")
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                    AnalyticsSegments {
                        objectName: "analyticsRecording"
                        readonly property bool settingsSearchable: true
                        readonly property string title: Translation.tr("Advanced power analytics")
                        readonly property string searchText: title + " " + Translation.tr("Record power history")
                        Layout.preferredWidth: 124
                        options: [{label: Translation.tr("Off"), value: false}, {label: Translation.tr("On"), value: true}]
                        currentValue: Config.options.battery.advancedAnalytics
                        onSelected: value => Config.options.battery.advancedAnalytics = value
                    }
                }
            }

            PowerAnalyticsPanel {
                pageActive: rootPage.pageShown && analyticsBranch.shown
            }
        }
    }
}
