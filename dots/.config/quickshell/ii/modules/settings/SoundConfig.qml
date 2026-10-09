import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    ContentSection {
        title: Translation.tr("Volume protection")
        description: Translation.tr("Prevents abrupt increments and restricts volume limit")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Earbang protection")
            autoToggle: false
            checked: Config.options.audio.protection.enable
            onClicked: Config.options.audio.protection.enable = !Config.options.audio.protection.enable
        }
        ConfigSpinBox {
            enabled: Config.options.audio.protection.enable
            icon: "arrow_warm_up"
            text: Translation.tr("Max allowed increase (%)")
            value: Config.options.audio.protection.maxAllowedIncrease
            from: 0
            to: 100
            stepSize: 2
            onValueChanged: {
                Config.options.audio.protection.maxAllowedIncrease = value;
            }
        }
        ConfigSpinBox {
            enabled: Config.options.audio.protection.enable
            icon: "vertical_align_top"
            text: Translation.tr("Volume limit (%)")
            value: Config.options.audio.protection.maxAllowed
            from: 0
            to: 154 // pavucontrol allows up to 153%
            stepSize: 2
            onValueChanged: {
                Config.options.audio.protection.maxAllowed = value;
            }
        }
    }

    ContentSection {
        title: Translation.tr("System sounds")

        ConfigSwitch {
            buttonIcon: "battery_android_full"
            text: Translation.tr("Battery")
            description: Translation.tr("When the battery is low or full")
            checked: Config.options.sounds.battery
            onCheckedChanged: {
                Config.options.sounds.battery = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "av_timer"
            text: Translation.tr("Pomodoro")
            description: Translation.tr("When a focus or break period ends")
            autoToggle: false
            checked: Config.options.sounds.pomodoro
            onClicked: Config.options.sounds.pomodoro = !Config.options.sounds.pomodoro
        }
    }
}
