pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.onboarding
import QtQuick
import QtQuick.Layouts

/**
 * Light or dark, and a wallpaper from the presets' pictures with its own theme. Both apply with the
 * live preview as soon as they're picked; what's on its way shows until the shell says it's done.
 */
PageScaffold {
    id: root
    title: Translation.tr("Choose your look")
    subtitle: Translation.tr("Colors come from the wallpaper.")

    // Pictures from the presets, not videos or animated ones
    readonly property var pictures: Presets.presets.filter(preset => preset.kind === "builtin" && Presets.isRemote(preset.wallpaperAnimations?.wallpaper)
        && !FileUtils.isVideoPath((preset.wallpaperAnimations?.wallpaper ?? "").split("?")[0]) && (preset.wallpaperPreview ?? "").length > 0)
        .sort((a, b) => Number(b.id === "autumn") - Number(a.id === "autumn"))
    // Autumn tree, unless another was picked: on the desktop as soon as the step opens
    Component.onCompleted: {
        if (!root.flow.preservePalette && root.flow.appliedWallpaper !== root.flow.choices.wallpaper) root.flow.applyWallpaper(root.flow.choices.wallpaper);
    }
    // Being downloaded and applied: a wallpaper, or the theme in light or dark
    readonly property string pendingWallpaper: root.flow.applying === "wallpaper" ? root.flow.applyingId : ""
    readonly property bool pendingTheme: root.flow.applying === "theme"

    Reveal {
        order: 1
        RowLayout {
            width: parent.width
            spacing: 16
            Repeater {
                model: [{ "value": "light", "name": Translation.tr("Light"), "dark": false },
                        { "value": "dark", "name": Translation.tr("Dark"), "dark": true }]
                delegate: SelectCard {
                    id: themeCard
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 128
                    selected: root.flow.shownTheme === themeCard.modelData.value
                    onClicked: if (!themeCard.selected || root.flow.choices.theme === "") root.flow.applyTheme(themeCard.modelData.value)
                    readonly property color paper: themeCard.modelData.dark ? ColorUtils.colorWithHueOf("#25222a", Appearance.m3colors.m3primary)
                        : ColorUtils.colorWithHueOf("#f6f2fb", Appearance.m3colors.m3primary)
                    readonly property color ink: themeCard.modelData.dark ? "#e8e1ef" : "#2a2530"
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14
                        // A little window in that theme
                        Rectangle {
                            Layout.preferredWidth: 120
                            Layout.fillHeight: true
                            radius: Appearance.rounding.small
                            color: themeCard.paper
                            border.width: 1
                            border.color: ColorUtils.transparentize(themeCard.ink, 0.85)
                            Column {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 7
                                Rectangle { width: parent.width * 0.6; height: 8; radius: 4; color: Appearance.m3colors.m3primary }
                                Rectangle { width: parent.width; height: 6; radius: 3; color: ColorUtils.transparentize(themeCard.ink, 0.7) }
                                Rectangle { width: parent.width * 0.8; height: 6; radius: 3; color: ColorUtils.transparentize(themeCard.ink, 0.7) }
                                Rectangle { width: parent.width * 0.5; height: 6; radius: 3; color: ColorUtils.transparentize(themeCard.ink, 0.7) }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: themeCard.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                        MaterialLoadingIndicator {
                            Layout.rightMargin: 30
                            implicitSize: 32
                            visible: root.pendingTheme && themeCard.selected
                            loading: visible
                        }
                    }
                }
            }
        }
    }

    Reveal {
        order: 2
        StyledText {
            text: Translation.tr("Wallpaper")
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer0
        }
    }

    Reveal {
        order: 3
        Flow {
            width: parent.width
            spacing: 12

            Repeater {
                model: root.pictures
                delegate: SelectCard {
                    id: tile
                    required property var modelData
                    width: 168
                    height: 104
                    radius: Appearance.rounding.normal
                    selected: root.flow.choices.wallpaper === tile.modelData.id
                    onClicked: if (!tile.selected || root.flow.preservePalette) root.flow.applyWallpaper(tile.modelData.id)
                    Image {
                        id: preview
                        anchors.fill: parent
                        source: tile.modelData.wallpaperPreview
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 336
                        asynchronous: true
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.ms(300) }
                        }
                    }
                    // Downloading and applying it
                    Rectangle {
                        anchors.fill: parent
                        visible: opacity > 0
                        opacity: root.pendingWallpaper === tile.modelData.id ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.ms(200) }
                        }
                        color: ColorUtils.transparentize("#000000", 0.45)
                        MaterialLoadingIndicator {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -10
                            implicitSize: 40
                            loading: parent.visible
                        }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 26
                        color: ColorUtils.transparentize("#000000", 0.55)
                        StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr(tile.modelData.name)
                            color: "#ffffff"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }
        }
    }

    Reveal {
        order: 4
        visible: root.pictures.length === 0
        StyledText {
            width: parent.width
            wrapMode: Text.Wrap
            text: Translation.tr("More wallpapers appear here when you're online, and in Settings → Presets.")
            color: Appearance.colors.colSubtext
        }
    }
}
