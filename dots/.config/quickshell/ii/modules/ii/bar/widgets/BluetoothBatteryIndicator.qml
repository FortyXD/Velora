import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Battery of the first connected Bluetooth device that reports one
StyledText {
    id: root
    readonly property var device: BluetoothStatus.connectedDevices.find(device => device.batteryAvailable) ?? null
    readonly property real level: device?.battery ?? 0
    readonly property bool active: Config.options.bar.indicators.bluetoothBattery && device !== null
    property color normalColor: Appearance.colors.colOnLayer0
    leftPadding: 2
    font.pixelSize: Appearance.font.pixelSize.small
    color: root.level < 0.2 ? Appearance.colors.colError : root.normalColor
    text: `${Math.round(root.level * 100)}%`
}
