import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import qs.modules.ii.mediaControls

/**
 * The active media player on the desktop, using the same player card as the media popup.
 */
AbstractBackgroundWidget {
    id: root
    configEntryName: "media"

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool hideWhenIdle: Config.options.background.widgets.media.hideWhenIdle
    readonly property bool hidden: root.hideWhenIdle && root.player === null

    implicitWidth: Appearance.sizes.mediaControlsWidth
    implicitHeight: Appearance.sizes.mediaControlsHeight
    opacity: ((GlobalStates.screenLocked && !root.visibleWhenLocked) || root.hidden) ? 0 : 1

    Loader {
        anchors.fill: parent
        active: root.player !== null
        sourceComponent: PlayerControl {
            player: root.player
            radius: Appearance.rounding.verylarge
        }
    }

    // Placeholder when nothing is playing and the widget stays visible
    Rectangle {
        visible: root.player === null
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0

        RowLayout {
            anchors.centerIn: parent
            spacing: 12
            MaterialShapeWrappedMaterialSymbol {
                shape: MaterialShape.Shape.Cookie7Sided
                text: "music_off"
                iconSize: 26
                padding: 12
            }
            ColumnLayout {
                spacing: 2
                StyledText {
                    text: Translation.tr("Nothing playing")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
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
