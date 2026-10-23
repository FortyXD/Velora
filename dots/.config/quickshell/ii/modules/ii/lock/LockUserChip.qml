import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar

/**
 * User name and keyboard layout (lock.showUser, lock.showKeyboardLayout).
 * With `liveData` off (the settings app) the layout is an example.
 */
Toolbar {
    id: root
    property bool liveData: true
    readonly property bool showUser: Config.options.lock.showUser
    readonly property bool showLayout: Config.options.lock.showKeyboardLayout
    readonly property bool hasContent: root.showUser || root.showLayout

    LockIconText {
        visible: root.showUser
        Layout.leftMargin: 8
        icon: "account_circle"
        text: SystemInfo.username
    }

    // Keyboard layout (Xkb)
    Loader {
        Layout.leftMargin: root.showUser ? 0 : 10
        Layout.rightMargin: 8
        Layout.fillHeight: true
        active: root.showLayout
        visible: active

        sourceComponent: Row {
            spacing: 8
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                fill: 1
                text: "keyboard_alt"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.liveData ? HyprlandXkb.currentLayoutCode : "us"
                color: Appearance.colors.colOnSurfaceVariant
                animateChange: true
            }
        }
    }

    // Keyboard layout (Fcitx); the tray only exists in the shell
    Loader {
        Layout.rightMargin: 10
        Layout.alignment: Qt.AlignVCenter
        active: root.liveData && root.showLayout
        visible: (item?.pinnedItems.length ?? 0) > 0
        sourceComponent: Bar.SysTray {
            showSeparator: false
            showOverflowMenu: false
            pinnedItems: SystemTray.items.values.filter(i => i.id == "Fcitx")
        }
    }
}
