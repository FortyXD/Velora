import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar.edit

Scope {
    id: bar
    property bool showBarBackground: Config.options.bar.showBackground

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        LazyLoader {
            id: barLoader
            property bool recreating: false
            active: GlobalStates.barOpen && !GlobalStates.screenLocked && !recreating
            readonly property bool glass: Config.options.bar.style.glass
            onGlassChanged: {
                recreating = true;
                Qt.callLater(() => recreating = false);
            }
            required property ShellScreen modelData
            component: PanelWindow { // Bar window
                id: barRoot
                screen: barLoader.modelData

                property var brightnessMonitor: Brightness.getMonitorForScreen(barLoader.modelData)
                
                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: {
                        barRoot.superShow = true
                    }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
                        if (GlobalStates.superDown) showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            barRoot.superShow = false;
                        }
                    }
                }
                property bool superShow: false
                readonly property bool editingHere: GlobalStates.barEditing && GlobalStates.barEditScreen === barRoot.screen?.name
                property bool mustShow: hoverRegion.containsMouse || superShow || editingHere
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: (Config?.options.bar.autoHide.enable && (!mustShow || !Config?.options.bar.autoHide.pushWindows)) ? 0 :
                    Appearance.sizes.baseVerticalBarWidth + (Appearance.sizes.barFloating ? Appearance.sizes.barFloatMargin : 0)
                WlrLayershell.namespace: Config.options.bar.style.glass ? "quickshell:barGlass" : "quickshell:verticalBar"
                // WlrLayershell.layer: WlrLayer.Overlay // TODO enable this when bar can hide when fullscreen
                implicitWidth: Appearance.sizes.verticalBarWidth + Appearance.rounding.screenRounding
                    + (editingHere ? editDrawerLoader.width + 16 : 0)
                // While editing, the drawer beside the bar takes input too
                property Region barMask: Region {
                    item: hoverMaskRegion
                }
                mask: editingHere ? null : barMask
                WlrLayershell.keyboardFocus: editingHere ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                color: "transparent"

                // Positioning
                anchors {
                    left: !Config.options.bar.bottom
                    right: Config.options.bar.bottom
                    top: true
                    bottom: true
                }

                // Include in focus grab
                Component.onCompleted: {
                    GlobalFocusGrab.addPersistent(barRoot);
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
                }

                MouseArea  {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors.fill: parent

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            leftMargin: -Config.options.bar.autoHide.hoverRegionWidth
                            rightMargin: -Config.options.bar.autoHide.hoverRegionWidth
                        }
                    }

                    VerticalBarContent {
                        id: barContent
                        editing: barRoot.editingHere
                        controller: editController
                        
                        implicitWidth: Appearance.sizes.verticalBarWidth
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: parent.left
                            right: undefined
                            leftMargin: (Config?.options.bar.autoHide.enable && !mustShow) ? -Appearance.sizes.verticalBarWidth : 0
                            rightMargin: 0
                        }
                        Behavior on anchors.leftMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "right"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: undefined
                                    right: parent.right
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.rightMargin: (Config?.options.bar.autoHide.enable && !mustShow) ? -Appearance.sizes.barHeight : 0
                            }
                        }
                    }

                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: barContent.right
                            right: undefined
                        }
                        width: Appearance.rounding.screenRounding
                        active: showBarBackground && Config.options.bar.cornerStyle === 0 && !Config.options.bar.style.islands // Hug

                        states: State {
                            name: "right"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: undefined
                                    right: barContent.left
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: topCorner
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }

                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colBarBackground : "transparent"

                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        topCorner.corner: RoundCorner.CornerEnum.TopRight
                                    }
                                }
                            }
                            RoundCorner {
                                id: bottomCorner
                                anchors {
                                    bottom: parent.bottom
                                    left: !Config.options.bar.bottom ? parent.left : undefined
                                    right: Config.options.bar.bottom ? parent.right : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colBarBackground : "transparent"

                                corner: RoundCorner.CornerEnum.BottomLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        bottomCorner.corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }

                    Loader {
                        id: editDrawerLoader
                        active: barRoot.editingHere
                        width: 420
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            topMargin: 8
                            bottomMargin: 8
                            left: Config.options.bar.bottom ? undefined : barContent.right
                            right: Config.options.bar.bottom ? barContent.left : undefined
                            leftMargin: Appearance.rounding.screenRounding + 4
                            rightMargin: Appearance.rounding.screenRounding + 4
                        }
                        sourceComponent: BarEditDrawer {
                            view: barContent
                            controller: editController
                        }
                    }

                    BarEditController {
                        id: editController
                        view: barContent
                    }
                }
            }
        }
    }

}
