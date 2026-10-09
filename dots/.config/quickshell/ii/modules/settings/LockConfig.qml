import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    ContentSection {
        icon: "lock"
        title: Translation.tr("Behavior")
        description: Translation.tr("Which locker is used and when it starts")

        ConfigSwitch {
            buttonIcon: "water_drop"
            text: Translation.tr('Use Hyprlock (instead of Quickshell)')
            description: Translation.tr("If you want to somehow use fingerprint unlock...")
            checked: Config.options.lock.useHyprlock
            onCheckedChanged: {
                Config.options.lock.useHyprlock = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "account_circle"
            text: Translation.tr('Launch on startup')
            description: Translation.tr("Lock the session right after logging in")
            checked: Config.options.lock.launchOnStartup
            onCheckedChanged: {
                Config.options.lock.launchOnStartup = checked;
            }
        }
    }

    ContentSection {
        icon: "shield_lock"
        title: Translation.tr("Security")

        ConfigSwitch {
            buttonIcon: "settings_power"
            text: Translation.tr('Require password to power off/restart')
            description: Translation.tr("Remember that on most devices one can always hold the power button to force shutdown. This only makes it a tiny bit harder for accidents to happen")
            checked: Config.options.lock.security.requirePasswordToPower
            onCheckedChanged: {
                Config.options.lock.security.requirePasswordToPower = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "key_vertical"
            text: Translation.tr('Also unlock keyring')
            description: Translation.tr("This is usually safe and needed for your browser and AI sidebar anyway. Mostly useful for those who use lock on startup instead of a display manager that does it (GDM, SDDM, etc.)")
            checked: Config.options.lock.security.unlockKeyring
            onCheckedChanged: {
                Config.options.lock.security.unlockKeyring = checked;
            }
        }
    }

    ContentSection {
        icon: "style"
        title: Translation.tr("Style")
        description: Translation.tr("Applies to the Quickshell lock screen")

        ConfigSwitch {
            buttonIcon: "center_focus_weak"
            text: Translation.tr('Center clock')
            checked: Config.options.lock.centerClock
            onCheckedChanged: {
                Config.options.lock.centerClock = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "info"
            text: Translation.tr('Show "Locked" text')
            checked: Config.options.lock.showLockedText
            onCheckedChanged: {
                Config.options.lock.showLockedText = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "shapes"
            text: Translation.tr('Use varying shapes for password characters')
            checked: Config.options.lock.materialShapeChars
            onCheckedChanged: {
                Config.options.lock.materialShapeChars = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Blur")
            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr('Enable blur')
                checked: Config.options.lock.blur.enable
                onCheckedChanged: {
                    Config.options.lock.blur.enable = checked;
                }
            }
            ConfigSpinBox {
                enabled: Config.options.lock.blur.enable
                icon: "loupe"
                text: Translation.tr("Extra wallpaper zoom (%)")
                value: Config.options.lock.blur.extraZoom * 100
                from: 1
                to: 150
                stepSize: 2
                onValueChanged: {
                    Config.options.lock.blur.extraZoom = value / 100;
                }
            }
        }
    }
}
