import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Connection type and signal strength
MaterialSymbol {
    readonly property bool active: true
    text: Network.materialSymbol
    iconSize: Appearance.font.pixelSize.larger
    color: Appearance.colors.colOnLayer0
}
