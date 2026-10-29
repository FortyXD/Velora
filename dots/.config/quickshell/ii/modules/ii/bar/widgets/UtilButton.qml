import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower

/**
 * One of the small round bar buttons, chosen by `kind` (see BarWidgetCatalog.utilButtonKinds).
 */
Loader {
    id: root

    property string kind

    Layout.alignment: Qt.AlignVCenter
    sourceComponent: {
        switch (root.kind) {
        case "screenSnip": return screenSnip;
        case "screenRecord": return screenRecord;
        case "colorPicker": return colorPicker;
        case "keyboardToggle": return keyboardToggle;
        case "micToggle": return micToggle;
        case "idleInhibitor": return idleInhibitor;
        case "nightLight": return nightLight;
        case "doNotDisturb": return doNotDisturb;
        case "darkMode": return darkMode;
        case "performanceProfile": return performanceProfile;
        case "powerSaving": return powerSaving;
        case "gpuMode": return gpuMode;
        default: return null;
        }
    }

    property Component screenSnip: Component {
        CircleUtilButton {
            iconName: "screenshot_region"
            iconFill: 1
            tooltipText: Translation.tr("Screen snip")
            onClicked: Hyprland.dispatch(`hl.dsp.global("quickshell:regionScreenshot")`)
        }
    }

    property Component screenRecord: Component {
        CircleUtilButton {
            toggled: ScreenRecorder.active
            urgent: true
            iconName: ScreenRecorder.active ? "stop_circle" : "videocam"
            iconFill: 1
            tooltipText: ScreenRecorder.tooltip
            onClicked: ScreenRecorder.toggle()
        }
    }

    property Component colorPicker: Component {
        CircleUtilButton {
            iconName: "colorize"
            iconFill: 1
            tooltipText: Translation.tr("Color picker")
            onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/colors/pick-color.sh")]) // Remembers the color for the toolbox
        }
    }

    property Component keyboardToggle: Component {
        CircleUtilButton {
            toggled: GlobalStates.oskOpen
            iconName: GlobalStates.oskOpen ? "keyboard_hide" : "keyboard"
            iconFill: 0
            tooltipText: Translation.tr("On-screen keyboard")
            onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
        }
    }

    property Component micToggle: Component {
        CircleUtilButton {
            readonly property bool muted: Audio.source?.audio?.muted ?? false
            toggled: muted
            urgent: true
            iconName: muted ? "mic_off" : "mic"
            tooltipText: muted ? Translation.tr("Unmute microphone") : Translation.tr("Mute microphone")
            onClicked: Audio.toggleMicMute()
        }
    }

    property Component idleInhibitor: Component {
        CircleUtilButton {
            toggled: Idle.inhibit
            iconName: "coffee"
            tooltipText: Idle.inhibit ? Translation.tr("Keeping the system awake") : Translation.tr("Keep system awake")
            onClicked: Idle.toggleInhibit()
        }
    }

    property Component nightLight: Component {
        CircleUtilButton {
            toggled: Hyprsunset.temperatureActive
            iconName: Config.options.light.night.automatic ? "night_sight_auto" : "bedtime"
            tooltipText: Translation.tr("Night Light")
            onClicked: Hyprsunset.toggleTemperature()
            Component.onCompleted: Hyprsunset.fetchState()
        }
    }

    property Component doNotDisturb: Component {
        CircleUtilButton {
            toggled: Notifications.silent
            iconName: Notifications.silent ? "notifications_paused" : "notifications"
            tooltipText: Notifications.silent ? Translation.tr("Do not disturb is on") : Translation.tr("Do not disturb")
            onClicked: Notifications.silent = !Notifications.silent
        }
    }

    property Component darkMode: Component {
        CircleUtilButton {
            iconName: Appearance.m3colors.darkmode ? "light_mode" : "dark_mode"
            tooltipText: Appearance.m3colors.darkmode ? Translation.tr("Switch to light mode") : Translation.tr("Switch to dark mode")
            onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", Appearance.m3colors.darkmode ? "light" : "dark", "--noswitch"])
        }
    }

    property Component performanceProfile: Component {
        CircleUtilButton {
            toggled: PowerProfiles.profile !== PowerProfile.Balanced
            iconName: switch (PowerProfiles.profile) {
                case PowerProfile.PowerSaver: return "energy_savings_leaf";
                case PowerProfile.Performance: return "local_fire_department";
                default: return "airwave";
            }
            iconFill: 0
            tooltipText: Translation.tr("Click to cycle through power profiles")
            onClicked: {
                if (PowerProfiles.hasPerformanceProfile) {
                    switch (PowerProfiles.profile) {
                        case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced; break;
                        case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance; break;
                        case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver; break;
                    }
                } else {
                    PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced;
                }
            }
        }
    }

    property Component powerSaving: Component {
        CircleUtilButton {
            toggled: PowerSaving.active
            iconName: "energy_savings_leaf"
            tooltipText: Translation.tr("Energy saving: %1 | Right-click for settings").arg(PowerSaving.statusText)
            onClicked: PowerSaving.toggle()
            altAction: () => PowerSaving.openSettings()
        }
    }

    property Component gpuMode: Component {
        CircleUtilButton {
            id: gpuButton
            property bool containsMouse: hovered
            iconName: Supergfxctl.icon
            iconColor: Supergfxctl.lastError.length > 0 ? Appearance.colors.colError : Appearance.colors.colOnLayer2
            onClicked: Supergfxctl.toggle()

            StyledPopup {
                hoverTarget: gpuButton

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    StyledPopupValueRow {
                        icon: Supergfxctl.icon
                        label: "GPU:"
                        value: Supergfxctl.statusText
                    }
                }
            }
        }
    }
}
