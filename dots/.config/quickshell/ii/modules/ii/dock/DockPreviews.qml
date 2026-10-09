pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Live previews of an app's windows. They open after resting on a running
 * app for a moment, then follow the pointer to other running apps.
 */
PopupWindow {
    id: root

    required property DockContext dock
    required property var dockWindow
    property real rowX: 0 // Dock row position in the dock window
    property real bottomY: 0 // Previews sit above this line of the dock window
    property real maxPreviewHeight: 180
    property real maxPreviewWidth: 280
    property real controlsHeight: 30

    property Item tile: null
    property bool shown: false
    readonly property var toplevels: tile?.toplevels ?? []

    function dismiss() {
        dwellTimer.stop();
        hideTimer.stop();
        root.shown = false;
    }

    onToplevelsChanged: {
        if (root.shown && root.toplevels.length === 0) root.dismiss();
    }

    Binding {
        target: root.dock
        property: "previewsOpen"
        value: root.shown
    }

    Connections {
        target: root.dock
        function onHoveredTileChanged() {
            const tile = root.dock.hoveredTile;
            if (tile && tile.windowCount > 0 && !root.dock.menuOpen) {
                hideTimer.stop();
                if (root.shown) root.tile = tile;
                else dwellTimer.restart();
            } else {
                dwellTimer.stop();
                if (root.shown) hideTimer.restart();
            }
        }
        function onTileActivated() {
            root.dismiss();
        }
        function onAppMenuRequested() {
            root.dismiss();
        }
        function onDockMenuRequested() {
            root.dismiss();
        }
    }

    Timer {
        id: dwellTimer
        interval: 550
        onTriggered: {
            const tile = root.dock.hoveredTile;
            if (!tile || !(tile.windowCount > 0)) return;
            root.tile = tile;
            root.shown = true;
        }
    }

    Timer {
        id: hideTimer
        interval: 350
        onTriggered: {
            if (!contentArea.containsMouse) root.shown = false;
        }
    }

    anchor {
        window: root.dockWindow
        rect.x: 0
        rect.y: root.bottomY
        edges: Edges.Top | Edges.Left
        gravity: Edges.Top | Edges.Right
        adjustment: PopupAdjustment.None
    }

    visible: previewBackground.opacity > 0
    color: "transparent"
    implicitWidth: root.dockWindow?.width ?? 1
    implicitHeight: contentArea.implicitHeight
    mask: Region {
        item: contentArea
    }

    MouseArea {
        id: contentArea
        readonly property real margin: Appearance.sizes.elevationMargin
        anchors.bottom: parent.bottom
        implicitWidth: previewBackground.implicitWidth + margin * 2
        implicitHeight: root.maxPreviewHeight + root.controlsHeight + margin * 2 + previewBackground.padding * 2
        width: implicitWidth
        height: implicitHeight
        x: Math.max(0, Math.min(root.width - width, root.rowX + (root.tile?.baseCenter ?? 0) - width / 2))
        hoverEnabled: true
        onContainsMouseChanged: {
            if (containsMouse) hideTimer.stop();
            else if (!(root.dock.hoveredTile?.windowCount > 0)) hideTimer.restart();
        }

        Behavior on x {
            enabled: root.shown
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        StyledRectangularShadow {
            target: previewBackground
            opacity: previewBackground.opacity
            visible: opacity > 0
        }

        Rectangle {
            id: previewBackground
            readonly property real padding: 5
            anchors {
                bottom: parent.bottom
                bottomMargin: contentArea.margin
                horizontalCenter: parent.horizontalCenter
            }
            implicitWidth: previewRow.implicitWidth + padding * 2
            implicitHeight: previewRow.implicitHeight + padding * 2
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainer
            clip: true

            opacity: root.shown ? 1 : 0
            transform: Translate {
                y: root.shown ? 0 : 8
                Behavior on y {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on implicitWidth {
                enabled: root.shown
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            RowLayout {
                id: previewRow
                anchors.centerIn: parent

                Repeater {
                    model: ScriptModel {
                        // No captures run while the previews are hidden
                        values: root.visible ? root.toplevels : []
                    }

                    RippleButton {
                        id: windowButton
                        required property var modelData
                        Layout.fillHeight: true
                        padding: 0
                        middleClickAction: () => {
                            windowButton.modelData?.close();
                        }
                        onClicked: {
                            windowButton.modelData?.activate();
                            root.dismiss();
                        }
                        contentItem: ColumnLayout {
                            implicitWidth: screencopyView.implicitWidth
                            implicitHeight: screencopyView.implicitHeight

                            ButtonGroup {
                                contentWidth: parent.width - anchors.margins * 2
                                StyledText {
                                    Layout.margins: 5
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    text: windowButton.modelData?.title ?? ""
                                    elide: Text.ElideRight
                                    color: Appearance.m3colors.m3onSurface
                                }
                                GroupButton {
                                    colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                    baseWidth: root.controlsHeight
                                    baseHeight: root.controlsHeight
                                    buttonRadius: Appearance.rounding.full
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "close"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                    onClicked: {
                                        windowButton.modelData?.close();
                                    }
                                }
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                implicitHeight: screencopyView.height
                                implicitWidth: screencopyView.width
                                ScreencopyView {
                                    id: screencopyView
                                    anchors.centerIn: parent
                                    captureSource: windowButton.modelData
                                    live: true
                                    paintCursor: true
                                    constraintSize: Qt.size(root.maxPreviewWidth, root.maxPreviewHeight)
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: screencopyView.width
                                            height: screencopyView.height
                                            radius: Appearance.rounding.small
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
