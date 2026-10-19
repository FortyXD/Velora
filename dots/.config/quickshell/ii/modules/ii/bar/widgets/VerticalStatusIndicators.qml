import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts

/**
 * StatusIndicators for a vertical bar: the same icons stacked in a column.
 */
RippleButton {
    id: root

    property bool zoneHovered: false
    property var options: ({})
    function shows(key) {
        return root.options[key] !== false;
    }

    implicitHeight: indicatorsColumnLayout.implicitHeight + 4 * 2
    implicitWidth: indicatorsColumnLayout.implicitWidth + 6 * 2

    buttonRadius: Appearance.rounding.full
    colBackground: root.zoneHovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarRightOpen
    property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0

    Behavior on colText {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen

    ColumnLayout {
        id: indicatorsColumnLayout
        anchors.centerIn: parent
        property real realSpacing: 6
        spacing: 0

        Revealer {
            vertical: true
            reveal: root.shows("showAudioMuted") && audioMuted.active
            Layout.fillWidth: true
            Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            AudioMutedIndicator {
                id: audioMuted
                color: root.colText
            }
        }
        Revealer {
            vertical: true
            reveal: root.shows("showMicMuted") && micMuted.active
            Layout.fillWidth: true
            Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MicMutedIndicator {
                id: micMuted
                color: root.colText
            }
        }
        HyprlandXkbIndicator {
            vertical: true
            visible: active && root.shows("showKeyboardLayout")
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: indicatorsColumnLayout.realSpacing
            color: root.colText
        }
        Revealer {
            vertical: true
            reveal: root.shows("showNotifications") && (Notifications.silent || Notifications.unread > 0)
            Layout.fillWidth: true
            Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
            implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
            implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            NotificationUnreadCount {
                id: notificationUnreadCount
                color: root.colText
            }
        }
        NetworkIndicator {
            visible: root.shows("showNetwork")
            Layout.alignment: Qt.AlignHCenter
            color: root.colText
        }
        BluetoothIndicator {
            Layout.topMargin: indicatorsColumnLayout.realSpacing
            Layout.alignment: Qt.AlignHCenter
            visible: active && root.shows("showBluetooth")
            color: root.colText
        }
    }
}
