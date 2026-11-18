pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Processor, memory and swap with their recent history, network speed, battery and updates
 * (options: graphs, network, battery, updates, details). Extras are opt-in.
 * Network speed is only measured while it's in sight.
 */
Rectangle {
    id: root
    property Item host: null
    readonly property var options: root.host?.options ?? {}
    readonly property bool live: root.host?.active ?? false

    readonly property bool showNetwork: root.options.network ?? false
    readonly property bool showBattery: (root.options.battery ?? false) && Battery.available
    readonly property bool showUpdates: (root.options.updates ?? false) && Updates.available && Updates.count > 0
    readonly property bool showDetails: root.options.details ?? false
    readonly property bool measuresNetwork: root.live && root.showNetwork
    property bool networkRegistered: false
    function updateNetworkSubscription() {
        if (root.networkRegistered === root.measuresNetwork) return;
        NetworkSpeed.users += root.measuresNetwork ? 1 : -1;
        root.networkRegistered = root.measuresNetwork;
    }
    onMeasuresNetworkChanged: root.updateNetworkSubscription()
    Component.onCompleted: root.updateNetworkSubscription()
    Component.onDestruction: if (root.networkRegistered) NetworkSpeed.users -= 1

    implicitHeight: column.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Resource {
                icon: "memory"
                name: Translation.tr("CPU")
                value: ResourceUsage.cpuUsage
                history: ResourceUsage.cpuUsageHistory
            }
            Resource {
                icon: "memory_alt"
                name: Translation.tr("RAM")
                value: ResourceUsage.memoryUsedPercentage
                history: ResourceUsage.memoryUsageHistory
                detail: Translation.tr("of %1").arg(ResourceUsage.maxAvailableMemoryString)
            }
            Resource {
                visible: ResourceUsage.swapTotal > 1
                icon: "swap_horiz"
                name: Translation.tr("Swap")
                value: ResourceUsage.swapUsedPercentage
                history: ResourceUsage.swapUsageHistory
                detail: Translation.tr("of %1").arg(ResourceUsage.maxAvailableSwapString)
            }
        }

        Flow {
            objectName: "systemExtras"
            visible: root.showNetwork || root.showBattery || root.showUpdates || root.showDetails
            Layout.fillWidth: true
            spacing: 6

            InfoChip {
                visible: root.showNetwork
                symbol: "arrow_downward"
                text: NetworkSpeed.format(NetworkSpeed.downloadRate)
            }
            InfoChip {
                visible: root.showNetwork
                symbol: "arrow_upward"
                text: NetworkSpeed.format(NetworkSpeed.uploadRate)
            }
            InfoChip {
                visible: root.showBattery
                symbol: Battery.isCharging ? "battery_charging_full" : Battery.isLow ? "battery_alert" : "battery_full"
                text: {
                    const percent = `${Math.round(Battery.percentage * 100)}%`;
                    if (Battery.isCharging || Battery.timeToEmpty <= 0) return percent;
                    const minutes = Math.round(Battery.timeToEmpty / 60);
                    return `${percent} · ${Translation.tr("%1 h %2 min left").arg(Math.floor(minutes / 60)).arg(minutes % 60)}`;
                }
            }
            InfoChip {
                visible: root.showUpdates
                symbol: "system_update"
                text: Translation.tr("%1 updates").arg(Updates.count)
                emphasized: Updates.updateAdvised
                onClicked: {
                    GlobalStates.closeSidebars();
                    Quickshell.execDetached(["bash", "-c", Config.options.apps.update]);
                }
            }
            InfoChip {
                visible: root.showDetails
                symbol: "monitoring"
                text: Translation.tr("Details")
                onClicked: {
                    GlobalStates.closeSidebars();
                    Quickshell.execDetached(["bash", "-c", Config.options.apps.taskManager]);
                }
            }
        }
    }

    // A use in percent over its recent history
    component Resource: Rectangle {
        id: resource
        property string icon
        property string name
        property real value: 0
        property list<real> history: []
        property string detail: ""
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        implicitHeight: resourceColumn.implicitHeight + 12
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: resourceColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 6
            }
            spacing: 2
            RowLayout {
                spacing: 4
                MaterialSymbol {
                    text: resource.icon
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: resource.name
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: `${Math.round(resource.value * 100)}%`
                    font {
                        family: Appearance.font.family.numbers
                        variableAxes: Appearance.font.variableAxes.numbers
                        pixelSize: Appearance.font.pixelSize.normal
                    }
                    color: Appearance.colors.colOnLayer2
                }
            }
            Rectangle {
                id: graphBackground
                visible: root.options.graphs ?? true
                Layout.fillWidth: true
                implicitHeight: 34
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colSecondaryContainer
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: graphBackground.width
                        height: graphBackground.height
                        radius: graphBackground.radius
                    }
                }
                Graph {
                    anchors.fill: parent
                    values: resource.history
                    points: ResourceUsage.historyLength
                    alignment: Graph.Alignment.Right
                }
            }
            StyledText {
                visible: resource.detail.length > 0
                text: resource.detail
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    component InfoChip: RippleButton {
        id: chip
        property string symbol
        property bool emphasized: false
        implicitHeight: 30
        leftPadding: 10
        rightPadding: 12
        buttonRadius: Appearance.rounding.full
        colBackground: chip.emphasized ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
        colBackgroundHover: chip.emphasized ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
        contentItem: Row {
            spacing: 5
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.symbol
                iconSize: 16
                color: chip.emphasized ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.text
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: chip.emphasized ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
            }
        }
    }
}
