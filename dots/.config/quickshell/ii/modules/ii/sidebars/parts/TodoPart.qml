import QtQuick
import qs.modules.ii.sidebars
import qs.modules.ii.sidebarRight.todo

// Tasks to do and done
SidebarCard {
    focusTarget: widget
    TodoWidget {
        id: widget
        anchors.fill: parent
        anchors.margins: 6
    }
}
