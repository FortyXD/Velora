pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs.services.network
import qs.modules.common

/** NetworkManager state and controls for the right sidebar and the Wi-Fi settings page. */
Singleton {
    id: root

    // The latest state from velora-connectivityd
    readonly property var state: ConnectivityBackend.network
    readonly property bool available: root.state.available ?? false
    readonly property bool wifi: root.state.wifiConnected ?? false
    readonly property bool ethernet: root.state.ethernetConnected ?? false
    readonly property bool wifiEnabled: root.state.wifiEnabled ?? false
    readonly property bool wifiScanning: root.state.wifiScanning ?? false
    readonly property string wifiStatus: root.state.wifiStatus ?? "disconnected"
    readonly property string connectivity: root.state.connectivity ?? "unknown"
    readonly property string snapshotError: ConnectivityBackend.problem === "" ? ""
        : ConnectivityBackend.problem === "missing" ? Translation.tr("The connection service isn't installed. Run “velora update”.")
        : ConnectivityBackend.problem === "version" ? Translation.tr("The connection service is out of date. Run “velora update”.")
        : Translation.tr("The connection service stopped unexpectedly. Restarting it…")

    property bool connectionPending: false
    property string wifiConnectSsid: ""
    property string passwordPromptSsid: ""
    property string credentialErrorSsid: ""
    property string wifiErrorMessage: ""

    readonly property bool wifiConnecting: connectionPending || wifiStatus === "connecting"
    property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(network => network.active) ?? null
    // Reassigned only when the order really changes (see `onStateChanged`): lists are drawn with Repeaters,
    // which rebuild every row on a new list, and signal levels change all the time
    property list<var> friendlyWifiNetworks: []
    // Every saved profile of any kind, in the order plasma-nm lists them
    readonly property var profiles: root.state.profiles ?? []
    readonly property var profileByUuid: {
        const byUuid = {};
        for (const profile of root.profiles) byUuid[profile.uuid] = profile;
        return byUuid;
    }
    // Every saved Wi-Fi profile, in range or not: { ssid, uuid, ... }
    readonly property var savedNetworks: root.profiles.filter(profile => profile.connectionType === "802-11-wireless")
    readonly property bool wifiHardwareEnabled: root.state.wifiHardwareEnabled ?? true
    readonly property bool hotspotActive: root.state.hotspotActive ?? false
    readonly property bool airplaneMode: root.state.airplaneMode ?? false
    readonly property bool canShareConnection: (root.state.devices ?? []).some(device => device.supportsAp)
    readonly property var savedOutOfRange: savedNetworks.filter(saved => !wifiNetworks.some(network => network.ssid === saved.ssid))
    readonly property var wifiDetails: root.detailsOf(root.state.wifiDetails)
    readonly property var ethernetDetails: root.detailsOf(root.state.ethernetDetails)
    readonly property string networkName: ethernet ? Translation.tr("Ethernet") : (active?.ssid ?? "")
    readonly property int networkStrength: active?.strength ?? 0
    readonly property string materialSymbol: root.ethernet
        ? "lan"
        : !root.wifiEnabled ? "signal_wifi_off"
        : root.wifiConnecting ? "wifi"
        : root.wifiStatus === "connected" ? (
            root.networkStrength > 83 ? "signal_wifi_4_bar" :
            root.networkStrength > 67 ? "network_wifi" :
            root.networkStrength > 50 ? "network_wifi_3_bar" :
            root.networkStrength > 33 ? "network_wifi_2_bar" :
            root.networkStrength > 17 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
        ) : root.wifiStatus === "limited" ? "signal_wifi_bad" : "wifi_find"

    function detailsOf(device) {
        if (!device) return ({});
        return {
            "device": device.interface,
            "ip": device.ip4.addresses[0] ?? "",
            "gateway": device.ip4.gateway,
            "dns": device.ip4.dns
        };
    }

    /** The name of a security type as the daemon reports it. */
    function securityLabel(type: string): string {
        switch (type) {
        case "none": return Translation.tr("Open");
        case "wep": return "WEP";
        case "dynamic-wep": return Translation.tr("Dynamic WEP");
        case "leap": return "LEAP";
        case "wpa-psk": return "WPA/WPA2";
        case "sae": return "WPA3";
        case "owe": return Translation.tr("Enhanced Open (OWE)");
        case "wpa-eap": return Translation.tr("WPA/WPA2 Enterprise");
        case "wpa-eap-suite-b192": return Translation.tr("WPA3 Enterprise 192-bit");
        default: return Translation.tr("Unknown");
        }
    }

    function strengthSymbol(strength: int): string {
        return strength > 83 ? "signal_wifi_4_bar" :
            strength > 67 ? "network_wifi" :
            strength > 50 ? "network_wifi_3_bar" :
            strength > 33 ? "network_wifi_2_bar" :
            strength > 17 ? "network_wifi_1_bar" : "signal_wifi_0_bar";
    }

    function frequencyBand(frequency: int): string {
        return frequency <= 0 ? "" : frequency < 3000 ? "2.4 GHz" : frequency < 5925 ? "5 GHz" : "6 GHz";
    }

    function enableWifi(enabled = true): void {
        ConnectivityBackend.call("network.setWifiEnabled", { enabled }, null);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    /** Every radio off, remembering which were on; turning it off again brings back just those. */
    function setAirplaneMode(enabled: bool): void {
        ConnectivityBackend.call("network.setAirplaneMode", { enabled }, null);
    }

    function rescanWifi(force = false): void {
        if (!wifiEnabled) return;
        ConnectivityBackend.call("network.scan", { force }, null);
    }

    // A fresh list as soon as Wi-Fi comes on
    onWifiEnabledChanged: if (wifiEnabled) rescanWifi(true)

    function forgetWifiNetwork(uuid: string): void {
        if (!uuid) return;
        ConnectivityBackend.call("network.forget", { uuid }, null);
    }

    function startConnecting(ssid: string): void {
        wifiErrorMessage = "";
        wifiConnectSsid = ssid;
        connectionPending = true;
    }

    function connectToHiddenNetwork(ssid: string, password: string): void {
        if (!ssid || !wifiEnabled || connectionPending) return;
        startConnecting(ssid);
        ConnectivityBackend.call("network.join", { ssid, password, hidden: true }, (result, error) => root.finishConnection(error));
    }

    /** Joins by name and password, from a Wi-Fi QR code. */
    function joinNetwork(ssid: string, password: string): void {
        if (!ssid || !wifiEnabled || connectionPending) return;
        startConnecting(ssid);
        ConnectivityBackend.call("network.join", { ssid, password }, (result, error) => root.finishConnection(error));
    }

    function targetNetwork() {
        return wifiNetworks.find(network => network.ssid === wifiConnectSsid) ?? null;
    }

    function beginConnection(network) {
        if (!network || !wifiEnabled || connectionPending || network.active) return;
        // A password is asked for right away, like other systems do, for a new network and for a saved one
        // that never got connected (its profile has no working password)
        if (network.isSecure && !network.known) {
            network.askingPassword = true;
            passwordPromptSsid = network.ssid;
            wifiErrorMessage = "";
            return;
        }
        passwordPromptSsid = "";
        credentialErrorSsid = "";
        network.askingPassword = false;
        network.errorText = "";
        startConnecting(network.ssid);
        if (network.savedUuid) {
            ConnectivityBackend.call("network.activate", { uuid: network.savedUuid }, (result, error) => root.finishConnection(error));
        } else {
            ConnectivityBackend.call("network.join", { ssid: network.ssid, bssid: network.bssid }, (result, error) => root.finishConnection(error));
        }
    }

    function connectToWifiNetwork(network: WifiAccessPoint): void {
        beginConnection(network);
    }

    /** Connects a saved profile by its UUID, for the rows that list profiles rather than access points. */
    function connectProfile(profile: var): void {
        if (!profile || !wifiEnabled || connectionPending) return;
        const accessPoint = wifiNetworks.find(network => network.savedUuid === profile.uuid);
        if (accessPoint) {
            beginConnection(accessPoint);
            return;
        }
        credentialErrorSsid = "";
        startConnecting(profile.ssid);
        ConnectivityBackend.call("network.activate", { uuid: profile.uuid }, (result, error) => root.finishConnection(error));
    }

    /** Replaces a saved profile's password and connects with it. */
    function changeProfilePassword(profile: var, password: string): void {
        if (!profile || connectionPending || !password) return;
        const accessPoint = wifiNetworks.find(network => network.savedUuid === profile.uuid);
        if (accessPoint) {
            changePassword(accessPoint, password);
            return;
        }
        startConnecting(profile.ssid);
        ConnectivityBackend.call("network.changePassword", { uuid: profile.uuid, password }, (result, error) => root.finishConnection(error));
    }

    function deactivateProfile(uuid: string): void {
        ConnectivityBackend.call("network.deactivate", { uuid }, null);
    }

    // The settings app goes to its connection editor on this
    signal openEditor()

    /** Opens a profile in the settings app's connection editor. */
    function editProfile(uuid: string): void {
        ProfileEditor.requestOpen(uuid);
        root.openEditor();
    }

    function startHotspot(ssid: string, password: string, done: var): void {
        ConnectivityBackend.call("network.startHotspot", { ssid, password }, (result, error) => done(error));
    }

    function stopHotspot(): void {
        ConnectivityBackend.call("network.stopHotspot", {}, null);
    }

    function changePassword(network: WifiAccessPoint, password: string): void {
        if (!network || connectionPending || !password) return;
        network.errorText = "";
        startConnecting(network.ssid);
        const join = () => ConnectivityBackend.call("network.join", { ssid: network.ssid, bssid: network.bssid, password }, (result, error) => root.finishConnection(error));
        if (network.savedUuid && network.neverUsed) {
            // A profile that never connected may lack its security settings: start over with a fresh one
            ConnectivityBackend.call("network.forget", { uuid: network.savedUuid }, (result, error) => error ? root.finishConnection(error) : join());
        } else if (network.savedUuid) {
            ConnectivityBackend.call("network.changePassword", { uuid: network.savedUuid, password }, (result, error) => root.finishConnection(error));
        } else {
            join();
        }
    }

    function finishConnection(error): void {
        const target = targetNetwork();
        if (error) {
            const needsPassword = error.code === "wrong_secret" || error.code === "secrets_required";
            const shouldAsk = needsPassword && !(target?.known ?? false);
            passwordPromptSsid = shouldAsk ? wifiConnectSsid : "";
            credentialErrorSsid = needsPassword && !shouldAsk ? wifiConnectSsid : "";
            wifiErrorMessage = needsPassword
                ? (shouldAsk ? Translation.tr("Password rejected. Try again.") : Translation.tr("Saved password was rejected. You can update it below."))
                : Translation.tr(error.message);
            if (target) {
                target.askingPassword = shouldAsk;
                target.errorText = wifiErrorMessage;
            }
        } else {
            wifiErrorMessage = "";
            passwordPromptSsid = "";
            credentialErrorSsid = "";
            if (target) {
                target.askingPassword = false;
                target.errorText = "";
            }
        }
        connectionPending = false;
        wifiConnectSsid = "";
    }

    function requestPasswordUpdate(): void {
        const target = wifiNetworks.find(network => network.ssid === credentialErrorSsid);
        if (!target || !target.savedUuid || connectionPending) return;
        passwordPromptSsid = target.ssid;
        credentialErrorSsid = "";
        target.askingPassword = true;
        target.errorText = "";
        wifiErrorMessage = "";
    }

    function cancelPasswordPrompt(): void {
        const target = wifiNetworks.find(network => network.ssid === passwordPromptSsid);
        if (target) {
            target.askingPassword = false;
            target.errorText = "";
        }
        passwordPromptSsid = "";
        credentialErrorSsid = "";
        wifiErrorMessage = "";
    }

    function disconnectWifiNetwork(): void {
        const connection = (root.state.activeConnections ?? []).find(active => active.connectionType === "802-11-wireless");
        if (connection) ConnectivityBackend.call("network.deactivate", { uuid: connection.uuid }, null);
    }

    function openPublicWifiPortal(): void {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]);
    }

    onStateChanged: {
        // Built aside and assigned once: splice/push on a list property notify every
        // intermediate step, and those steps hold the same network twice
        const networks = root.state.networks ?? [];
        const previous = root.wifiNetworks;
        const next = [];
        for (const network of networks) {
            const existing = next.find(item => item.ssid === network.ssid)
                ?? previous.find(item => item.ssid === network.ssid);
            if (existing) existing.lastIpcObject = network;
            if (!next.includes(existing)) next.push(existing ?? apComp.createObject(root, { lastIpcObject: network }));
        }
        const gone = previous.filter(item => !next.includes(item));
        if (next.length !== previous.length || next.some((item, index) => item !== previous[index])) root.wifiNetworks = next;
        // Signal in steps of ten, so a level wavering between two values doesn't swap two rows back and forth
        const rank = network => network.active ? 0 : network.savedUuid ? 1 : 2;
        const friendly = [...next].sort((a, b) => rank(a) - rank(b) || Math.round(b.strength / 10) - Math.round(a.strength / 10) || a.ssid.localeCompare(b.ssid));
        const shown = root.friendlyWifiNetworks;
        if (friendly.length !== shown.length || friendly.some((item, index) => item !== shown[index])) root.friendlyWifiNetworks = friendly;
        for (const item of gone) item.destroy();
    }

    Component {
        id: apComp
        WifiAccessPoint {}
    }
}
