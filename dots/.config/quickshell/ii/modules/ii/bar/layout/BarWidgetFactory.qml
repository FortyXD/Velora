import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar
import qs.modules.ii.bar.weather
import qs.modules.ii.bar.widgets
import qs.modules.ii.verticalBar as VBar
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Components for the bar widget types listed in BarWidgetCatalog.
 * Every widget gets `host` (its BarItemHost) once loaded: host.type, host.tier, host.vertical,
 * host.zoneHovered, host.inPill, host.options. A widget may expose `barVisible` (shown at all)
 * and `barFill` (takes free space), which the host uses for layout.
 */
QtObject {
    id: root

    function component(type, vertical = false) {
        if (BarWidgetCatalog.get(type)?.utilButton) return root.utilButton;
        if (vertical && root.verticalComponents[type]) return root.verticalComponents[type];
        return root.components[type] ?? null;
    }

    // Variants drawn differently on a vertical bar
    readonly property var verticalComponents: ({
        "resources": verticalResources,
        "battery": verticalBattery,
        "clock": verticalClock,
        "media": verticalMedia,
        "statusIndicators": verticalStatusIndicators,
    })

    property Component verticalResources: Component {
        VBar.Resources {
            property var host: null
        }
    }

    property Component verticalBattery: Component {
        VBar.BatteryIndicator {
            property var host: null
            readonly property bool barVisible: Battery.available
        }
    }

    property Component verticalClock: Component {
        VBar.VerticalClockWidget {
            property var host: null
        }
    }

    property Component verticalMedia: Component {
        VBar.VerticalMedia {
            property var host: null
        }
    }

    property Component verticalStatusIndicators: Component {
        VerticalStatusIndicators {
            property var host: null
            zoneHovered: host?.zoneHovered ?? false
            options: host?.options ?? ({})
        }
    }

    // Whether a widget should be created at all, before its component is loaded
    function gate(type) {
        switch (type) {
        case "weather":
            return Config.options.bar.weather.enable;
        default:
            return true;
        }
    }

    function textColor(host) {
        return host?.inPill ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer0;
    }

    readonly property var components: ({
        "leftSidebarButton": leftSidebarButton,
        "activeWindow": activeWindow,
        "workspaces": workspaces,
        "resources": resources,
        "battery": battery,
        "sysTray": sysTray,
        "privacy": privacy,
        "statusIndicators": statusIndicators,
        "network": network,
        "bluetooth": bluetooth,
        "keyboardLayout": keyboardLayout,
        "notifications": notifications,
        "audioMuted": audioMuted,
        "micMuted": micMuted,
        "island": island,
        "media": media,
        "clock": clock,
        "weather": weather,
        "utilButtons": utilButtons,
        "launcher": launcher,
        "session": session,
        "settingsButton": settingsButton,
        "wallpaperButton": wallpaperButton,
        "appButton": appButton,
        "spacer": spacer,
        "fixedSpace": fixedSpace,
        "separator": separator,
        "text": text,
        "customCommand": customCommand,
        "networkSpeed": networkSpeed,
        "updates": updates,
        "randomWallpaper": randomWallpaper,
    })

    property Component customCommand: Component {
        CustomCommandWidget {}
    }

    property Component networkSpeed: Component {
        NetworkSpeedWidget {}
    }

    property Component updates: Component {
        UpdatesWidget {}
    }

    property Component randomWallpaper: Component {
        CircleUtilButton {
            property var host: null
            iconName: "shuffle"
            tooltipText: Translation.tr("Random wallpaper")
            onClicked: Wallpapers.randomFromCurrentFolder()
        }
    }

    // System

    property Component leftSidebarButton: Component {
        LeftSidebarButton {
            property var host: null
            colBackground: host?.zoneHovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        }
    }

    property Component activeWindow: Component {
        ActiveWindow {
            property var host: null
        }
    }

    property Component workspaces: Component {
        Workspaces {
            property var host: null
            vertical: host?.vertical ?? false
        }
    }

    property Component resources: Component {
        Resources {
            property var host: null
            readonly property bool barFill: host?.tier === 2
            alwaysShowAllResources: host?.tier === 2
        }
    }

    property Component battery: Component {
        BatteryIndicator {
            property var host: null
            readonly property bool barVisible: Battery.available
        }
    }

    property Component sysTray: Component {
        SysTray {
            property var host: null
            vertical: host?.vertical ?? false
            invertSide: Config.options.bar.bottom
        }
    }

    // Indicators

    property Component privacy: Component {
        PrivacyIndicator {
            property var host: null
        }
    }

    property Component statusIndicators: Component {
        StatusIndicators {
            property var host: null
            zoneHovered: host?.zoneHovered ?? false
            options: host?.options ?? ({})
        }
    }

    property Component network: Component {
        IndicatorWidget {
            id: networkWidget
            NetworkIndicator {
                color: root.textColor(networkWidget.host)
            }
        }
    }

    property Component bluetooth: Component {
        IndicatorWidget {
            id: bluetoothWidget
            active: bluetoothIcon.active
            Row {
                spacing: 0
                BluetoothIndicator {
                    id: bluetoothIcon
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.textColor(bluetoothWidget.host)
                }
                BluetoothBatteryIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: active
                    normalColor: root.textColor(bluetoothWidget.host)
                }
            }
        }
    }

    property Component keyboardLayout: Component {
        IndicatorWidget {
            id: keyboardWidget
            active: xkbIndicator.active
            HyprlandXkbIndicator {
                id: xkbIndicator
                vertical: keyboardWidget.host?.vertical ?? false
                color: root.textColor(keyboardWidget.host)
            }
        }
    }

    property Component notifications: Component {
        IndicatorWidget {
            id: notificationsWidget
            active: (host?.options?.alwaysShow ?? false) || Notifications.silent || Notifications.unread > 0
            NotificationUnreadCount {
                color: root.textColor(notificationsWidget.host)
            }
        }
    }

    property Component audioMuted: Component {
        IndicatorWidget {
            id: audioMutedWidget
            active: audioMutedIcon.active
            clickable: true
            tooltipText: Translation.tr("Unmute sound")
            onActivated: Audio.toggleMute()
            AudioMutedIndicator {
                id: audioMutedIcon
                color: root.textColor(audioMutedWidget.host)
            }
        }
    }

    property Component micMuted: Component {
        IndicatorWidget {
            id: micMutedWidget
            active: micMutedIcon.active
            clickable: true
            tooltipText: Translation.tr("Unmute microphone")
            onActivated: Audio.toggleMicMute()
            MicMutedIndicator {
                id: micMutedIcon
                color: root.textColor(micMutedWidget.host)
            }
        }
    }

    // Media and time

    property Component island: Component {
        BarIsland {
            property var host: null
        }
    }

    property Component media: Component {
        Media {
            property var host: null
        }
    }

    property Component clock: Component {
        ClockWidget {
            property var host: null
            showDate: Config.options.bar.verbose && (host?.tier ?? 0) < 2 && (host?.options?.showDate ?? true)
        }
    }

    property Component weather: Component {
        WeatherBar {
            property var host: null
        }
    }

    // Buttons

    property Component utilButtons: Component {
        UtilButtons {
            property var host: null
            readonly property bool barVisible: Config.options.bar.verbose
        }
    }

    property Component utilButton: Component {
        UtilButton {
            property var host: null
            kind: host?.type ?? ""
        }
    }

    property Component launcher: Component {
        CircleUtilButton {
            property var host: null
            iconName: "search"
            tooltipText: Translation.tr("Search")
            toggled: GlobalStates.overviewOpen
            onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
        }
    }

    property Component session: Component {
        CircleUtilButton {
            property var host: null
            iconName: "power_settings_new"
            tooltipText: Translation.tr("Session")
            onClicked: GlobalStates.sessionOpen = !GlobalStates.sessionOpen
        }
    }

    property Component settingsButton: Component {
        CircleUtilButton {
            property var host: null
            iconName: "settings"
            tooltipText: Translation.tr("Settings")
            onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")])
        }
    }

    property Component wallpaperButton: Component {
        CircleUtilButton {
            property var host: null
            iconName: "wallpaper"
            tooltipText: Translation.tr("Wallpapers")
            toggled: GlobalStates.wallpaperSelectorOpen
            onClicked: GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
        }
    }

    property Component appButton: Component {
        CircleUtilButton {
            property var host: null
            readonly property string command: host?.options?.command ?? ""
            iconName: host?.options?.icon || "terminal"
            tooltipText: host?.options?.tooltip || command
            onClicked: if (command.trim().length > 0) Quickshell.execDetached(["bash", "-c", command])
        }
    }

    // Building blocks

    property Component spacer: Component {
        Item {
            property var host: null
        }
    }

    property Component fixedSpace: Component {
        Item {
            property var host: null
            readonly property real size: host?.options?.size ?? 16
            implicitWidth: host?.vertical ? 1 : size
            implicitHeight: host?.vertical ? size : 1
        }
    }

    property Component separator: Component {
        Item {
            property var host: null
            implicitWidth: host?.vertical ? Appearance.sizes.baseVerticalBarWidth / 3 : 1
            implicitHeight: host?.vertical ? 1 : Appearance.sizes.baseBarHeight / 3
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colOutlineVariant
            }
        }
    }

    property Component text: Component {
        Item {
            id: textWidget
            property var host: null
            implicitWidth: textRow.implicitWidth
            implicitHeight: Appearance.sizes.baseBarHeight
            RowLayout {
                id: textRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    visible: text.length > 0
                    text: textWidget.host?.options?.icon ?? ""
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.textColor(textWidget.host)
                }
                StyledText {
                    text: textWidget.host?.options?.text ?? Translation.tr("Hello")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.textColor(textWidget.host)
                }
            }
        }
    }
}
