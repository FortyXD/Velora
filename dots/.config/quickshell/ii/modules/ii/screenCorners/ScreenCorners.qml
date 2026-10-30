import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The rounded screen corners, and the hot corners (Config.options.hotCorners, actions in services/HotCorners.qml),
 * each in windows of their own so hot corners work whatever the rounding is set to.
 */
Scope {
    id: screenCorners

    component CornerPanelWindow: PanelWindow {
        id: cornerPanelWindow
        property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
        property bool fullscreen
        // Stays mapped behind fullscreen windows and only hides the corner: mapping it again on leaving
        // fullscreen made the corners pop in a moment late
        readonly property bool cornerShown: Config.options.appearance.fakeScreenRounding === 1 || (Config.options.appearance.fakeScreenRounding === 2 && !fullscreen)
        visible: Config.options.appearance.fakeScreenRounding !== 0
        property var corner

        exclusionMode: ExclusionMode.Ignore
        mask: Region {} // Only draws
        WlrLayershell.namespace: "quickshell:screenCorners"
        WlrLayershell.layer: WlrLayer.Overlay
        color: "transparent"

        anchors {
            top: cornerWidget.isTopLeft || cornerWidget.isTopRight
            left: cornerWidget.isBottomLeft || cornerWidget.isTopLeft
            bottom: cornerWidget.isBottomLeft || cornerWidget.isBottomRight
            right: cornerWidget.isTopRight || cornerWidget.isBottomRight
        }
        margins {
            right: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.right) * -1
            bottom: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.bottom) * -1
        }

        implicitWidth: cornerWidget.implicitWidth
        implicitHeight: cornerWidget.implicitHeight

        RoundCorner {
            id: cornerWidget
            anchors.fill: parent
            opacity: cornerPanelWindow.cornerShown ? 1 : 0
            corner: cornerPanelWindow.corner
            rightVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.right) * 1
            bottomVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.bottom) * 1

            implicitSize: Appearance.rounding.screenRounding
        }
    }

    // A hot corner: a small trigger area in the very corner, with a soft glow that shows it's there and grows,
    // with the action's icon, while the pointer is on it
    component HotCornerWindow: PanelWindow {
        id: hotWindow
        required property string corner // topLeft, topRight, bottomLeft, bottomRight
        property bool fullscreen
        readonly property var options: Config.options.hotCorners
        readonly property string action: hotWindow.options[hotWindow.corner]?.action ?? "none"
        readonly property var actionInfo: HotCorners.actionInfo(hotWindow.action)
        readonly property bool isTop: hotWindow.corner.startsWith("top")
        readonly property bool isLeft: hotWindow.corner.endsWith("Left")
        readonly property bool hovered: triggerArea.containsMouse
        readonly property real glowRadius: hotWindow.hovered ? 46 : (hotWindow.options.hint ? 9 : 0)
        readonly property bool deadPixelWorkaround: Config.options.interactions.deadPixelWorkaround.enable
        readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)

        HotCornerActivationGuard {
            id: activationGuard
            suppressed: HotCorners.blocked
            corner: hotWindow.corner
            screenX: hotWindow.hyprlandMonitor?.x ?? 0
            screenY: hotWindow.hyprlandMonitor?.y ?? 0
            screenWidth: hotWindow.screen?.width ?? 0
            screenHeight: hotWindow.screen?.height ?? 0
            size: hotWindow.options.size
            // Current circular masks have a diameter of 2 * size; older shells used a square.
            circular: triggerArea.width === 2 * hotWindow.options.size
            onAllowedChanged: {
                if (!allowed) dwellTimer?.stop();
                else if (triggerArea?.containsMouse && hotWindow.options.trigger === "hover")
                    dwellTimer?.restart(); // A fresh entry may have arrived during the cursor check.
            }
        }
        Connections {
            target: HotCorners
            function onSelectionFinished(x, y, valid) {
                activationGuard.resumeAt(x, y, valid && hotWindow.hyprlandMonitor !== null);
            }
        }

        function trigger() {
            if (!activationGuard.allowed) return;
            HotCorners.run(hotWindow.action, hotWindow.options[hotWindow.corner]?.command ?? "");
        }

        visible: hotWindow.action !== "none" && !GlobalStates.regionSelectorOpen
            && (!hotWindow.fullscreen || hotWindow.options.inFullscreen)
        exclusionMode: ExclusionMode.Ignore
        mask: Region {
            item: triggerArea
        }
        WlrLayershell.namespace: "quickshell:hotCorner"
        WlrLayershell.layer: WlrLayer.Overlay
        color: "transparent"
        anchors {
            top: hotWindow.isTop
            bottom: !hotWindow.isTop
            left: hotWindow.isLeft
            right: !hotWindow.isLeft
        }
        margins {
            right: (hotWindow.deadPixelWorkaround && !hotWindow.isLeft) * -1
            bottom: (hotWindow.deadPixelWorkaround && !hotWindow.isTop) * -1
        }
        implicitWidth: 60
        implicitHeight: 60

        Rectangle { // The glow, a quarter of a circle in the corner
            width: hotWindow.glowRadius * 2
            height: hotWindow.glowRadius * 2
            radius: hotWindow.glowRadius
            x: hotWindow.isLeft ? -hotWindow.glowRadius : parent.width - hotWindow.glowRadius
            y: hotWindow.isTop ? -hotWindow.glowRadius : parent.height - hotWindow.glowRadius
            color: ColorUtils.transparentize(Appearance.colors.colPrimary, hotWindow.hovered ? 0.1 : 0.5)
            Behavior on width {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on height {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
        MaterialSymbol {
            opacity: hotWindow.hovered ? 1 : 0
            x: hotWindow.isLeft ? 7 : parent.width - width - 7
            y: hotWindow.isTop ? 7 : parent.height - height - 7
            text: hotWindow.actionInfo.icon
            iconSize: 20
            fill: 1
            color: Appearance.colors.colOnPrimary
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        FocusedScrollMouseArea {
            id: triggerArea
            width: hotWindow.options.size
            height: hotWindow.options.size
            x: hotWindow.isLeft ? 0 : parent.width - width - (hotWindow.deadPixelWorkaround ? 1 : 0)
            y: hotWindow.isTop ? 0 : parent.height - height - (hotWindow.deadPixelWorkaround ? 1 : 0)
            hoverEnabled: true
            cursorShape: hotWindow.options.trigger === "click" ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: if (activationGuard.allowed && hotWindow.options.trigger === "hover") dwellTimer.restart()
            onExited: {
                dwellTimer.stop();
                activationGuard.pointerExited();
            }
            onPressed: if (hotWindow.options.trigger === "click") hotWindow.trigger()
            onScrollUp: {
                if (!activationGuard.allowed || !hotWindow.options.scroll) return;
                if (hotWindow.isLeft) Brightness.increaseBrightness();
                else Audio.incrementVolume();
            }
            onScrollDown: {
                if (!activationGuard.allowed || !hotWindow.options.scroll) return;
                if (hotWindow.isLeft) Brightness.decreaseBrightness();
                else Audio.decrementVolume();
            }
            onMovedAway: {
                if (!hotWindow.options.scroll) return;
                if (hotWindow.isLeft) GlobalStates.osdBrightnessOpen = false;
                else GlobalStates.osdVolumeOpen = false;
            }
        }
        Timer { // A short stay in the corner, so passing through it doesn't fire
            id: dwellTimer
            interval: 120
            onTriggered: if (triggerArea.containsMouse) hotWindow.trigger()
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: monitorScope
            required property var modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

            // Hide when fullscreen
            property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
            property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
            property bool fullscreen: activeWorkspaceWithFullscreen != undefined

            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.TopLeft
                fullscreen: monitorScope.fullscreen
            }
            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.TopRight
                fullscreen: monitorScope.fullscreen
            }
            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.BottomLeft
                fullscreen: monitorScope.fullscreen
            }
            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.BottomRight
                fullscreen: monitorScope.fullscreen
            }

            Variants {
                model: HotCorners.cornerNames
                delegate: HotCornerWindow {
                    required property var modelData
                    screen: monitorScope.modelData
                    corner: modelData
                    fullscreen: monitorScope.fullscreen
                }
            }
        }
    }
}
