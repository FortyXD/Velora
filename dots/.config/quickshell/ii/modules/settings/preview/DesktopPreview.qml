import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.presets

/**
 * Live miniature of the desktop: windows tiled with your layout, gaps, border and rounding,
 * the bar, the dock with your pinned apps (it magnifies under the pointer, like the real one)
 * and the hot corners. Everything follows the settings as they change. Clicking a corner
 * moves the hot corners to that edge.
 */
MiniScreen {
    id: root

    signal cornerClicked(bool bottom)

    readonly property var dockConfig: Config.options.dock
    readonly property var corners: Config.options.sidebar.cornerOpen
    readonly property string dockMode: !root.dockConfig.enable ? "off"
        : root.dockConfig.pinnedOnStartup ? "always"
        : root.dockConfig.hoverToReveal ? "hover" : "empty"
    readonly property real bu: mockup.bu
    readonly property real gapsIn: HyprlandSettings.get("general:gaps_in", 4) * root.bu
    readonly property real gapsOut: HyprlandSettings.get("general:gaps_out", 5) * root.bu
    readonly property real borderSize: HyprlandSettings.get("general:border_size", 1)
    readonly property real rounding: HyprlandSettings.get("decoration:rounding", 12) * root.bu
    readonly property string tiling: HyprlandSettings.get("general:layout", "dwindle")

    // The dock, sized like the real one relative to the screen
    readonly property real dockScale: root.width / 1100
    readonly property real dockHeight: (root.dockConfig.height ?? 60) * root.dockScale
    readonly property real dockIcon: root.dockHeight * 0.73
    readonly property bool barAtBottom: Config.options.bar.bottom && !mockup.vertical
    readonly property real barReserve: mockup.t + mockup.margin * 2
    readonly property real dockBottom: (root.barAtBottom ? root.barReserve : 0) + 6 * root.dockScale

    // Where windows go: the screen without the bar, and without the dock when it always shows
    readonly property rect area: {
        let x = 0;
        let y = 0;
        let w = root.width;
        let h = root.height;
        if (mockup.vertical) {
            w -= root.barReserve;
            if (!Config.options.bar.bottom) x += root.barReserve;
        } else {
            h -= root.barReserve;
            if (!Config.options.bar.bottom) y += root.barReserve;
        }
        if (root.dockMode === "always") h -= root.dockHeight + 6 * root.dockScale;
        return Qt.rect(x + root.gapsOut, y + root.gapsOut, Math.max(10, w - root.gapsOut * 2), Math.max(10, h - root.gapsOut * 2));
    }
    readonly property var windowRects: {
        if (root.dockMode === "empty") return []; // The dock only shows on an empty workspace
        const a = root.area;
        const between = root.gapsIn * 2;
        if (root.tiling === "master") {
            const masterWidth = (a.width - between) * 0.56;
            const stackHeight = (a.height - between) / 2;
            const stackX = a.x + masterWidth + between;
            return [
                Qt.rect(a.x, a.y, masterWidth, a.height),
                Qt.rect(stackX, a.y, a.width - masterWidth - between, stackHeight),
                Qt.rect(stackX, a.y + stackHeight + between, a.width - masterWidth - between, stackHeight),
            ];
        }
        const half = (a.width - between) / 2;
        const quarter = (a.height - between) / 2;
        return [
            Qt.rect(a.x, a.y, half, a.height),
            Qt.rect(a.x + half + between, a.y, half, quarter),
            Qt.rect(a.x + half + between, a.y + quarter + between, half, quarter),
        ];
    }

    // Windows
    Repeater {
        model: 3
        delegate: Rectangle {
            id: windowBox
            required property int index
            readonly property var place: root.windowRects[index] ?? null
            visible: place !== null
            x: place?.x ?? 0
            y: place?.y ?? 0
            width: place?.width ?? 0
            height: place?.height ?? 0
            radius: root.rounding
            color: ColorUtils.applyAlpha(Appearance.colors.colLayer1, 0.94)
            border.width: root.borderSize > 0 ? Math.max(1, root.borderSize * root.bu) : 0
            border.color: windowBox.index === 0 ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

            Behavior on x {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on width {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on height {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            Column { // A hint of content
                x: 10
                y: 10
                spacing: 6
                Repeater {
                    model: Math.max(0, Math.min(5, Math.floor((windowBox.height - 20) / 14)))
                    delegate: Rectangle {
                        required property int index
                        width: (windowBox.width - 20) * (index === 0 ? 0.45 : 0.85 - 0.12 * (index % 3))
                        height: index === 0 ? 7 : 5
                        radius: 3
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, index === 0 ? 0.6 : 0.82)
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

    // Hot corners
    Repeater {
        model: [
            { "left": true, "bottom": false }, { "left": false, "bottom": false },
            { "left": true, "bottom": true }, { "left": false, "bottom": true },
        ]
        delegate: Item {
            id: corner
            required property var modelData
            readonly property bool active: root.corners.enable && root.corners.bottom === modelData.bottom
            width: 70
            height: 46
            x: modelData.left ? 0 : root.width - width
            y: modelData.bottom ? root.height - height : 0
            visible: root.corners.enable

            Rectangle { // Glow
                id: glow
                property real glowSize: cornerMouse.containsMouse || corner.active ? 64 : 0
                width: glow.glowSize * 2
                height: glow.glowSize * 2
                radius: glow.glowSize
                x: corner.modelData.left ? -glow.glowSize : corner.width - glow.glowSize
                y: corner.modelData.bottom ? corner.height - glow.glowSize : -glow.glowSize
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, corner.active ? 0.55 : 0.8)
                Behavior on glowSize {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            MaterialSymbol {
                visible: corner.active
                x: corner.modelData.left ? 8 : corner.width - width - 8
                y: corner.modelData.bottom ? corner.height - height - 6 : 6
                text: corner.modelData.left ? "left_panel_open" : "right_panel_open"
                iconSize: 18
                color: Appearance.colors.colOnPrimaryContainer
            }
            MouseArea {
                id: cornerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cornerClicked(corner.modelData.bottom)
            }
            StyledToolTip {
                alternativeVisibleCondition: cornerMouse.containsMouse
                extraVisibleCondition: false
                text: corner.modelData.left ? Translation.tr("Opens the left sidebar") : Translation.tr("Opens the right sidebar")
            }
        }
    }

    // Dock
    Rectangle {
        id: dockBox
        visible: root.dockMode !== "off"
        readonly property var apps: (root.dockConfig.pinnedApps ?? []).slice(0, 9)
        readonly property real slot: root.dockIcon * 1.14
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.dockBottom
        width: dockRow.width + root.dockHeight * 0.2
        height: root.dockHeight
        radius: root.dockHeight * 0.32
        color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 0.92)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        opacity: root.dockMode === "hover" && !dockHover.hovered ? 0.85 : 1

        HoverHandler {
            id: dockHover
        }

        Row {
            id: dockRow
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -root.dockHeight * 0.03
            Repeater {
                model: [...dockBox.apps, "SEPARATOR", "APPS"]
                delegate: Item {
                    id: tile
                    required property var modelData
                    readonly property bool separator: modelData === "SEPARATOR"
                    readonly property real center: tile.x + tile.width / 2
                    readonly property real magnify: !root.dockConfig.magnification || !dockHover.hovered || tile.separator ? 1
                        : 1 + (root.dockConfig.magnificationScale - 1) * Math.max(0, (1 + Math.cos(Math.PI * Math.min(1, Math.abs(tile.center - dockHover.point.position.x + dockRow.x) / (dockBox.slot * 2.4)))) / 2)
                    width: tile.separator ? root.dockIcon * 0.3 : dockBox.slot
                    height: root.dockIcon

                    Rectangle {
                        visible: tile.separator
                        anchors.centerIn: parent
                        width: 1
                        height: parent.height * 0.6
                        color: Appearance.colors.colOutlineVariant
                    }
                    Rectangle {
                        visible: tile.modelData === "APPS"
                        anchors.centerIn: parent
                        width: root.dockIcon * 0.92
                        height: width
                        radius: width * 0.28
                        scale: tile.magnify
                        transformOrigin: Item.Bottom
                        color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "apps"
                            iconSize: parent.width * 0.6
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                    IconImage {
                        visible: !tile.separator && tile.modelData !== "APPS"
                        anchors.centerIn: parent
                        implicitSize: root.dockIcon * 0.92
                        scale: tile.magnify
                        transformOrigin: Item.Bottom
                        source: visible ? Quickshell.iconPath(TaskbarApps.iconFor(tile.modelData), "image-missing") : ""
                        Behavior on scale {
                            NumberAnimation {
                                duration: 90
                            }
                        }
                    }
                }
            }
        }
    }

    // Where a hidden dock comes from
    MaterialSymbol {
        visible: root.dockMode === "hover" && !dockHover.hovered
        anchors.horizontalCenter: dockBox.horizontalCenter
        anchors.bottom: dockBox.top
        anchors.bottomMargin: 4
        text: "arrow_cool_down"
        rotation: 180
        iconSize: 18
        color: Appearance.colors.colOnLayer0
    }
}
