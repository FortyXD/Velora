pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(sortFunction)
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]
    property list<var> pairedDevices: [...connectedDevices, ...pairedButNotConnectedDevices]

    // Shared actions, so the sidebar and the settings page behave the same

    function setEnabled(enabled: bool): void {
        if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = enabled;
    }

    function setDiscovering(discovering: bool): void {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter || (discovering && !adapter.enabled)) return;
        if (adapter.discovering !== discovering) adapter.discovering = discovering;
    }

    // Address of a device whose pairing failed, until another attempt starts
    property string pairingFailedAddress: ""

    // Pairs a new device (it is trusted, so it reconnects by itself later) and connects to it
    function pairAndConnect(device: BluetoothDevice): void {
        if (!device) return;
        root.pairingFailedAddress = "";
        const address = device.address;
        BluetoothManager.pair(device.dbusPath, error => {
            if (error && error.code !== "canceled") root.pairingFailedAddress = address;
        });
    }

    function forget(device: BluetoothDevice): void {
        device?.forget();
    }
}
