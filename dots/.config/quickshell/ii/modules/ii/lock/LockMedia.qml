import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.mediaControls

/**
 * What's playing, with working buttons (the lock screen takes all input, so the desktop widget
 * can't be used there). With `liveData` off, or nothing playing in an editor, an example card.
 */
Item {
    id: root
    property bool liveData: true
    property bool placeholder: false // Show the example card when nothing plays
    property bool wanted: true // Shown in the layout; the player card isn't built otherwise
    readonly property MprisPlayer player: root.liveData ? MprisController.activePlayer : null
    readonly property bool hasContent: root.player !== null

    implicitWidth: Appearance.sizes.mediaControlsWidth
    implicitHeight: Appearance.sizes.mediaControlsHeight

    Loader {
        anchors.fill: parent
        active: root.wanted && root.player !== null
        sourceComponent: PlayerControl {
            player: root.player
            radius: Appearance.rounding.verylarge
        }
    }

    // Example
    Rectangle {
        visible: root.player === null && (root.placeholder || !root.liveData)
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colSecondaryContainer

        RowLayout {
            anchors {
                fill: parent
                margins: 14
            }
            spacing: 14
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: height
                radius: Appearance.rounding.normal
                gradient: Gradient {
                    GradientStop { position: 0; color: Appearance.colors.colPrimary }
                    GradientStop { position: 1; color: Appearance.colors.colTertiary }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "music_note"
                    iconSize: 40
                    color: Appearance.colors.colOnPrimary
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: root.liveData ? Translation.tr("Nothing playing") : Translation.tr("Song title")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    text: root.liveData ? Translation.tr("Shows up when music plays") : Translation.tr("Artist")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: 0.8
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    spacing: 18
                    Repeater {
                        model: ["skip_previous", "pause", "skip_next"]
                        MaterialSymbol {
                            required property string modelData
                            text: modelData
                            iconSize: 26
                            fill: 1
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }
}
