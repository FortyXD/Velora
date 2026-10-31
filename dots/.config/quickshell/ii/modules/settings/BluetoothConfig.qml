import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.network

ContentPage {
    id: page
    readonly property var adapter: BluetoothManager.adapter
    readonly property bool isOn: BluetoothManager.powered && !BluetoothManager.softBlocked

    // Devices by path, in the order given. A row reads its own details, so these only change when the list
    // does, not with every signal level.
    property var savedKeys: []
    property var namedKeys: []
    property var unnamedKeys: []
    property bool showUnnamed: false
    function updateKeys(): void {
        const assign = (name, list) => {
            const next = list.map(device => device.path);
            if (JSON.stringify(next) !== JSON.stringify(page[name])) page[name] = next;
        };
        assign("savedKeys", BluetoothManager.saved);
        assign("namedKeys", BluetoothManager.nearby.filter(device => device.named));
        assign("unnamedKeys", BluetoothManager.nearby.filter(device => !device.named));
    }
    Component.onCompleted: page.updateKeys()
    Connections {
        target: BluetoothManager
        function onSavedChanged() {
            page.updateKeys();
        }
        function onNearbyChanged() {
            page.updateKeys();
        }
    }

    // Looks for devices only while the page is on screen
    readonly property bool searching: page.pageShown && page.isOn
    onSearchingChanged: BluetoothManager.setDiscovering(page.searching)
    Component.onDestruction: BluetoothManager.setDiscovering(false)

    NoticeBox {
        visible: Network.snapshotError.length > 0
        Layout.fillWidth: true
        materialIcon: "error"
        text: Network.snapshotError
    }

    NoticeBox {
        visible: BluetoothManager.hardBlocked
        Layout.fillWidth: true
        materialIcon: "airplanemode_active"
        text: Translation.tr("Bluetooth is turned off by a switch or key on this computer.")
    }

    ConnectionHeader {
        icon: !page.isOn ? "bluetooth_disabled" : BluetoothManager.connected.length > 0 ? "bluetooth_connected" : "bluetooth"
        iconColor: page.heroColor
        title: Translation.tr("Bluetooth")
        subtitle: !BluetoothManager.available ? Translation.tr("No Bluetooth adapter found")
            : !page.isOn ? Translation.tr("Off")
            : BluetoothManager.connected.length > 0 ? BluetoothManager.connected.map(device => device.name).join(", ")
            : Translation.tr("No devices connected")
        detail: !page.isOn ? Translation.tr("Turn it on to use headphones, mice and other devices")
            : (page.adapter?.discoverable ?? false) ? Translation.tr("Visible to others as “%1”").arg(page.adapter?.name ?? "")
            : Translation.tr("%1 paired devices").arg(BluetoothManager.saved.length)
        checked: page.isOn
        switchEnabled: BluetoothManager.available && !BluetoothManager.hardBlocked
        switchLabel: Translation.tr("Turn Bluetooth on or off")
        onToggled: BluetoothManager.setEnabled(!page.isOn)

        ConfigSwitch {
            visible: page.isOn
            buttonIcon: "visibility"
            text: Translation.tr("Visible to nearby devices")
            description: Translation.tr("Lets phones and other computers find this one, to pair from their side")
            autoToggle: false
            checked: page.adapter?.discoverable ?? false
            onClicked: BluetoothManager.setDiscoverable(!(page.adapter?.discoverable ?? false))
        }
    }

    ContentSection {
        icon: "devices"
        title: Translation.tr("My devices")
        description: Translation.tr("Every device this computer has paired with. Click one for its details.")
        visible: BluetoothManager.available

        Repeater {
            model: page.savedKeys
            delegate: BluetoothDeviceRow {
                required property var modelData
                path: modelData
            }
        }

        StyledText {
            visible: page.savedKeys.length === 0
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
                text: BluetoothManager.discovering ? Translation.tr("Looking for devices…") : Translation.tr("Not looking right now")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            StatusIcon {
                visible: BluetoothManager.discovering
                text: ""
                iconSize: 18
                color: Appearance.colors.colSubtext
                busy: BluetoothManager.discovering
            }
        }

        Repeater {
            model: page.namedKeys
            delegate: BluetoothDeviceRow {
                required property var modelData
                path: modelData
            }
        }

        ConfigNavRow {
            visible: page.unnamedKeys.length > 0
            buttonIcon: page.showUnnamed ? "expand_less" : "expand_more"
            title: page.showUnnamed ? Translation.tr("Hide devices without a name")
                : Translation.tr("Devices without a name (%1)").arg(page.unnamedKeys.length)
            trailingIcon: ""
            onClicked: page.showUnnamed = !page.showUnnamed
        }

        Repeater {
            model: page.showUnnamed ? page.unnamedKeys : []
            delegate: BluetoothDeviceRow {
                required property var modelData
                path: modelData
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
            title: Translation.tr("Bluetooth settings")
            description: Translation.tr("This computer's name and visibility, what happens at login, and receiving files")
            onClicked: ApplicationWindow.window?.openPage("bluetooth-options")
        }
    }
}
