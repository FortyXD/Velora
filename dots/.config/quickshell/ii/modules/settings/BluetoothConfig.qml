import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.network

ContentPage {
    id: page
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool isOn: BluetoothStatus.enabled
    // Devices that only report an address are kept apart; they are rarely what you're looking for
    readonly property var namedNearby: BluetoothStatus.unpairedDevices.filter(device => device.name && device.name !== device.address.replace(/:/g, "-"))
    readonly property var unnamedNearby: BluetoothStatus.unpairedDevices.filter(device => !page.namedNearby.includes(device))
    property bool showUnnamed: false

    // Looks for devices only while the page is on screen
    readonly property bool searching: page.pageShown && page.isOn
    onSearchingChanged: BluetoothStatus.setDiscovering(page.searching)
    Component.onCompleted: BluetoothStatus.setDiscovering(page.searching)
    Component.onDestruction: BluetoothStatus.setDiscovering(false)

    ConnectionHeader {
        icon: !page.isOn ? "bluetooth_disabled" : BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth"
        iconColor: page.heroColor
        title: Translation.tr("Bluetooth")
        subtitle: !BluetoothStatus.available ? Translation.tr("No Bluetooth adapter found")
            : !page.isOn ? Translation.tr("Off")
            : BluetoothStatus.connectedDevices.length > 0 ? BluetoothStatus.connectedDevices.map(device => device.name).join(", ")
            : Translation.tr("No devices connected")
        detail: !page.isOn ? Translation.tr("Turn it on to use headphones, mice and other devices")
            : (page.adapter?.discoverable ?? false) ? Translation.tr("Visible to others as “%1”").arg(page.adapter?.name ?? "")
            : Translation.tr("%1 paired devices").arg(BluetoothStatus.pairedDevices.length)
        checked: page.isOn
        switchEnabled: BluetoothStatus.available
        switchLabel: Translation.tr("Turn Bluetooth on or off")
        onToggled: BluetoothStatus.setEnabled(!page.isOn)

        ConfigSwitch {
            visible: page.isOn
            buttonIcon: "visibility"
            text: Translation.tr("Visible to nearby devices")
            description: Translation.tr("Lets phones and other computers find this one, to pair from their side")
            autoToggle: false
            checked: page.adapter?.discoverable ?? false
            onClicked: if (page.adapter) page.adapter.discoverable = !page.adapter.discoverable
        }
    }

    ContentSection {
        icon: "devices"
        title: Translation.tr("My devices")
        visible: page.isOn

        Repeater {
            model: BluetoothStatus.pairedDevices
            delegate: BluetoothDeviceRow {
                required property var modelData
                device: modelData
            }
        }

        StyledText {
            visible: BluetoothStatus.pairedDevices.length === 0
            Layout.fillWidth: true
            Layout.margins: 14
            text: Translation.tr("No paired devices yet. Switch on the device you want to add, put it in pairing mode and pick it below.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        icon: "bluetooth_searching"
        title: Translation.tr("Nearby devices")
        description: Translation.tr("Click a device to pair with it. It will connect by itself next time.")
        visible: page.isOn

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                text: (page.adapter?.discovering ?? false) ? Translation.tr("Looking for devices…")
                    : Translation.tr("Not looking right now")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            MaterialSymbol {
                visible: page.adapter?.discovering ?? false
                text: "progress_activity"
                iconSize: 18
                color: Appearance.colors.colSubtext
                RotationAnimation on rotation {
                    running: page.adapter?.discovering ?? false
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1200
                }
            }
        }

        Repeater {
            model: page.namedNearby
            delegate: BluetoothDeviceRow {
                required property var modelData
                device: modelData
            }
        }

        ConfigNavRow {
            visible: page.unnamedNearby.length > 0
            buttonIcon: page.showUnnamed ? "expand_less" : "expand_more"
            title: page.showUnnamed ? Translation.tr("Hide devices without a name")
                : Translation.tr("Devices without a name (%1)").arg(page.unnamedNearby.length)
            trailingIcon: ""
            onClicked: page.showUnnamed = !page.showUnnamed
        }

        Repeater {
            model: page.showUnnamed ? page.unnamedNearby : []
            delegate: BluetoothDeviceRow {
                required property var modelData
                device: modelData
            }
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Options")

        ConfigSwitch {
            buttonIcon: "battery_android_full"
            text: Translation.tr("Show the battery of connected devices in the bar")
            checked: Config.options.bar.indicators.bluetoothBattery
            onCheckedChanged: Config.options.bar.indicators.bluetoothBattery = checked
        }
        ConfigNavRow {
            buttonIcon: "settings_bluetooth"
            title: Translation.tr("Advanced Bluetooth settings")
            description: Translation.tr("File transfer, audio profiles and other details")
            trailingIcon: "open_in_new"
            onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.bluetooth])
        }
    }
}
