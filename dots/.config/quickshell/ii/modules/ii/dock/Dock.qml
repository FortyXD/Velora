import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    readonly property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    Variants {
        // For each monitor
        model: Quickshell.screens

        PanelWindow {
            id: dockWindow
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked

            readonly property real bottomGap: Appearance.sizes.hyprlandGapsOut
            readonly property real hiddenOffset: dock.barHeight + bottomGap + Appearance.sizes.elevationMargin + dock.bounceHeight
            // Stays true for a moment after the pointer leaves, so brushing past the edge doesn't flicker the dock
            property bool hoverHold: false
            readonly property bool reveal: root.pinned || hoverHold || dock.menuOpen || dock.previewsOpen
                || !ToplevelManager.activeToplevel?.activated
            property real hideOffset: 0 // Animated in onRevealChanged
            Component.onCompleted: hideOffset = reveal ? 0 : hiddenOffset

            anchors {
                bottom: true
                left: true
                right: true
            }
            exclusiveZone: root.pinned ? dock.barHeight + bottomGap : 0
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"
            implicitHeight: bottomGap + dock.barHeight + dock.headroom

            mask: Region {
                item: inputRegion
            }

            DockContext {
                id: dock
                rowWidth: shelf.row.width
                magnifying: dockHover.hovered && dockWindow.reveal

                onAppMenuRequested: tile => dockWindow.openAppMenu(tile)
                onDockMenuRequested: tile => dockWindow.openDockMenu(tile)
            }

            onRevealChanged: {
                slideAnim.stop();
                slideAnim.to = reveal ? 0 : hiddenOffset;
                slideAnim.duration = reveal ? 380 : 260;
                slideAnim.easing.bezierCurve = reveal ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel;
                slideAnim.start();
            }

            NumberAnimation {
                id: slideAnim
                target: dockWindow
                property: "hideOffset"
                easing.type: Easing.BezierSpline
            }

            Timer {
                id: hideDelay
                interval: 300
                onTriggered: dockWindow.hoverHold = false
            }

            function menuPoint(tile) {
                return {
                    x: shelf.row.x + tile.visualCenter,
                    y: shelf.row.y + tile.visualTop - 8
                };
            }

            function openAppMenu(tile) {
                const point = menuPoint(tile);
                dockMenu.openAt(dockWindow, point.x, point.y, appMenuEntries(tile));
            }

            function openDockMenu(tile) {
                const point = tile ? menuPoint(tile) : {
                    x: shelf.row.x + dock.pointerX,
                    y: shelf.row.y - 8
                };
                dockMenu.openAt(dockWindow, point.x, point.y, dockMenuEntries());
            }

            function appMenuEntries(tile) {
                const entries = [];
                const appId = tile.appId;
                const toplevels = tile.toplevels;

                for (const toplevel of toplevels) {
                    entries.push({
                        text: toplevel.title || TaskbarApps.displayName(appId),
                        checked: toplevel.activated,
                        action: () => FreeWindows.activateToplevel(toplevel)
                    });
                }
                if (entries.length > 0) entries.push({ type: "separator" });

                const desktopEntry = TaskbarApps.desktopEntryFor(appId);
                const actions = desktopEntry?.actions ?? [];
                for (const action of actions) {
                    entries.push({
                        text: action.name,
                        action: () => {
                            action.execute();
                            TaskbarApps.markLaunching(appId, toplevels.length);
                        }
                    });
                }
                if (actions.length > 0) entries.push({ type: "separator" });

                entries.push({
                    text: toplevels.length > 0 ? Translation.tr("New window") : Translation.tr("Open"),
                    action: () => TaskbarApps.launch(appId, toplevels.length)
                });
                entries.push({
                    text: Translation.tr("Keep in dock"),
                    checked: TaskbarApps.isPinned(appId),
                    action: () => TaskbarApps.togglePin(appId)
                });
                if (toplevels.length > 0) {
                    entries.push({ type: "separator" });
                    entries.push({
                        text: toplevels.length > 1 ? Translation.tr("Close all windows") : Translation.tr("Close window"),
                        action: () => {
                            for (const toplevel of toplevels) toplevel.close();
                        }
                    });
                }
                return entries;
            }

            function dockMenuEntries() {
                return [
                    {
                        text: Translation.tr("Hide the dock automatically"),
                        checked: !root.pinned,
                        action: () => Config.options.dock.pinnedOnStartup = !root.pinned
                    },
                    {
                        text: Translation.tr("Magnification"),
                        checked: Config.options.dock.magnification,
                        action: () => Config.options.dock.magnification = !Config.options.dock.magnification
                    },
                    { type: "separator" },
                    {
                        text: Translation.tr("Dock settings…"),
                        action: () => Quickshell.execDetached(["env", "QS_SETTINGS_PAGE=desktop", "qs", "-p", Quickshell.shellPath("settings.qml")])
                    },
                ];
            }

            Item {
                id: content
                anchors.fill: parent

                HoverHandler {
                    id: dockHover
                    onPointChanged: dock.pointerX = point.position.x - shelf.row.x
                    onHoveredChanged: {
                        if (hovered) {
                            hideDelay.stop();
                            dockWindow.hoverHold = true;
                        } else {
                            hideDelay.restart();
                        }
                    }
                }

                // Where the dock takes input: the dock itself, the space its magnified icons
                // reach into while hovered, or a thin strip at the edge while hidden
                Item {
                    id: inputRegion
                    readonly property real revealedTop: shelf.row.y - (dock.magnifying ? dock.iconSize * (dock.maxScale - 1) + dock.topPadding : 0)
                    readonly property real stripHeight: Config.options.dock.hoverToReveal ? Config.options.dock.hoverRegionHeight : 0
                    x: shelf.background.x
                    width: shelf.background.width
                    y: dockWindow.reveal ? revealedTop : dockWindow.height - stripHeight
                    height: dockWindow.height - y
                }

                Item {
                    id: slider
                    anchors.fill: parent
                    transform: Translate {
                        y: dockWindow.hideOffset
                    }

                    DockShelf {
                        id: shelf
                        anchors.fill: parent
                        dock: dock
                        bottomGap: dockWindow.bottomGap
                        devicePixelRatio: dockWindow.devicePixelRatio
                        onAppsRequested: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                    }

                    // App name above the hovered icon
                    Rectangle {
                        id: nameLabel
                        readonly property Item tile: dock.hoveredTile
                        // Keeps its place and text while fading out
                        property Item shownTile: null
                        property string text: ""
                        onTileChanged: {
                            if (!tile || tile.label.length === 0) return;
                            shownTile = tile;
                            text = tile.label;
                        }

                        readonly property bool shown: tile !== null && tile.label.length > 0 && !tile.pressed
                            && tile.bounceOffset === 0 && !dock.menuOpen && !dock.previewsOpen && dockWindow.reveal
                        opacity: shown ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: nameLabel.shown ? 120 : 80
                            }
                        }

                        // Like the shell's tooltips (StyledToolTipContent)
                        implicitWidth: labelText.implicitWidth + 20
                        implicitHeight: labelText.implicitHeight + 12
                        radius: Appearance.popup.smallRadius
                        color: Appearance.popup.colBackground
                        border.width: 1
                        border.color: Appearance.popup.colBorder
                        x: shownTile ? Math.round(Math.max(4, Math.min(parent.width - width - 4, shelf.row.x + shownTile.visualCenter - width / 2))) : 0
                        y: shownTile ? Math.round(shelf.row.y + shownTile.visualTop - height - 10) : 0

                        StyledText {
                            id: labelText
                            anchors.centerIn: parent
                            text: nameLabel.text
                            font.pixelSize: Appearance.popup.captionSize
                            color: Appearance.popup.colText
                        }
                    }
                }
            }

            DockMenu {
                id: dockMenu
                onVisibleChanged: dock.menuOpen = visible
            }

            DockPreviews {
                dock: dock
                dockWindow: dockWindow
                rowX: shelf.row.x
                bottomY: shelf.row.y - dock.iconSize * (dock.maxScale - 1) - dock.topPadding
            }
        }
    }
}
