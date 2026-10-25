import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool barEditing: false // Bar layout edit mode: widgets ignore input while it is on
    property string barEditScreen: "" // Name of the screen whose bar is being edited
    property string barEditSelection: "" // uid of the selected bar widget while editing
    property string barEditHovered: "" // uid of the bar widget under the pointer while editing
    onBarEditingChanged: {
        barEditSelection = "";
        barEditHovered = "";
    }
    onScreenLockedChanged: {
        if (screenLocked) barEditing = false;
        lockExiting = false;
    }
    property bool lockEditorOpen: false // The full-size lock screen editor (modules/ii/lock/LockEditorWindow.qml)
    property bool lockExiting: false // Unlocked: the lock screen plays its way out (lock.animations) before it goes
    property bool crosshairOpen: false
    property bool desktopWidgetEditing: false // A desktop widget needs keyboard input on the background layer
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false

    // Tools and dialogs in a sidebar close whichever sidebar they're in
    function closeSidebars() {
        root.sidebarLeftOpen = false;
        root.sidebarRightOpen = false;
    }

    // Notifications are read once the sidebar showing them opens (the right one, unless they were moved left)
    function markNotificationsRead() {
        Notifications.timeoutAll();
        Notifications.markAllRead();
    }
    onSidebarRightOpenChanged: {
        if (root.sidebarRightOpen && SidebarLayout.sideOf("notifications") !== "left") root.markNotificationsRead();
    }
    onSidebarLeftOpenChanged: {
        if (root.sidebarLeftOpen && SidebarLayout.sideOf("notifications") === "left") root.markNotificationsRead();
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}