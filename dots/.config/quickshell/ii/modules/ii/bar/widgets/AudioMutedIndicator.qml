import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Speaker icon shown while the default output is muted
MaterialSymbol {
    readonly property bool active: Audio.sink?.audio?.muted ?? false
    text: "volume_off"
    iconSize: Appearance.font.pixelSize.larger
    color: Appearance.colors.colOnLayer0
}
