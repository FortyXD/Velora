import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property string activeWindowAddress: `0x${activeWindow?.HyprlandToplevel?.address}`
    property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == monitor?.name
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)
    readonly property bool showsActiveWindow: !!(root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow)
    readonly property string appClass: showsActiveWindow ? (root.activeWindow?.appId ?? "") : (root.biggestWindow?.class ?? "")
    // Changes when another window or workspace is shown, but not when the title of the same window changes
    readonly property string identity: showsActiveWindow ? root.activeWindowAddress
        : root.biggestWindow ? `${root.biggestWindow.address}` : `ws${monitor?.activeWorkspace?.id ?? 1}`

    implicitWidth: rowLayout.implicitWidth

    onIdentityChanged: if (Config.options.bar.microAnimations) switchAnimation.restart()
    ParallelAnimation {
        id: switchAnimation
        NumberAnimation { target: rowLayout; property: "opacity"; from: 0.25; to: 1; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: rowTranslate; property: "x"; from: 6; to: 0; duration: 260; easing.type: Easing.OutCubic }
    }

    RowLayout {
        id: rowLayout
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8
        transform: Translate { id: rowTranslate }

        Item { // App icon
            Layout.alignment: Qt.AlignVCenter
            visible: root.appClass.length > 0
            implicitWidth: 22
            implicitHeight: 22

            IconImage {
                id: appIcon
                anchors.fill: parent
                source: Quickshell.iconPath(AppSearch.guessIcon(root.appClass), "image-missing")
                implicitSize: 22
            }
            Loader {
                active: Config.options.bar.workspaces.monochromeIcons
                anchors.fill: appIcon
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false // There's already color overlay
                        anchors.fill: parent
                        source: appIcon
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
                    }
                }
            }
        }

        ColumnLayout {
            id: colLayout
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -4

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                text: root.showsActiveWindow ?
                    root.activeWindow?.appId :
                    (root.biggestWindow?.class) ?? Translation.tr("Desktop")

            }

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
                text: root.showsActiveWindow ?
                    root.activeWindow?.title :
                    (root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`
            }
        }
    }
}
