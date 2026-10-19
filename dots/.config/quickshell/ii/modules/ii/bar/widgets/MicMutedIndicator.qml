import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Microphone icon shown while the default input is muted
MaterialSymbol {
    readonly property bool active: Audio.source?.audio?.muted ?? false
    text: "mic_off"
    iconSize: Appearance.font.pixelSize.larger
    color: Appearance.colors.colOnLayer0
}
