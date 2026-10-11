import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property var buttons: Config.options.bar.utilButtons
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: rowLayout.implicitHeight

    component UtilButtonLoader: Loader {
        required property bool shown
        active: shown
        visible: shown
        Layout.alignment: Qt.AlignVCenter
    }

    RowLayout {
        id: rowLayout

        spacing: 4
        anchors.centerIn: parent

        UtilButtonLoader {
            shown: root.buttons.showScreenSnip
            sourceComponent: CircleUtilButton {
                iconName: "screenshot_region"
                iconFill: 1
                tooltipText: Translation.tr("Screen snip")
                onClicked: Hyprland.dispatch(`hl.dsp.global("quickshell:regionScreenshot")`)
            }
        }

        UtilButtonLoader {
            shown: root.buttons.showScreenRecord
            sourceComponent: CircleUtilButton {
                toggled: ScreenRecorder.recording
                urgent: true
                iconName: ScreenRecorder.recording ? "stop_circle" : "videocam"
                iconFill: 1
                tooltipText: ScreenRecorder.recording ? Translation.tr("Stop recording") : Translation.tr("Record screen")
                onClicked: ScreenRecorder.toggle()
            }
        }

        UtilButtonLoader {
            shown: root.buttons.showColorPicker
            sourceComponent: CircleUtilButton {
                iconName: "colorize"
                iconFill: 1
                tooltipText: Translation.tr("Color picker")
                onClicked: Quickshell.execDetached(["hyprpicker", "-a"])
            }
        }

        UtilButtonLoader {
            shown: root.buttons.showKeyboardToggle
            sourceComponent: CircleUtilButton {
                toggled: GlobalStates.oskOpen
                iconName: GlobalStates.oskOpen ? "keyboard_hide" : "keyboard"
                iconFill: 0
                tooltipText: Translation.tr("On-screen keyboard")
                onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
            }
        }

        UtilButtonLoader {
            shown: root.buttons.showMicToggle
            sourceComponent: CircleUtilButton {
                readonly property bool muted: Audio.source?.audio?.muted ?? false
                toggled: muted
                urgent: true
                iconName: muted ? "mic_off" : "mic"
                tooltipText: muted ? Translation.tr("Unmute microphone") : Translation.tr("Mute microphone")
                onClicked: Audio.toggleMicMute()
            }
        }

        UtilButtonLoader {
            shown: root.buttons.showIdleInhibitor
            sourceComponent: CircleUtilButton {
                toggled: Idle.inhibit
                iconName: "coffee"
                tooltipText: Idle.inhibit ? Translation.tr("Keeping the system awake") : Translation.tr("Keep system awake")
                onClicked: Idle.toggleInhibit()
            }
        }

        UtilButtonLoader {
            shown: root.buttons.showNightLight
            sourceComponent: CircleUtilButton {
                toggled: Hyprsunset.temperatureActive
                iconName: Config.options.light.night.automatic ? "night_sight_auto" : "bedtime"
                tooltipText: Translation.tr("Night Light")
                onClicked: Hyprsunset.toggleTemperature()
                Component.onCompleted: Hyprsunset.fetchState()
            }
        }

        UtilButtonLoader {
            shown: root.buttons.showDoNotDisturb
            sourceComponent: CircleUtilButton {
                toggled: Notifications.silent
                iconName: Notifications.silent ? "notifications_paused" : "notifications"
                tooltipText: Notifications.silent ? Translation.tr("Do not disturb is on") : Translation.tr("Do not disturb")
                onClicked: Notifications.silent = !Notifications.silent
            }
        }

        UtilButtonLoader {
            shown: root.buttons.showDarkModeToggle
            sourceComponent: CircleUtilButton {
                iconName: Appearance.m3colors.darkmode ? "light_mode" : "dark_mode"
                tooltipText: Appearance.m3colors.darkmode ? Translation.tr("Switch to light mode") : Translation.tr("Switch to dark mode")
                onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", Appearance.m3colors.darkmode ? "light" : "dark", "--noswitch"])
            }
        }

        UtilButtonLoader {
            shown: root.buttons.showPerformanceProfileToggle
            sourceComponent: CircleUtilButton {
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

        UtilButtonLoader {
            id: supergfxctlToggleLoader
            shown: root.buttons.showSupergfxctlToggle
            sourceComponent: CircleUtilButton {
                property bool containsMouse: hovered
                colBackground: "transparent"
                colBackgroundHover: "transparent"
                iconName: Supergfxctl.icon
                iconColor: Supergfxctl.lastError.length > 0 ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                onClicked: Supergfxctl.toggle()
            }
        }
    }

    StyledPopup {
        hoverTarget: supergfxctlToggleLoader.item ?? null

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
