import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The lock screen at full size, to see it and arrange it: drag parts, pick an arrangement, play the
 * animations. Nothing is locked and no password is asked. IPC: `lockEditor open|close|toggle`
 * (the settings app opens it); Esc closes it.
 */
Scope {
    id: root
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    component Separator: Rectangle {
        Layout.fillHeight: true
        Layout.topMargin: 8
        Layout.bottomMargin: 8
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        implicitWidth: 1
        color: Appearance.colors.colOutlineVariant
    }

    IpcHandler {
        target: "lockEditor"
        function open(): void {
            if (!GlobalStates.screenLocked) GlobalStates.lockEditorOpen = true;
        }
        function close(): void {
            GlobalStates.lockEditorOpen = false;
        }
        function toggle(): void {
            GlobalStates.lockEditorOpen = !GlobalStates.lockEditorOpen && !GlobalStates.screenLocked;
        }
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) GlobalStates.lockEditorOpen = false;
        }
    }

    Loader {
        active: GlobalStates.lockEditorOpen
        sourceComponent: PanelWindow {
            id: editorWindow
            screen: root.focusedScreen
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:lockEditor"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "black"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            property bool editing: true

            function close() {
                GlobalStates.lockEditorOpen = false;
            }
            function clockFrom() {
                const from = LockLayout.desktopClocks[editorWindow.screen?.name ?? ""];
                return from && from.visible ? Qt.rect(from.x, from.y, from.width, from.height) : null;
            }
            function replay() {
                scene.exiting = false;
                scene.playEntrance(editorWindow.clockFrom());
            }
            // Out as on unlock, then in again
            function playUnlock() {
                scene.exiting = true;
                replayTimer.restart();
            }
            Timer {
                id: replayTimer
                interval: 900
                onTriggered: editorWindow.replay()
            }

            Component.onCompleted: Qt.callLater(editorWindow.replay)

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        editorWindow.close();
                        event.accepted = true;
                        return;
                    }
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z) {
                        LockLayout.undo();
                        event.accepted = true;
                        return;
                    }
                    // Arrows nudge the selected part
                    const id = scene.selectedId;
                    if (id.length === 0) return;
                    const step = (event.modifiers & Qt.ShiftModifier) ? 0.0025 : 0.01;
                    const item = LockLayout.items[id];
                    const host = scene.host(id);
                    const x = host.center.x / scene.width;
                    const y = host.center.y / scene.height;
                    if (event.key === Qt.Key_Left) LockLayout.move(id, x - step, y);
                    else if (event.key === Qt.Key_Right) LockLayout.move(id, x + step, y);
                    else if (event.key === Qt.Key_Up) LockLayout.move(id, x, y - step);
                    else if (event.key === Qt.Key_Down) LockLayout.move(id, x, y + step);
                    else return;
                    event.accepted = true;
                }

                LockScene {
                    id: scene
                    anchors.fill: parent
                    liveData: true
                    showBackdrop: true
                    playVideo: true
                    startHidden: true
                    editing: editorWindow.editing
                    onElementMoved: (id, x, y) => LockLayout.move(id, x, y)
                    onElementRemoved: id => LockLayout.setShown(id, false)
                    onElementReset: id => LockLayout.resetItem(id)
                }

                // Tools, at the top
                ColumnLayout {
                    id: tools
                    anchors {
                        top: parent.top
                        horizontalCenter: parent.horizontalCenter
                        topMargin: 16
                    }
                    spacing: 8
                    z: 10

                    Toolbar {
                        Layout.alignment: Qt.AlignHCenter
                        StyledText {
                            Layout.leftMargin: 12
                            Layout.rightMargin: 6
                            text: Translation.tr("Lock screen")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }
                        Repeater {
                            model: LockLayout.presets
                            delegate: IconToolbarButton {
                                required property var modelData
                                text: modelData.icon
                                toggled: LockLayout.matchesPreset(modelData.id)
                                onClicked: LockLayout.applyPreset(modelData.id)
                                StyledToolTip {
                                    text: modelData.name
                                }
                            }
                        }
                        Separator {}
                        IconToolbarButton {
                            text: "undo"
                            enabled: LockLayout.canUndo
                            onClicked: LockLayout.undo()
                            StyledToolTip {
                                text: Translation.tr("Undo (Ctrl+Z)")
                            }
                        }
                        IconToolbarButton {
                            text: "restart_alt"
                            onClicked: LockLayout.reset()
                            StyledToolTip {
                                text: Translation.tr("Back to the built-in arrangement")
                            }
                        }
                        Separator {}
                        IconToolbarButton {
                            text: editorWindow.editing ? "visibility" : "edit"
                            onClicked: {
                                editorWindow.editing = !editorWindow.editing;
                                scene.selectElement("");
                            }
                            StyledToolTip {
                                text: editorWindow.editing ? Translation.tr("See it as it will be") : Translation.tr("Arrange")
                            }
                        }
                        IconToolbarButton {
                            text: "play_arrow"
                            onClicked: editorWindow.replay()
                            StyledToolTip {
                                text: Translation.tr("Play the locking animation")
                            }
                        }
                        IconToolbarButton {
                            text: "lock_open"
                            onClicked: editorWindow.playUnlock()
                            StyledToolTip {
                                text: Translation.tr("Play the unlocking animation")
                            }
                        }
                        Separator {}
                        RippleButton {
                            implicitHeight: 40
                            leftPadding: 16
                            rightPadding: 16
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: editorWindow.close()
                            contentItem: StyledText {
                                text: Translation.tr("Done")
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }

                    // What's shown: one chip per part
                    Toolbar {
                        Layout.alignment: Qt.AlignHCenter
                        visible: editorWindow.editing
                        Repeater {
                            model: LockElementCatalog.elements.filter(element => element.hideable)
                            delegate: IconToolbarButton {
                                required property var modelData
                                text: modelData.icon
                                toggled: LockLayout.items[modelData.id].show
                                onClicked: LockLayout.setShown(modelData.id, !LockLayout.items[modelData.id].show)
                                StyledToolTip {
                                    text: `${modelData.name}: ${LockLayout.items[modelData.id].show ? Translation.tr("shown") : Translation.tr("hidden")}`
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: editorWindow.editing
                        text: Translation.tr("Drag parts to move them • Arrows nudge the selected one • Double-click puts it back • Esc closes")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                        style: Text.Raised
                        styleColor: ColorUtils.transparentize(Appearance.colors.colShadow, 0.4)
                    }
                }
            }
        }
    }
}
