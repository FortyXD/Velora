import QtQuick
import qs.modules.ii.sidebars
import qs.modules.ii.sidebarRight.pomodoro

// Pomodoro, stopwatch and countdown
SidebarCard {
    focusTarget: widget
    PomodoroWidget {
        id: widget
        anchors.fill: parent
        anchors.margins: 6
    }
}
