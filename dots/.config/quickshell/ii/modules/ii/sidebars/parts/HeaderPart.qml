import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.quickToggles.classicStyle

/**
 * Uptime and the edit, reload, settings and power buttons (options: showUptime, buttons).
 * "Edit" arranges the quick toggles of the same sidebar, so it's there only with tiles.
 */
Item {
    id: root
    property Item host: null
    readonly property var options: root.host?.options ?? {}
    readonly property var buttons: root.options.buttons ?? SidebarCatalog.headerButtons.map(button => button.id)
    readonly property bool canEdit: (root.host?.column?.hasToggles ?? false) && Config.options.sidebar.quickToggles.style === "android"

    implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight) + 5

    Rectangle {
        id: uptimeContainer
        visible: root.options.showUptime ?? true
        anchors {
            top: parent.top
            topMargin: 5
            bottom: parent.bottom
            left: parent.left
        }
        color: Appearance.colors.colLayer1
        radius: height / 2
        implicitWidth: uptimeRow.implicitWidth + 24
        implicitHeight: uptimeRow.implicitHeight + 8

        Row {
            id: uptimeRow
            anchors.centerIn: parent
            spacing: 8
            CustomIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 25
                height: 25
                source: SystemInfo.distroIcon
                colorize: true
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Up %1").arg(DateTime.uptime)
                textFormat: Text.MarkdownText
            }
        }
    }

    ButtonGroup {
        id: systemButtonsRow
        anchors {
            top: parent.top
            topMargin: 5
            bottom: parent.bottom
            right: parent.right
        }
        color: Appearance.colors.colLayer1
        padding: 4

        QuickToggleButton {
            toggled: root.host?.column?.editMode ?? false
            visible: root.canEdit && root.buttons.includes("edit")
            buttonIcon: "edit"
            onClicked: root.host.column.editMode = !root.host.column.editMode
            StyledToolTip {
                text: Translation.tr("Edit quick toggles") + ((root.host?.column?.editMode ?? false) ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
            }
        }
        QuickToggleButton {
            toggled: false
            visible: root.buttons.includes("reload")
            buttonIcon: "restart_alt"
            onClicked: {
                Quickshell.execDetached(HyprlandSettings.reloadCommand);
                Quickshell.reload(true);
            }
            StyledToolTip {
                text: Translation.tr("Reload Hyprland & Quickshell")
            }
        }
        QuickToggleButton {
            toggled: false
            visible: root.buttons.includes("settings")
            buttonIcon: "settings"
            onClicked: {
                GlobalStates.closeSidebars();
                Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]);
            }
            StyledToolTip {
                text: Translation.tr("Settings")
            }
        }
        QuickToggleButton {
            toggled: false
            visible: root.buttons.includes("session")
            buttonIcon: "power_settings_new"
            onClicked: GlobalStates.sessionOpen = true
            StyledToolTip {
                text: Translation.tr("Session")
            }
        }
    }
}
