import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A Bluetooth device in the settings list. Paired ones connect or disconnect with the button and open
 * their options (reconnect by itself, forget) on click; new ones pair and connect on click.
 */
ColumnLayout {
    id: root
    required property BluetoothDevice device
    property bool expanded: false
    readonly property bool busy: root.device.pairing || root.device.state === BluetoothDeviceState.Connecting
        || root.device.state === BluetoothDeviceState.Disconnecting
    readonly property bool failed: BluetoothStatus.pairingFailedAddress === root.device.address
    readonly property string displayName: root.device.name || root.device.deviceName || Translation.tr("Unknown device")

    Layout.fillWidth: true
    spacing: 0

    RippleButton {
        id: rowButton
        Layout.fillWidth: true
        implicitHeight: 56
        leftPadding: 12
        rightPadding: 8
        buttonRadius: Appearance.rounding.small
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: {
            if (root.device.paired) root.expanded = !root.expanded;
            else if (!root.busy) BluetoothStatus.pairAndConnect(root.device);
        }

        contentItem: RowLayout {
            spacing: 12

            ConfigIconTile {
                icon: Icons.getBluetoothDeviceMaterialSymbol(root.device.icon || "")
                active: root.device.connected
                iconSize: 22
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: root.displayName
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
                    text: root.device.pairing ? Translation.tr("Pairing…")
                        : root.device.state === BluetoothDeviceState.Connecting ? Translation.tr("Connecting…")
                        : root.device.state === BluetoothDeviceState.Disconnecting ? Translation.tr("Disconnecting…")
                        : root.failed ? Translation.tr("Couldn't pair. Put the device in pairing mode and try again.")
                        : root.device.connected ? (root.device.batteryAvailable
                            ? Translation.tr("Connected · %1% battery").arg(Math.round(root.device.battery * 100))
                            : Translation.tr("Connected"))
                        : root.device.paired ? Translation.tr("Not connected")
                        : Translation.tr("Click to pair")
                }
            }

            MaterialSymbol {
                visible: root.busy
                text: "progress_activity"
                iconSize: 18
                color: Appearance.colors.colSubtext
                RotationAnimation on rotation {
                    running: root.busy
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                }
            }

            DialogButton {
                visible: root.device.paired && !root.busy
                buttonText: root.device.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                onClicked: {
                    if (root.device.connected) root.device.disconnect();
                    else root.device.connect();
                }
            }

            MaterialSymbol {
                visible: root.device.paired
                text: "keyboard_arrow_down"
                iconSize: 20
                color: Appearance.colors.colSubtext
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    // Options of a paired device
    RowLayout {
        visible: root.expanded && root.device.paired
        Layout.fillWidth: true
        Layout.leftMargin: 50
        Layout.rightMargin: 8
        Layout.bottomMargin: 8
        spacing: 8

        StyledSwitch {
            checkable: false
            checked: root.device.trusted
            onClicked: root.device.trusted = !root.device.trusted
        }
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Connect by itself when it's nearby")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer2
        }
        ForgetButton {
            label: Translation.tr("Forget this device")
            onConfirmed: BluetoothStatus.forget(root.device)
        }
    }
}
