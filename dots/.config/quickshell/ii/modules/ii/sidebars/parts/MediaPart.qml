import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.mediaControls

/**
 * What's playing: the same player card as the media popup (option hideWhenIdle).
 */
Item {
    id: root
    property Item host: null
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool partVisible: root.player !== null || !(root.host?.options.hideWhenIdle ?? true)

    implicitHeight: root.player !== null ? Appearance.sizes.mediaControlsHeight - Appearance.sizes.elevationMargin * 2 : idle.implicitHeight

    Loader {
        anchors.fill: parent
        anchors.margins: -Appearance.sizes.elevationMargin // The card keeps room for a shadow the sidebar doesn't need
        active: root.player !== null
        sourceComponent: PlayerControl {
            player: root.player
            radius: Appearance.rounding.normal
            live: root.host?.active ?? false
        }
    }

    Rectangle {
        id: idle
        visible: root.player === null
        anchors.fill: parent
        implicitHeight: idleRow.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        RowLayout {
            id: idleRow
            anchors.centerIn: parent
            spacing: 12
            MaterialShapeWrappedMaterialSymbol {
                shape: MaterialShape.Shape.Cookie7Sided
                text: "music_off"
                iconSize: 22
                padding: 10
            }
            ColumnLayout {
                spacing: 2
                StyledText {
                    text: Translation.tr("Nothing playing")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: Translation.tr("Start music or a video to control it here")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
