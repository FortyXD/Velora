import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.bar
import qs.modules.ii.bar.weather
import qs.modules.ii.bar.widgets
import QtQuick

/**
 * Components for the bar widget types listed in BarWidgetCatalog.
 * Every widget gets `host` (its BarItemHost) once loaded: host.tier, host.vertical,
 * host.zoneHovered, host.options. A widget may expose `barVisible` (shown at all) and
 * `barFill` (takes free space), which the host uses for layout.
 */
QtObject {
    id: root

    function component(type) {
        return root.components[type] ?? null;
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

    readonly property var components: ({
        "leftSidebarButton": leftSidebarButton,
        "activeWindow": activeWindow,
        "workspaces": workspaces,
        "resources": resources,
        "battery": battery,
        "sysTray": sysTray,
        "privacy": privacy,
        "statusIndicators": statusIndicators,
        "island": island,
        "clock": clock,
        "weather": weather,
        "utilButtons": utilButtons,
        "spacer": spacer,
    })

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

    property Component privacy: Component {
        PrivacyIndicator {
            property var host: null
        }
    }

    property Component statusIndicators: Component {
        StatusIndicators {
            property var host: null
            zoneHovered: host?.zoneHovered ?? false
        }
    }

    property Component island: Component {
        BarIsland {
            property var host: null
        }
    }

    property Component clock: Component {
        ClockWidget {
            property var host: null
            showDate: Config.options.bar.verbose && (host?.tier ?? 0) < 2
        }
    }

    property Component weather: Component {
        WeatherBar {
            property var host: null
        }
    }

    property Component utilButtons: Component {
        UtilButtons {
            property var host: null
            readonly property bool barVisible: Config.options.bar.verbose
        }
    }

    property Component spacer: Component {
        Item {
            property var host: null
        }
    }
}
