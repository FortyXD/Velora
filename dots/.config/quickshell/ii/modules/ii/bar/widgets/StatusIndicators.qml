import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts

/**
 * Right sidebar button holding the status icons: muted speaker and microphone, keyboard layout,
 * notifications, network, Bluetooth and the battery of a connected Bluetooth device.
 */
RippleButton {
    id: root

    property bool zoneHovered: false
    property var options: ({})
    function shows(key) {
        return root.options[key] !== false;
    }

    implicitWidth: indicatorsRowLayout.implicitWidth + 10 * 2
    implicitHeight: indicatorsRowLayout.implicitHeight + 5 * 2

    buttonRadius: Appearance.rounding.full
    colBackground: root.zoneHovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarRightOpen
    scale: down && Config.options.bar.microAnimations ? 0.95 : 1
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0

    Behavior on colText {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    onPressed: {
        GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
    }

    RowLayout {
        id: indicatorsRowLayout
        anchors.centerIn: parent
        property real realSpacing: 15
        spacing: 0

        Revealer {
            reveal: root.shows("showAudioMuted") && audioMuted.active
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            Behavior on Layout.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            AudioMutedIndicator {
                id: audioMuted
                color: root.colText
            }
        }
        Revealer {
            reveal: root.shows("showMicMuted") && micMuted.active
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            Behavior on Layout.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MicMutedIndicator {
                id: micMuted
                color: root.colText
            }
        }
        HyprlandXkbIndicator {
            visible: active && root.shows("showKeyboardLayout")
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: indicatorsRowLayout.realSpacing
            color: root.colText
        }
        Revealer {
            reveal: root.shows("showNotifications") && (Notifications.silent || Notifications.unread > 0)
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
            implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
            Behavior on Layout.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            NotificationUnreadCount {
                id: notificationUnreadCount
                color: root.colText
            }
        }
        NetworkIndicator {
            visible: root.shows("showNetwork")
            color: root.colText
        }
        BluetoothIndicator {
            id: bluetooth
            Layout.leftMargin: indicatorsRowLayout.realSpacing
            visible: active && root.shows("showBluetooth")
            color: root.colText
        }
        Revealer {
            reveal: bluetoothBattery.active && root.shows("showBluetooth")
            Layout.alignment: Qt.AlignVCenter
            BluetoothBatteryIndicator {
                id: bluetoothBattery
                normalColor: root.colText
            }
        }
    }
}
