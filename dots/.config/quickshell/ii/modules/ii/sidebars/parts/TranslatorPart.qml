import QtQuick
import qs.modules.ii.sidebars
import qs.modules.ii.sidebarLeft

// Translates as you type
SidebarCard {
    focusTarget: widget
    Translator {
        id: widget
        anchors.fill: parent
    }
}
