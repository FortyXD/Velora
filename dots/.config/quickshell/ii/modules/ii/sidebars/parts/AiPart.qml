import QtQuick
import qs.modules.ii.sidebars
import qs.modules.ii.sidebarLeft

// Chat with an assistant
SidebarCard {
    focusTarget: widget
    AiChat {
        id: widget
        anchors.fill: parent
    }
}
