import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    visible: Updates.veloraAvailable
    implicitWidth: 20
    implicitHeight: 20
    Accessible.name: Translation.tr("Velora update available")
    onClicked: Quickshell.execDetached(["env", "QS_SETTINGS_PAGE=updates", "qs", "-p", Quickshell.shellPath("settings.qml")])
    contentItem: Item {
        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Appearance.colors.colPrimary }
    }
    StyledToolTip { text: Translation.tr("Velora update available") }
}
