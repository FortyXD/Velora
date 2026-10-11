pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

/**
 * Miniature of a workspace: the wallpaper with captures of its windows where they sit.
 * Click a window to focus it, or anywhere else to switch to the workspace.
 *
 * Cheap on purpose: when the preview opens, every window of the shown workspaces is captured once
 * (a single frame, ~80 ms for all of them), so moving between workspaces is instant. Only the windows on
 * display are refreshed, once a second, instead of being captured live. The wallpaper is decoded once
 * at a small size and kept. Windows show their app icon until their first frame arrives.
 */
StyledPopup {
    id: root
    interactive: true
    openDelay: 220

    property int workspaceId: 0
    // Windows of these workspaces are captured up front
    property int firstWorkspace: 1
    property int lastWorkspace: 10

    readonly property var windows: HyprlandData.windowList.filter(win => win.workspace.id === workspaceId)
    readonly property var monitorData: HyprlandData.monitors.find(mon => mon.id === windows[0]?.monitor) ?? HyprlandData.monitors[0]
    readonly property bool rotated: (monitorData?.transform ?? 0) % 2 === 1
    readonly property real monitorWidth: ((rotated ? monitorData?.height : monitorData?.width) ?? 1920) / (monitorData?.scale ?? 1)
    readonly property real monitorHeight: ((rotated ? monitorData?.width : monitorData?.height) ?? 1080) / (monitorData?.scale ?? 1)
    readonly property real previewWidth: 340
    readonly property real previewScale: previewWidth / monitorWidth
    property string hoveredTitle: ""
    onWorkspaceIdChanged: hoveredTitle = ""

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                Layout.fillWidth: true
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurfaceVariant
                text: Translation.tr("Workspace %1").arg(Config.options.bar.workspaces.numberMap[root.workspaceId - 1] || root.workspaceId)
            }
            MaterialSymbol {
                text: "select_window"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: root.windows.length
            }
        }

        Rectangle { // The screen; its size is known up front, so the popup opens at its final size
            id: screen
            implicitWidth: root.previewWidth
            implicitHeight: Math.round(root.monitorHeight * root.previewScale)
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: screen.width
                    height: screen.height
                    radius: screen.radius
                }
            }

            Image { // Lives as long as the bar, so it's decoded once instead of on every open
                anchors.fill: parent
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(root.previewWidth * 2, Math.round(root.monitorHeight * root.previewScale) * 2)
                source: Config.options.background.wallpaperPath
            }

            MouseArea { // Empty space switches to the workspace
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Hyprland.dispatch(`hl.dsp.focus({ workspace = ${root.workspaceId} })`);
                    root.wanted = false;
                }
            }

            Loader {
                anchors.fill: parent
                active: root.active

                sourceComponent: Item {
                    Repeater {
                        model: ScriptModel {
                            values: ToplevelManager.toplevels.values.filter(toplevel => {
                                const workspace = HyprlandData.windowByAddress[`0x${toplevel.HyprlandToplevel?.address}`]?.workspace?.id ?? 0;
                                return workspace >= root.firstWorkspace && workspace <= root.lastWorkspace;
                            })
                        }
                        delegate: Item {
                            id: windowItem
                            required property var modelData
                            readonly property var windowData: HyprlandData.windowByAddress[`0x${modelData.HyprlandToplevel?.address}`]
                            readonly property var monitor: HyprlandData.monitors.find(mon => mon.id === windowData?.monitor) ?? root.monitorData
                            readonly property bool shown: (windowData?.workspace?.id ?? 0) === root.workspaceId
                            visible: shown
                            x: ((windowData?.at[0] ?? 0) - (monitor?.x ?? 0)) * root.previewScale
                            y: ((windowData?.at[1] ?? 0) - (monitor?.y ?? 0)) * root.previewScale
                            width: (windowData?.size[0] ?? 0) * root.previewScale
                            height: (windowData?.size[1] ?? 0) * root.previewScale
                            z: windowData?.floating ? 2 : 1

                            Rectangle { // Shown until the capture has a frame
                                anchors.fill: parent
                                radius: 3
                                color: Appearance.colors.colLayer1
                                visible: !capture.hasContent
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: Math.min(28, parent.width * 0.5, parent.height * 0.5)
                                    source: Quickshell.iconPath(AppSearch.guessIcon(windowItem.windowData?.class), "image-missing")
                                }
                            }
                            ScreencopyView {
                                id: capture
                                anchors.fill: parent
                                captureSource: windowItem.modelData
                                live: false // One frame on creation, then refreshed by the timer below
                            }
                            Timer { // Keep the windows on display from looking frozen, at a tiny cost
                                interval: 1000
                                repeat: true
                                running: windowItem.shown && capture.hasContent
                                onTriggered: capture.captureFrame()
                            }
                            Rectangle { // Hover outline
                                anchors.fill: parent
                                color: "transparent"
                                radius: 3
                                border.width: windowMouseArea.containsMouse ? 2 : 0
                                border.color: Appearance.colors.colPrimary
                            }
                            MouseArea {
                                id: windowMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: {
                                    if (containsMouse) root.hoveredTitle = windowItem.windowData?.title ?? "";
                                    else if (root.hoveredTitle === (windowItem.windowData?.title ?? "")) root.hoveredTitle = "";
                                }
                                onClicked: {
                                    if (windowItem.windowData) Hyprland.dispatch(`hl.dsp.focus({ window = "address:${windowItem.windowData.address}" })`);
                                    root.wanted = false;
                                }
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: root.previewWidth
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: root.hoveredTitle.length > 0 ? root.hoveredTitle : Translation.tr("Click a window to open it")
        }
    }
}
