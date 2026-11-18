import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        objectName: "notificationPopupWindow"
        visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        anchors {
            top: true
            right: NotificationPreferences.right
            left: !NotificationPreferences.right
            bottom: true
        }

        mask: Region {
            item: popupBounds
        }

        color: "transparent"
        implicitWidth: Appearance.sizes.notificationPopupWidth

        NotificationListView {
            id: listview
            objectName: "notificationPopupList"
            anchors {
                top: parent.top
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                topMargin: 4
                bottomMargin: 4
            }
            implicitWidth: parent.width - Appearance.sizes.elevationMargin * 2
            popup: true
            verticalLayoutDirection: NotificationPreferences.top ? ListView.TopToBottom : ListView.BottomToTop
        }
        Item {
            id: popupBounds
            x: listview.x
            y: listview.y + (NotificationPreferences.top ? 0 : listview.height - height)
            width: listview.width
            height: Math.min(listview.height, Math.max(0, listview.contentHeight))
        }
    }
}
