import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
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
