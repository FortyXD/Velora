import QtQuick
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
    readonly property real rounding: HyprlandSettings.get("decoration:rounding", 18) * root.bu
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

    WindowMock {
        x: root.area.x + root.area.width * 0.06
        y: root.area.y + root.area.height * 0.09
        width: root.area.width * 0.5
        height: root.area.height * 0.6
        focused: false

        Column { // A terminal
            x: 12 * root.bu
            y: 12 * root.bu
            spacing: 3 * root.bu
            Repeater {
                model: ["~ ❯ ls", "Documents  Music", "Pictures  Videos", "~ ❯ _"]
                delegate: StyledText {
                    required property string modelData
                    required property int index
                    text: modelData
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Math.max(7, 12 * root.bu)
                    color: index === 0 || index === 3 ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                }
            }
        }
    }

    WindowMock {
        x: root.area.x + root.area.width * 0.36
        y: root.area.y + root.area.height * 0.3
        width: root.area.width * 0.56
        height: root.area.height * 0.6
        focused: true

        Column { // A note in your fonts
            x: 14 * root.bu
            y: 12 * root.bu
            width: parent.width - 28 * root.bu
            spacing: 4 * root.bu
            StyledText {
                width: parent.width
                text: Translation.tr("Hello there")
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.pixelSize: Math.max(9, 20 * root.bu)
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                width: parent.width
                text: Translation.tr("This is how your windows look. Change something below and watch it here.")
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: Appearance.font.family.main
                font.pixelSize: Math.max(7, 12 * root.bu)
                color: Appearance.colors.colSubtext
            }
            Rectangle {
                width: 64 * root.bu
                height: 20 * root.bu
                radius: height / 2
                color: Appearance.colors.colPrimary
                StyledText {
                    anchors.centerIn: parent
                    text: "OK"
                    font.pixelSize: Math.max(7, 11 * root.bu)
                    color: Appearance.colors.colOnPrimary
                }
            }
            Item { width: 1; height: 6 * root.bu }
            Repeater { // A hint of more content
                model: [0.9, 0.75, 0.82, 0.5]
                delegate: Rectangle {
                    required property real modelData
                    width: parent.width * modelData
                    height: 6 * root.bu
                    radius: height / 2
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.85)
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
