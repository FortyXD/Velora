import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebars
import QtQuick

/**
 * The left sidebar: its parts from SidebarLayout, top to bottom, and the dialogs its quick toggles open.
 * The window around it (SidebarLeft.qml) widens, pins and detaches it.
 */
Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent

    function focusActiveItem() {
        column.focusMain();
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (!GlobalStates.sidebarLeftOpen) {
                column.editMode = false;
                return;
            }
            column.snap();
            Qt.callLater(column.focusMain); // Typing goes to the shown tab (the chat's input)
        }
    }

    Keys.onPressed: event => {
        if (event.modifiers === Qt.ControlModifier && (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
            column.cycleTabs(event.key === Qt.Key_PageDown ? 1 : -1);
            event.accepted = true;
        }
    }

    SidebarPartsColumn {
        id: column
        anchors.fill: parent
        anchors.margins: root.sidebarPadding
        side: "left"
        open: GlobalStates.sidebarLeftOpen
        onDialogRequested: name => dialogs.show(name)
    }

    SidebarDialogs {
        id: dialogs
        anchors.fill: parent
        open: GlobalStates.sidebarLeftOpen
    }
}
