import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import Quickshell
import qs
import qs.modules.common.widgets

PopupWindow {
    id: root

    ///////////////////// Properties ////////////////////
    required property bool tasksHovered
    property var appEntry
    property var requestedEntry
    property Item anchorItem
    property Item requestedAnchor
    property bool opened: false

    WindowPreviewPool {
        id: previewPool
        active: root.opened && !GlobalStates.screenLocked
        current: root.requestedEntry?.toplevels ?? []
        onDisplayedChanged: root.presentReady()
    }

    function presentReady() {
        if (!previewPool.displayed.length || !previewPool.current.every(window => previewPool.displayed.includes(window))) return;
        root.appEntry = root.requestedEntry;
        root.anchorItem = root.requestedAnchor;
        root.anchor.updateAnchor();
    }

    //////////////////// Functions ////////////////////
    function close() { // Closing doesn't animate, not sure if they're just lazy or it's intentional
        marginBehavior.enabled = false;
        root.opened = false;
    }

    function open() {
        marginBehavior.enabled = true;
        root.opened = true;
    }

    function show(appEntry: var, button: Item) {
        root.requestedAnchor = button;
        root.requestedEntry = appEntry;
        root.open();
        root.presentReady();
    }

    ///////////////////// Internals /////////////////////
    readonly property bool bottom: Config.options.waffles.bar.bottom
    property real visualMargin: 12
    property real ambientShadowWidth: 1

    visible: root.opened && previewPool.displayed.length > 0 && !GlobalStates.screenLocked
    color: "transparent"
    implicitWidth: contentItem.implicitWidth + ambientShadowWidth + (visualMargin * 2)
    implicitHeight: contentItem.implicitHeight + ambientShadowWidth + (visualMargin * 2)
    anchor {
        adjustment: PopupAdjustment.Slide
        item: root.anchorItem
        gravity: bottom ? Edges.Top : Edges.Bottom
        edges: bottom ? Edges.Top : Edges.Bottom
    }

    Timer {
        interval: 250
        running: root.opened && !hoverChecker.containsMouse && !root.tasksHovered
        onTriggered: {
            root.close();
        }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (GlobalStates.screenLocked) root.close(); }
    }

    // Content
    MouseArea {
        id: hoverChecker
        anchors.fill: parent
        hoverEnabled: true

        // Shadow
        WAmbientShadow {
            target: contentItem
        }

        Rectangle {
            id: contentItem
            property real sourceEdgeMargin: root.visible ? (root.ambientShadowWidth + root.visualMargin) : -root.implicitHeight
            Behavior on sourceEdgeMargin {
                id: marginBehavior
                animation: Looks.transition.enter.createObject(this)
            }
            anchors {
                left: parent.left
                right: parent.right
                top: root.bottom ? undefined : parent.top
                bottom: root.bottom ? parent.bottom : undefined
                margins: root.ambientShadowWidth + root.visualMargin
                // Opening anim
                bottomMargin: root.bottom ? sourceEdgeMargin : (root.ambientShadowWidth + root.visualMargin)
                topMargin: root.bottom ? (root.ambientShadowWidth + root.visualMargin) : sourceEdgeMargin
            }
            color: Looks.colors.bg1Base
            radius: Looks.radius.large

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: contentItem.width
                    height: contentItem.height
                    radius: contentItem.radius
                }
            }

            // Testing
            implicitHeight: Math.min(158, windowsRow.implicitHeight)
            implicitWidth: windowsRow.implicitWidth

            RowLayout {
                id: windowsRow
                anchors.fill: parent

                Repeater {
                    model: ScriptModel {
                        values: previewPool.windows
                    }
                    delegate: WindowPreview {
                        required property var modelData
                        visible: previewPool.displayed.includes(modelData)
                        toplevel: modelData
                        preparing: root.opened && previewPool.current.includes(modelData)
                        onReadyChanged: previewPool.setReady(modelData, ready)
                        Component.onCompleted: previewPool.setReady(modelData, ready)
                    }
                }
            }
        }
    }
}
