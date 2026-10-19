import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Number of pending system updates; click to update in a terminal
IndicatorWidget {
    id: root

    readonly property color textColor: host?.inPill ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer0
    active: Updates.available && (Updates.count > 0 || (host?.options?.alwaysShow ?? false))
    clickable: true
    tooltipText: Updates.count > 0 ? Translation.tr("%1 updates available. Click to update").arg(Updates.count) : Translation.tr("Up to date")
    onActivated: Quickshell.execDetached(["bash", "-c", Config.options.apps.update])

    Row {
        spacing: 3
        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: Updates.updateStronglyAdvised ? "system_update_alt" : "update"
            iconSize: Appearance.font.pixelSize.larger
            color: Updates.updateStronglyAdvised ? Appearance.colors.colError : root.textColor
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: Updates.count > 0
            text: Updates.count
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.textColor
        }
    }
}
