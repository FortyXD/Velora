import QtQuick
import qs.modules.ii.sidebars
import qs.modules.ii.overlay.notes

// A scratchpad that saves as you type: the same notes as on the overlay
SidebarCard {
    id: root
    focusTarget: focusProxy

    Item {
        id: focusProxy
        onActiveFocusChanged: if (activeFocus) notes.focusAtEnd()
    }
    NotesContent {
        id: notes
        color: "transparent"
    }
}
