import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A Bluetooth device in the settings list: its kind, name and state. A saved one connects or disconnects with the
 * button and opens its page on click; a new one pairs and connects on click.
 */
ColumnLayout {
    id: root
    required property string path
    readonly property var device: BluetoothManager.deviceByPath[root.path] ?? null
    readonly property bool saved: root.device?.paired ?? false
    readonly property bool busy: BluetoothManager.busy[root.path] === true
    readonly property string errorText: BluetoothManager.errors[root.path] ?? ""
    readonly property string statusText: root.busy ? (root.saved ? Translation.tr("Connecting…") : Translation.tr("Pairing…"))
        : root.device?.blocked ? Translation.tr("Blocked")
        : root.device?.connected ? Translation.tr("Connected")
        : root.saved ? Translation.tr("Not connected")
        : Translation.tr("Click to pair")
    readonly property string batteryText: (root.device?.battery ?? null) !== null ? Translation.tr("Battery %1%").arg(root.device.battery) : ""

    function primaryAction(): void {
        if (root.saved) BluetoothManager.showDevice(root.path);
        else if (!root.busy) BluetoothManager.pair(root.path, null);
    }

    Layout.fillWidth: true
    spacing: 0

    RippleButton {
        Layout.fillWidth: true
        implicitHeight: 56
        leftPadding: 12
        rightPadding: 8
        buttonRadius: Appearance.rounding.small
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: root.primaryAction()

        contentItem: RowLayout {
            spacing: 12

            ConfigIconTile {
                icon: BluetoothManager.typeSymbol(root.device?.deviceType ?? "")
                active: root.device?.connected ?? false
                iconSize: 22
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: root.device?.fullName ?? ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.errorText.length > 0 ? Appearance.colors.colError : Appearance.colors.colSubtext
                    text: root.errorText || [root.statusText, BluetoothManager.typeLabel(root.device?.deviceType ?? ""), root.batteryText].filter(part => part.length > 0).join(" · ")
                }
            }
            StatusIcon {
                visible: root.busy
                text: ""
                iconSize: 18
                color: Appearance.colors.colSubtext
                busy: root.busy
            }
            DialogButton {
                visible: root.saved && !root.busy && !(root.device?.blocked ?? false)
                buttonText: root.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                onClicked: root.device.connected ? BluetoothManager.disconnectDevice(root.path) : BluetoothManager.connectDevice(root.path)
            }
            DialogButton {
                visible: !root.saved && root.busy
                buttonText: Translation.tr("Cancel")
                onClicked: BluetoothManager.cancelPairing(root.path)
            }
            MaterialSymbol {
                visible: root.saved
                text: "chevron_right"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }
        }
    }
}
