pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

/**
 * Bluetooth as the settings pages show it, from velora-connectivityd: every adapter and device with all BlueZ
 * knows of them, and actions that report how they went. The bar keeps reading `BluetoothStatus`.
 */
Singleton {
    id: root

    readonly property var state: ConnectivityBackend.bluetooth
    readonly property bool available: root.state.available ?? false
    readonly property bool powered: root.state.powered ?? false
    readonly property bool softBlocked: root.state.softBlocked ?? false
    readonly property bool hardBlocked: root.state.hardBlocked ?? false
    readonly property bool discovering: root.state.discovering ?? false
    readonly property var adapters: root.state.adapters ?? []
    readonly property var saved: root.state.saved ?? []
    readonly property var nearby: root.state.nearby ?? []
    readonly property var connected: root.saved.filter(device => device.connected)

    // Adapter the settings are about, when there are several
    property string selectedAdapter: ""
    readonly property var adapter: root.adapters.find(adapter => adapter.path === root.selectedAdapter) ?? root.adapters[0] ?? null
    // Device whose page is open
    property string selectedDevice: ""
    readonly property var device: root.deviceByPath[root.selectedDevice] ?? null
    readonly property var deviceByPath: {
        const byPath = {};
        for (const device of [...root.saved, ...root.nearby]) byPath[device.path] = device;
        return byPath;
    }

    // What's going on per device: requests in flight, and the last error
    property var busy: ({})
    property var errors: ({})

    // The settings app goes to a device's page on this
    signal openDevicePage()

    function showDevice(path: string): void {
        root.selectedDevice = path;
        root.openDevicePage();
    }

    function setKey(map: var, key: string, value: var): var {
        const next = Object.assign({}, map);
        if (value === undefined) delete next[key];
        else next[key] = value;
        return next;
    }

    /** Runs a request about a device, keeping track of it. */
    function deviceRequest(method: string, device: string, params: var, done: var): void {
        root.busy = root.setKey(root.busy, device, true);
        root.errors = root.setKey(root.errors, device, undefined);
        ConnectivityBackend.call(method, Object.assign({ device }, params ?? {}), (result, error) => {
            root.busy = root.setKey(root.busy, device, undefined);
            // Canceling isn't a failure to tell anyone about
            if (error && error.code !== "canceled") root.errors = root.setKey(root.errors, device, Translation.tr(error.message));
            if (done) done(error);
        });
    }

    function setEnabled(enabled: bool): void {
        ConnectivityBackend.call("bluetooth.setEnabled", { enabled }, null);
    }

    function setDiscovering(enabled: bool): void {
        ConnectivityBackend.call("bluetooth.setDiscovering", { enabled }, null);
    }

    /** Pairs, trusts and connects a device; just connects one already paired. */
    function pair(device: string, done: var): void {
        root.deviceRequest("bluetooth.pair", device, null, done);
    }

    function cancelPairing(device: string): void {
        ConnectivityBackend.call("bluetooth.cancelPairing", { device }, null);
    }

    function connectDevice(device: string): void {
        root.deviceRequest("bluetooth.connect", device, null, null);
    }

    function disconnectDevice(device: string): void {
        root.deviceRequest("bluetooth.disconnect", device, null, null);
    }

    function setTrusted(device: string, value: bool): void {
        root.deviceRequest("bluetooth.setTrusted", device, { value }, null);
    }

    function setBlocked(device: string, value: bool): void {
        root.deviceRequest("bluetooth.setBlocked", device, { value }, null);
    }

    function rename(device: string, name: string): void {
        root.deviceRequest("bluetooth.rename", device, { name }, null);
    }

    function forget(device: string): void {
        root.deviceRequest("bluetooth.forget", device, null, null);
    }

    function setDiscoverable(value: bool): void {
        if (root.adapter) ConnectivityBackend.call("bluetooth.setDiscoverable", { adapter: root.adapter.path, value }, null);
    }

    function setDiscoverableTimeout(seconds: int): void {
        if (root.adapter) ConnectivityBackend.call("bluetooth.setDiscoverableTimeout", { adapter: root.adapter.path, seconds }, null);
    }

    function setAdapterName(name: string): void {
        if (root.adapter && name.length > 0) ConnectivityBackend.call("bluetooth.setAdapterName", { adapter: root.adapter.path, name }, null);
    }

    // Sending files: the current one, and how far it is
    property string sendingTo: ""
    property string sendingName: ""
    property real sendingSize: 0
    property real sendingDone: 0
    property string sendError: ""

    function sendFiles(address: string, files: var): void {
        root.sendingTo = address;
        root.sendError = "";
        ConnectivityBackend.call("bluetooth.sendFiles", { address, files }, (result, error) => {
            root.sendingTo = "";
            root.sendingName = "";
            if (error) root.sendError = Translation.tr(error.message);
        });
    }

    Connections {
        target: ConnectivityBackend
        function onEvent(name, data) {
            if (name === "transferStarted") {
                root.sendingName = data.name.split("/").pop();
                root.sendingSize = data.size;
                root.sendingDone = 0;
            } else if (name === "transferProgress") {
                root.sendingDone = data.transferred;
            }
        }
    }

    function typeSymbol(type: string): string {
        switch (type) {
        case "phone": return "smartphone";
        case "modem": return "router";
        case "computer": return "computer";
        case "network": return "lan";
        case "headset": return "headset_mic";
        case "headphones": return "headphones";
        case "audio": return "speaker";
        case "keyboard": return "keyboard";
        case "mouse": return "mouse";
        case "joypad": return "sports_esports";
        case "tablet": return "tablet";
        case "camera": return "photo_camera";
        case "printer": return "print";
        case "imaging": return "image";
        case "display": return "tv";
        case "wearable": return "watch";
        case "toy": return "smart_toy";
        case "health": return "favorite";
        default: return "bluetooth";
        }
    }

    function typeLabel(type: string): string {
        switch (type) {
        case "phone": return Translation.tr("Phone");
        case "modem": return Translation.tr("Modem");
        case "computer": return Translation.tr("Computer");
        case "network": return Translation.tr("Network device");
        case "headset": return Translation.tr("Headset");
        case "headphones": return Translation.tr("Headphones");
        case "audio": return Translation.tr("Audio device");
        case "keyboard": return Translation.tr("Keyboard");
        case "mouse": return Translation.tr("Mouse");
        case "joypad": return Translation.tr("Game controller");
        case "tablet": return Translation.tr("Tablet");
        case "camera": return Translation.tr("Camera");
        case "printer": return Translation.tr("Printer");
        case "imaging": return Translation.tr("Imaging device");
        case "display": return Translation.tr("Display");
        case "wearable": return Translation.tr("Wearable");
        case "toy": return Translation.tr("Toy");
        case "health": return Translation.tr("Health device");
        default: return Translation.tr("Device");
        }
    }
}
