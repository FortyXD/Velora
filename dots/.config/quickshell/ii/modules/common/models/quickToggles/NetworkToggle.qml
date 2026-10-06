import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Internet")
    statusText: Network.ethernet ? Translation.tr("Ethernet connected") : Network.wifiConnecting ? Translation.tr("Connecting…") : Network.networkName || (Network.wifiEnabled ? Translation.tr("Not connected") : Translation.tr("Disabled"))
    busy: Network.wifiConnecting && !Network.ethernet
    tooltipText: Translation.tr("%1 | Right-click to configure").arg(Network.networkName)
    icon: Network.materialSymbol

    toggled: Network.wifiEnabled
    mainAction: () => Network.toggleWifi()
    hasMenu: true
}
