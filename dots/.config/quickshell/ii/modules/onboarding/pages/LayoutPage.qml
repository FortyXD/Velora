pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.onboarding
import qs.modules.settings.presets
import QtQuick
import QtQuick.Layouts

/**
 * The desktop: three looks drawn as they will be, applied to the real desktop as soon as one is
 * picked, while the assistant's selection animation stays live, and how windows behave. The looks differ in
 * layout only: all of them wear the chosen wallpaper's theme, drawn so here too.
 */
PageScaffold {
    id: root
    title: Translation.tr("Choose your desktop")
    subtitle: Translation.tr("It changes right away. Everything can be rearranged later in Settings.")

    // The one picked shows on the desktop as soon as the step opens
    Component.onCompleted: if (root.flow.appliedLook !== root.flow.choices.look) root.flow.applyLook(root.flow.choices.look)

    // The wallpaper's theme, in light or dark if that was picked
    readonly property var theme: {
        if (root.flow.preservePalette) return { "mode": Appearance.m3colors.darkmode ? "dark" : "light",
            "accent": Config.options.appearance.palette.accentColor };
        const theme = Presets.find(root.flow.choices.wallpaper)?.theme;
        if (!theme) return undefined;
        return Object.assign({}, theme, root.flow.choices.theme ? { "mode": root.flow.choices.theme } : {});
    }
    function mockupOf(look) {
        const preset = Presets.find(root.flow.lookPresets[look]);
        return preset ? Object.assign({}, preset, { "theme": root.theme }) : null;
    }

    readonly property var looks: [
        { "id": "velora", "name": "Velora", "description": Translation.tr("A bar at the top and a dock that comes up from below") },
        { "id": "horizon", "name": "Velora Horizon", "description": Translation.tr("A floating taskbar at the bottom with your apps") },
        { "id": "vertical", "name": "Velora Vertical", "description": Translation.tr("A narrow bar along the left side, more room for windows") },
    ]

    Reveal {
        order: 1
        RowLayout {
            width: parent.width
            spacing: 16

            Repeater {
                model: root.looks
                delegate: SelectCard {
                    id: card
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 312
                    selected: root.flow.choices.look === card.modelData.id
                    onClicked: root.flow.applyLook(card.modelData.id)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10
                        // The look itself, small; it comes alive (a little larger) when chosen
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width * 10 / 16
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: root.flow.currentPicture ? `file://${root.flow.currentPicture}` : ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 480
                                asynchronous: true
                            }
                            PresetMockup {
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.height
                                preset: root.mockupOf(card.modelData.id)
                                scale: card.selected ? 1 : 0.94
                                Behavior on scale {
                                    NumberAnimation { duration: Motion.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial }
                                }
                            }
                            // On its way to the desktop
                            MaterialLoadingIndicator {
                                anchors.centerIn: parent
                                implicitSize: 44
                                visible: opacity > 0
                                opacity: root.flow.applying === "look" && card.selected ? 1 : 0
                                loading: visible
                                Behavior on opacity {
                                    NumberAnimation { duration: Motion.ms(200) }
                                }
                            }
                        }
                        StyledText {
                            text: card.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: card.modelData.description
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    Reveal {
        order: 2
        RowLayout {
            width: parent.width
            spacing: 18

            WindowsDemo {
                free: root.flow.choices.windows !== "tiling"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    text: Translation.tr("Windows")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.flow.choices.windows === "tiling"
                        ? Translation.tr("New windows share the screen without overlapping. Super+arrows move between them.")
                        : Translation.tr("Windows stay where you put them. Super+arrows snap them to halves of the screen.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                // Segmented: tiling | free
                Row {
                    spacing: 4
                    Repeater {
                        model: [{ "value": "tiling", "text": Translation.tr("Tiling"), "icon": "view_quilt" },
                                { "value": "floating", "text": Translation.tr("Free windows"), "icon": "select_window" }]
                        delegate: RippleButton {
                            id: segment
                            required property var modelData
                            required property int index
                            toggled: (root.flow.choices.windows === "tiling") === (segment.modelData.value === "tiling")
                            implicitHeight: 40
                            implicitWidth: segmentRow.implicitWidth + 32
                            buttonRadius: height / 2
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: root.flow.applyWindows(segment.modelData.value)
                            contentItem: RowLayout {
                                id: segmentRow
                                spacing: 6
                                MaterialSymbol {
                                    Layout.leftMargin: 16
                                    text: segment.modelData.icon
                                    iconSize: 18
                                    color: segment.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    Layout.rightMargin: 16
                                    text: segment.modelData.text
                                    color: segment.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
