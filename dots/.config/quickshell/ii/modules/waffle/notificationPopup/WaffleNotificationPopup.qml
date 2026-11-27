import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.notificationCenter

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
            left: NotificationPreferences.left
            bottom: true
        }

        mask: Region {
            item: popupBounds
        }

        color: "transparent"
        implicitWidth: listview.implicitWidth

        WListView {
            id: listview
            objectName: "notificationPopupList"
            anchors.fill: parent
            leftMargin: 16
            rightMargin: 16
            topMargin: 16
            bottomMargin: 16

            verticalLayoutDirection: NotificationPreferences.top ? ListView.TopToBottom : ListView.BottomToTop
            
            implicitWidth: 396
            spacing:12

            model: ScriptModel {
                values: Notifications.popupList.slice().reverse()
            }
            delegate: WSingleNotification {
                required property var modelData
                notification: modelData
                width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
            }
        }
        Item {
            id: popupBounds
            width: listview.width
            height: Math.min(listview.height, Math.max(0, listview.contentHeight) + listview.topMargin + listview.bottomMargin)
            y: NotificationPreferences.top ? 0 : listview.height - height
        }
    }
}
