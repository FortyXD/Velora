import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebars
import QtQuick

/**
 * The right sidebar: its parts from SidebarLayout, top to bottom, and the dialogs its quick toggles open.
 */
Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        SidebarPartsColumn {
            id: column
            anchors.fill: parent
            anchors.margins: root.sidebarPadding
            side: "right"
            open: GlobalStates.sidebarRightOpen
            onDialogRequested: name => dialogs.show(name)
            onOpenChanged: if (!open) column.editMode = false
        }
    }

    Keys.onPressed: event => {
        if (event.modifiers === Qt.ControlModifier && (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
            column.cycleTabs(event.key === Qt.Key_PageDown ? 1 : -1);
            event.accepted = true;
        }
    }

    SidebarDialogs {
        id: dialogs
        anchors.fill: parent
        open: GlobalStates.sidebarRightOpen
    }
}
