import QtQuick
import qs.modules.ii.sidebars
import qs.modules.ii.sidebarRight.calendar

// The month at a glance
SidebarCard {
    focusTarget: widget
    CalendarWidget {
        id: widget
        anchors.fill: parent
        anchors.margins: 6
    }
}
