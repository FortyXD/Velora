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
            reveal: Audio.sink?.audio?.muted ?? false
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            Behavior on Layout.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MaterialSymbol {
                text: "volume_off"
                iconSize: Appearance.font.pixelSize.larger
                color: root.colText
            }
        }
        Revealer {
            reveal: Audio.source?.audio?.muted ?? false
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            Behavior on Layout.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MaterialSymbol {
                text: "mic_off"
                iconSize: Appearance.font.pixelSize.larger
                color: root.colText
            }
        }
        HyprlandXkbIndicator {
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: indicatorsRowLayout.realSpacing
            color: root.colText
        }
        Revealer {
            reveal: Notifications.silent || Notifications.unread > 0
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
        MaterialSymbol {
            text: Network.materialSymbol
            iconSize: Appearance.font.pixelSize.larger
            color: root.colText
        }
        MaterialSymbol {
            Layout.leftMargin: indicatorsRowLayout.realSpacing
            visible: BluetoothStatus.available
            text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            iconSize: Appearance.font.pixelSize.larger
            color: root.colText
        }
        Revealer { // Battery of the first connected Bluetooth device that reports one
            id: bluetoothBattery
            readonly property var device: BluetoothStatus.connectedDevices.find(device => device.batteryAvailable) ?? null
            readonly property real level: device?.battery ?? 0
            reveal: Config.options.bar.indicators.bluetoothBattery && device !== null
            Layout.alignment: Qt.AlignVCenter
            StyledText {
                leftPadding: 2
                font.pixelSize: Appearance.font.pixelSize.small
                color: bluetoothBattery.level < 0.2 ? Appearance.colors.colError : root.colText
                text: `${Math.round(bluetoothBattery.level * 100)}%`
            }
        }
    }
}
