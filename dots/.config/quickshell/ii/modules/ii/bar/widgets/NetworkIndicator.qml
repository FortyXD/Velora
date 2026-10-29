import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Connection type and signal strength
StatusIcon {
    readonly property bool active: true
    text: Network.materialSymbol
    busy: Network.wifiConnecting && !Network.ethernet
    iconSize: Appearance.font.pixelSize.larger
    color: Appearance.colors.colOnLayer0
}
