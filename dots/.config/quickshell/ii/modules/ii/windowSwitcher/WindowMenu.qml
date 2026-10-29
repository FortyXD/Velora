pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The window menu (Alt+Space, free windows), at the window's corner as on Windows: minimize,
 * maximize, snap, keep on every workspace, close. For windows that draw no title bar of their own.
 */
Scope {
    id: root
    property bool open: false
    property var target: null // The active window when it opened (hyprctl clients entry)

    GlobalShortcut {
        name: "windowMenuToggle"
        description: "Menu of the active window"
        onPressed: {
            if (root.open || !FreeWindows.enabled) {
                root.open = false;
                return;
            }
            root.target = HyprlandData.windowList.find(window => window.focusHistoryID === 0) ?? null;
            root.open = root.target !== null;
        }
    }

    function act(action) {
        root.open = false;
        const address = root.target?.address ?? "";
        const selector = `address:${address}`;
        switch (action) {
        case "minimize": FreeWindows.minimize(address); break;
        case "maximize": FreeWindows.toggleMaximize(address); break;
        case "left": FreeWindows.snap("left", address); break;
        case "right": FreeWindows.snap("right", address); break;
        case "center": FreeWindows.snap("center", address); break;
        case "pin": Hyprland.dispatch(`hl.dsp.window.pin({ window = "${selector}" })`); break;
        case "close": Hyprland.dispatch(`hl.dsp.window.close({ window = "${selector}" })`); break;
        }
    }

    LazyLoader {
        active: root.open

        component: PanelWindow {
            id: window
            readonly property var monitor: HyprlandData.monitors.find(monitor => monitor.id === root.target?.monitor)
            screen: Quickshell.screens.find(screen => screen.name === window.monitor?.name) ?? Quickshell.screens[0]
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:windowMenu"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: root.open = false
            }

            StyledRectangularShadow {
                target: menu
            }
            Rectangle {
                id: menu
                // At the window's top-left corner, kept on the screen
                x: Math.max(8, Math.min(window.width - width - 8, (root.target?.at?.[0] ?? 0) - (window.monitor?.x ?? 0) + 8))
                y: Math.max(8, Math.min(window.height - height - 8, (root.target?.at?.[1] ?? 0) - (window.monitor?.y ?? 0) + 8))
                width: 232
                height: items.implicitHeight + 12
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                focus: true
                Keys.onEscapePressed: root.open = false

                opacity: 0
                scale: 0.94
                transformOrigin: Item.TopLeft
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                ColumnLayout {
                    id: items
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 6
                    }
                    spacing: 0

                    Repeater {
                        model: [
                            { "action": "minimize", "icon": "minimize", "text": Translation.tr("Minimize") },
                            { "action": "maximize", "icon": (root.target?.fullscreen ?? 0) !== 0 ? "close_fullscreen" : "open_in_full",
                              "text": (root.target?.fullscreen ?? 0) !== 0 ? Translation.tr("Restore") : Translation.tr("Maximize") },
                            { "action": "left", "icon": "border_left", "text": Translation.tr("Snap left") },
                            { "action": "right", "icon": "border_right", "text": Translation.tr("Snap right") },
                            { "action": "center", "icon": "center_focus_strong", "text": Translation.tr("Center the window") },
                            { "action": "pin", "icon": "keep", "text": root.target?.pinned ? Translation.tr("Only on this workspace") : Translation.tr("Show on every workspace") },
                            { "action": "close", "icon": "close", "text": Translation.tr("Close"), "danger": true },
                        ]

                        delegate: RippleButton {
                            id: item
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.small
                            onClicked: root.act(item.modelData.action)
                            contentItem: RowLayout {
                                spacing: 10
                                MaterialSymbol {
                                    Layout.leftMargin: 8
                                    text: item.modelData.icon
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: item.modelData.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: item.modelData.text
                                    color: item.modelData.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
