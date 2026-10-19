import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Bluetooth state, for adapters that are present
MaterialSymbol {
    readonly property bool active: BluetoothStatus.available
    text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
    iconSize: Appearance.font.pixelSize.larger
    color: Appearance.colors.colOnLayer0
}
