import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.presets

/**
 * Live miniature for the Appearance page: the bar in your colors and transparency, a terminal behind
 * a focused window with your rounding, shadows, opacity, dimming and blur, your fonts, and the
 * rounded screen corners. Everything follows the settings as they change.
 */
MiniScreen {
    id: root

    readonly property real bu: mockup.bu
    readonly property real rounding: HyprlandSettings.get("decoration:rounding", 16) * root.bu
    readonly property real borderSize: HyprlandSettings.get("general:border_size", 1)
    readonly property bool shadows: HyprlandSettings.get("decoration:shadow:enabled", true) === true
    readonly property real shadowRange: HyprlandSettings.get("decoration:shadow:range", 20) * root.bu
    readonly property real activeOpacity: HyprlandSettings.get("decoration:active_opacity", 1)
    readonly property real inactiveOpacity: HyprlandSettings.get("decoration:inactive_opacity", 1)
    readonly property bool dimInactive: HyprlandSettings.get("decoration:dim_inactive", false) === true
    readonly property real dimStrength: HyprlandSettings.get("decoration:dim_strength", 0.05)
    readonly property bool blur: HyprlandSettings.get("decoration:blur:enabled", true) === true
    readonly property real blurSize: HyprlandSettings.get("decoration:blur:size", 10)
    readonly property bool screenCorners: Config.options.appearance.fakeScreenRounding !== 0

    // The screen without the bar
    readonly property real barReserve: mockup.t + mockup.margin * 2
    readonly property rect area: {
        const bottom = Config.options.bar.bottom;
        if (mockup.vertical)
            return Qt.rect(bottom ? 0 : root.barReserve, 0, root.width - root.barReserve, root.height);
        return Qt.rect(0, bottom ? 0 : root.barReserve, root.width, root.height - root.barReserve);
    }

    radius: Appearance.rounding.small
    // Keep the wallpaper decoded as the settings sidebar and its columns resize.
    wallpaperItem.sourceSize: Qt.size(1120, 0)

    WindowMock {
        x: root.area.x + root.area.width * 0.08
        y: root.area.y + root.area.height * 0.12
        width: root.area.width * 0.53
        height: root.area.height * 0.56
        focused: false

        Column {
            x: Math.max(7, parent.width * 0.08)
            y: Math.max(6, parent.height * 0.10)
            spacing: 3
            Repeater {
                model: ["~ ❯ ls", "Documents  Music", "Pictures   Videos"]
                delegate: StyledText {
                    required property string modelData
                    required property int index
                    text: modelData
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Math.max(7, Math.min(14, 14 * root.bu))
                    color: index === 0 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
            }
        }
    }

    WindowMock {
        x: root.area.x + root.area.width * 0.35
        y: root.area.y + root.area.height * 0.34
        width: root.area.width * 0.55
        height: root.area.height * 0.55
        focused: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Math.round(Math.min(parent.width, parent.height) * 0.12)
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: Translation.tr("Aa")
                font.family: Appearance.font.family.title
                font.pixelSize: Math.max(18, Math.min(58, parent.height * 0.60))
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                text: Appearance.font.family.main
                font.family: Appearance.font.family.main
                font.pixelSize: Math.max(8, Math.min(14, parent.height * 0.17))
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
            Row {
                Layout.topMargin: 3
                spacing: 2
                Repeater {
                    model: [Appearance.colors.colPrimary, Appearance.colors.colSecondary, Appearance.colors.colTertiary]
                    Rectangle {
                        required property color modelData
                        width: Math.max(8, root.area.width * 0.070)
                        height: Math.max(4, 7 * root.bu)
                        radius: height / 2
                        color: modelData
                    }
                }
            }
        }
    }

    PresetMockup {
        id: mockup
        anchors.fill: parent
        barOnly: true
    }

    // Rounded screen corners
    Repeater {
        model: root.screenCorners ? [RoundCorner.CornerEnum.TopLeft, RoundCorner.CornerEnum.TopRight, RoundCorner.CornerEnum.BottomLeft, RoundCorner.CornerEnum.BottomRight] : []
        delegate: RoundCorner {
            required property var modelData
            corner: modelData
            implicitSize: Math.max(4, Appearance.rounding.screenRounding * root.bu)
            x: isLeft ? 0 : root.width - width
            y: isTop ? 0 : root.height - height
            z: 3
        }
    }

    component WindowMock: Item {
        id: win
        property bool focused
        readonly property real windowOpacity: win.focused ? root.activeOpacity : root.inactiveOpacity
        default property alias contentData: content.data

        RectangularShadow {
            visible: root.shadows
            anchors.fill: parent
            radius: root.rounding
            blur: root.shadowRange
            spread: 0
            color: "#ee1a1a1a"
        }

        Item { // Everything inside follows the window's rounded shape
            id: shape
            anchors.fill: parent
            layer.enabled: true
            layer.effect: GE.OpacityMask {
                maskSource: Rectangle {
                    width: shape.width
                    height: shape.height
                    radius: root.rounding
                }
            }

            ShaderEffectSource { // The wallpaper right behind the window, blurred when the window lets it through
                id: behind
                anchors.fill: parent
                visible: false
                sourceItem: root.wallpaperItem
                sourceRect: Qt.rect(win.x, win.y, win.width, win.height)
            }
            MultiEffect {
                visible: root.blur && win.windowOpacity < 1
                anchors.fill: parent
                source: behind
                blurEnabled: true
                blur: 1
                blurMax: Math.round(Math.min(64, root.blurSize * 3))
            }
            Rectangle {
                id: content
                anchors.fill: parent
                opacity: win.windowOpacity
                color: win.focused ? Appearance.m3colors.m3surfaceContainerLow : Appearance.m3colors.m3surfaceContainer
            }
            Rectangle { // Dimmed while unfocused
                anchors.fill: parent
                visible: !win.focused && root.dimInactive
                color: "black"
                opacity: root.dimStrength
            }
        }

        Rectangle { // Border
            anchors.fill: parent
            visible: root.borderSize > 0
            radius: root.rounding
            color: "transparent"
            border.width: Math.max(1, root.borderSize * root.bu)
            border.color: win.focused ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
        }
    }
}
