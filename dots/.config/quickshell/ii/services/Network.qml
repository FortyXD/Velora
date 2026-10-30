pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.network
import qs.modules.common

/** NetworkManager state and controls for the right sidebar and the Wi-Fi settings page. */
Singleton {
    id: root

    property bool wifi: false
    property bool ethernet: false
    property bool wifiEnabled: false
    property bool wifiScanning: false
    property real lastWifiScanMs: 0
    property bool connectionPending: false
    property string wifiConnectSsid: ""
    property string passwordPromptSsid: ""
    property string wifiErrorMessage: ""
    property string failedNetworkKey: ""
    property string snapshotError: ""
    property string operationId: ""
    property string operationKey: ""
    property bool operationHidden: false
    property string secretRequest: ""
    property bool backendReady: false
    property var queuedConnection: null
    readonly property bool awaitingPassword: connectionPending && secretRequest.length > 0
    property bool snapshotRefreshPending: false

    readonly property bool wifiConnecting: connectionPending || wifiStatus === "connecting"
    property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(network => network.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        const rank = network => network.active ? 0 : network.savedUuid ? 1 : 2;
        return rank(a) - rank(b) || b.strength - a.strength || a.ssid.localeCompare(b.ssid);
    })
    // Every saved Wi-Fi profile, in range or not: { ssid, uuid }
    property list<var> savedNetworks: []
    readonly property list<var> savedOutOfRange: savedNetworks.filter(saved => !wifiNetworks.some(network => network.ssid === saved.ssid))
    // Addresses of the connected Wi-Fi and wired devices: { device, ip, gateway, dns }. Only read while
    // `trackDetails` is on (the settings page), since the sidebar doesn't show them.
    property bool trackDetails: false
    property var wifiDetails: ({})
    property var ethernetDetails: ({})
    property string wifiStatus: "disconnected"
    readonly property string networkName: ethernet ? Translation.tr("Ethernet") : (active?.ssid ?? "")
    readonly property int networkStrength: active?.strength ?? 0
    readonly property string materialSymbol: root.ethernet
        ? "lan"
        : root.wifiConnecting ? "sync"
        : !root.wifiEnabled ? "signal_wifi_off"
        : root.wifiStatus === "connected" ? (
            root.networkStrength > 83 ? "signal_wifi_4_bar" :
            root.networkStrength > 67 ? "network_wifi" :
            root.networkStrength > 50 ? "network_wifi_3_bar" :
            root.networkStrength > 33 ? "network_wifi_2_bar" :
            root.networkStrength > 17 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
        ) : root.wifiStatus === "limited" ? "signal_wifi_bad" : "wifi_find"

    Component.onCompleted: update()

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
        enableWifiProc.exec(["nmcli", "radio", "wifi", enabled ? "on" : "off"]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(force = false): void {
        if (!wifiEnabled || wifiScanning) return;
        const now = Date.now();
        if (!force && now - lastWifiScanMs < 30000) return;
        lastWifiScanMs = now;
        wifiScanning = true;
        rescanProcess.running = true;
    }

    function requestSnapshot(): void {
        snapshotRefreshPending = true;
        if (!getNetworks.running) {
            snapshotRefreshPending = false;
            getNetworks.running = true;
        }
    }

    function update(): void {
        updateConnectionType.startCheck();
        wifiStatusProcess.running = true;
        requestSnapshot();
        if (trackDetails) detailsProc.running = true;
    }

    onTrackDetailsChanged: if (trackDetails) detailsProc.running = true

    function forgetWifiNetwork(uuid: string): void {
        if (!uuid) return;
        forgetProc.exec(["nmcli", "connection", "delete", "uuid", uuid]);
    }

    function errorMessage(code: string): string {
        switch (code) {
        case "retry": return Translation.tr("Password needed again. Try another.");
        case "invalid-password": return Translation.tr("Check the password length and format.");
        case "invalid-name": return Translation.tr("Use a network name of 1–32 bytes.");
        case "auth": return Translation.tr("Authentication failed. Try connecting again.");
        case "ip": return Translation.tr("Could not obtain an IP address. Check the router.");
        case "timeout": return Translation.tr("Connection timed out. Try again.");
        case "permission": return Translation.tr("Connection not allowed. Check permissions.");
        case "busy": return Translation.tr("Another Wi-Fi connection is in progress.");
        case "unsupported": return Translation.tr("This security type isn't supported in Velora's Wi-Fi settings.");
        case "not-saved": return Translation.tr("Connected, but the password could not be saved.");
        case "unavailable": return Translation.tr("Wi-Fi helper unavailable. Try again.");
        case "already-connected": return "";
        default: return Translation.tr("Could not connect. Try again.");
        }
    }

    function startConnection(command, key: string, hidden: bool): void {
        if (!wifiEnabled || connectionPending) return;
        operationId = Date.now().toString() + "-" + Math.random().toString(36).slice(2);
        operationKey = key;
        operationHidden = hidden;
        wifiConnectSsid = command.ssid;
        failedNetworkKey = "";
        wifiErrorMessage = "";
        secretRequest = "";
        passwordPromptSsid = "";
        connectionPending = true;
        command.command = "connect";
        command.operation = operationId;
        if (backendReady && credentialBackend.running) {
            credentialBackend.write(JSON.stringify(command) + "\n");
        } else {
            queuedConnection = command;
            credentialBackend.running = true;
            backendStartTimer.restart();
        }
    }

    function connectToHiddenNetwork(ssid: string, security: string): void {
        startConnection({ssid: ssid, hidden: true, security: security}, "hidden", true);
    }

    function connectToWifiNetwork(network: WifiAccessPoint): void {
        if (!network || network.active) return;
        startConnection({ssid: network.ssid, uuid: network.savedUuid, bssid: network.bssid}, network.key, false);
    }

    function submitPassword(password: string): void {
        if (!awaitingPassword || !backendReady) return;
        const request = secretRequest;
        secretRequest = "";
        passwordPromptSsid = "";
        wifiErrorMessage = "";
        credentialBackend.write(JSON.stringify({command: "submit", operation: operationId, request: request, password: password}) + "\n");
    }

    function cancelPasswordPrompt(): void {
        if (connectionPending && backendReady)
            credentialBackend.write(JSON.stringify({command: "cancel", operation: operationId}) + "\n");
        queuedConnection = null;
        clearConnection();
        failedNetworkKey = "";
        wifiErrorMessage = "";
    }

    function clearConnection(): void {
        connectionPending = false;
        secretRequest = "";
        passwordPromptSsid = "";
        wifiConnectSsid = "";
        operationId = "";
        operationKey = "";
    }

    function backendEvent(line: string): void {
        let message;
        try { message = JSON.parse(line); } catch (error) { backendUnavailable(); return; }
        if (message.event === "ready") {
            backendStartTimer.stop();
            backendReady = true;
            if (queuedConnection) {
                credentialBackend.write(JSON.stringify(queuedConnection) + "\n");
                queuedConnection = null;
            }
            return;
        }
        if (message.event === "unavailable") { backendUnavailable(); return; }
        if (!connectionPending || message.operation !== operationId) return;
        if (message.event === "secret-required") {
            secretRequest = message.request;
            passwordPromptSsid = wifiConnectSsid;
            wifiErrorMessage = message.code ? errorMessage(message.code) : "";
        } else if (message.event === "connecting" || message.event === "saving") {
            secretRequest = "";
            passwordPromptSsid = "";
        } else if (["connected", "failed", "cancelled"].includes(message.event)) {
            wifiErrorMessage = message.code ? errorMessage(message.code) : "";
            failedNetworkKey = message.event === "failed" && !operationHidden ? operationKey : "";
            clearConnection();
            update();
        }
    }

    function backendUnavailable(): void {
        backendStartTimer.stop();
        backendReady = false;
        queuedConnection = null;
        if (connectionPending) {
            wifiErrorMessage = errorMessage("unavailable");
            failedNetworkKey = operationHidden ? "" : operationKey;
            clearConnection();
        }
        credentialBackend.running = false;
    }

    function disconnectWifiNetwork(): void {
        if (!active) return;
        const command = active.savedUuid
            ? ["nmcli", "connection", "down", "uuid", active.savedUuid]
            : ["nmcli", "connection", "down", active.ssid];
        disconnectProc.exec(command);
    }

    function openPublicWifiPortal(): void {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]);
    }

    Process {
        id: enableWifiProc
        onExited: root.update()
    }

    Process {
        id: credentialBackend
        command: ["python3", Quickshell.shellPath("scripts/network/wifi_agent.py")]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => root.backendEvent(line) }
        // The helper deliberately emits no raw exception/input diagnostics.
        onExited: root.backendUnavailable()
    }

    Timer {
        id: backendStartTimer
        interval: 12000
        onTriggered: root.backendUnavailable()
    }

    Process {
        id: disconnectProc
        onExited: root.update()
    }

    Process {
        id: forgetProc
        onExited: root.update()
    }

    Process {
        id: detailsProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["sh", "-c", 'nmcli -t -f DEVICE,TYPE,STATE device | while IFS=: read -r dev type state; do case "$type:$state" in wifi:connected|ethernet:connected) echo "@@"; nmcli -t -f GENERAL.DEVICE,GENERAL.TYPE,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$dev";; esac; done']
        stdout: StdioCollector {
            onStreamFinished: {
                let wifi = {};
                let ethernet = {};
                for (const block of text.split("@@").filter(part => part.trim().length > 0)) {
                    let details = { "device": "", "ip": "", "gateway": "", "dns": [] };
                    let type = "";
                    for (const line of block.split("\n")) {
                        const colon = line.indexOf(":");
                        if (colon < 0) continue;
                        const key = line.slice(0, colon);
                        const value = line.slice(colon + 1).replace(/\\:/g, ":").trim();
                        if (key === "GENERAL.DEVICE") details.device = value;
                        else if (key === "GENERAL.TYPE") type = value;
                        else if (key.startsWith("IP4.ADDRESS") && !details.ip) details.ip = value;
                        else if (key === "IP4.GATEWAY") details.gateway = value === "--" ? "" : value;
                        else if (key.startsWith("IP4.DNS")) details.dns.push(value);
                    }
                    if (type === "wifi") wifi = details;
                    else if (type === "ethernet") ethernet = details;
                }
                root.wifiDetails = wifi;
                root.ethernetDetails = ethernet;
            }
        }
    }

    Process {
        id: rescanProcess
        command: ["nmcli", "device", "wifi", "rescan"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                rescanRefreshTimer.restart();
                rescanLateRefreshTimer.restart();
            } else {
                root.lastWifiScanMs = 0;
                root.wifiScanning = false;
                root.requestSnapshot();
            }
        }
    }

    Timer {
        id: rescanRefreshTimer
        interval: 1800
        onTriggered: {
            root.wifiScanning = false;
            root.requestSnapshot();
        }
    }

    Timer {
        id: rescanLateRefreshTimer
        interval: 4500
        onTriggered: root.requestSnapshot()
    }

    // Secret reads may emit many NetworkManager profile-change events. Batch
    // those updates so they cannot trigger another snapshot immediately.
    Timer {
        id: profileRefreshTimer
        interval: 30000
        repeat: false
        onTriggered: root.requestSnapshot()
    }

    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("connection profile changed")) {
                    if (!profileRefreshTimer.running) profileRefreshTimer.start();
                    return;
                }
                root.update();
            }
        }
    }

    Process {
        id: updateConnectionType
        property string buffer: ""
        property bool refreshPending: false
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status && nmcli -t -f CONNECTIVITY g"]
        function startCheck(): void {
            if (running) {
                refreshPending = true;
                return;
            }
            buffer = "";
            running = true;
        }
        stdout: SplitParser {
            onRead: data => updateConnectionType.buffer += data + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            const lines = buffer.trim().split("\n");
            const connectivity = lines[lines.length - 1];
            if (exitCode === 0 && /^(full|limited|portal|none|unknown)$/.test(connectivity)) {
                lines.pop();
                let hasEthernet = false;
                let hasWifi = false;
                let status = "disconnected";
                for (const line of lines) {
                    if (line.startsWith("ethernet:connected")) hasEthernet = true;
                    if (!line.startsWith("wifi:")) continue;
                    if (line.includes("disconnected")) status = "disconnected";
                    else if (line.includes("connected")) {
                        hasWifi = true;
                        status = connectivity === "limited" ? "limited" : "connected";
                    } else if (line.includes("connecting")) status = "connecting";
                    else if (line.includes("unavailable") || line.includes("unmanaged")) status = "disabled";
                }
                root.wifiStatus = status;
                root.ethernet = hasEthernet;
                root.wifi = hasWifi;
            }
            if (refreshPending) {
                refreshPending = false;
                Qt.callLater(() => updateConnectionType.startCheck());
            }
        }
    }

    Process {
        id: wifiStatusProcess
        command: ["nmcli", "radio", "wifi"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                const enabled = text.trim() === "enabled";
                const justEnabled = enabled && !root.wifiEnabled;
                root.wifiEnabled = enabled;
                if (justEnabled) {
                    root.lastWifiScanMs = 0;
                    root.rescanWifi();
                }
            }
        }
    }

    Process {
        id: getNetworks
        command: ["python3", Quickshell.shellPath("scripts/network/wifi_snapshot.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                let snapshot;
                try {
                    snapshot = JSON.parse(text);
                } catch (error) {
                    root.snapshotError = Translation.tr("Could not read Wi-Fi networks");
                    return;
                }
                if (snapshot.error) {
                    root.snapshotError = Translation.tr(snapshot.error);
                    return;
                }
                root.snapshotError = "";
                root.savedNetworks = snapshot.saved ?? [];
                // Built aside and assigned once: splice/push on a list property notify every
                // intermediate step, and those steps hold the same network twice
                const networks = snapshot.networks ?? [];
                const previous = root.wifiNetworks;
                const next = [];
                for (const network of networks) {
                    const existing = next.find(item => item.key === network.key)
                        ?? previous.find(item => item.key === network.key);
                    if (existing) existing.lastIpcObject = network;
                    if (!next.includes(existing)) next.push(existing ?? apComp.createObject(root, { lastIpcObject: network }));
                }
                // Keep a disappearing target's inline cancel/form alive until the operation ends.
                const pendingTarget = previous.find(item => root.connectionPending && item.key === root.operationKey);
                if (pendingTarget && !next.includes(pendingTarget)) next.push(pendingTarget);
                // The AP may disappear mid-failure; keep the error visible in the
                // general message when its inline row is no longer available.
                if (root.failedNetworkKey && !next.some(item => item.key === root.failedNetworkKey))
                    root.failedNetworkKey = "";
                const gone = previous.filter(item => !next.includes(item));
                root.wifiNetworks = next;
                for (const item of gone) item.destroy();
            }
        }
        onExited: {
            if (root.snapshotRefreshPending) {
                root.snapshotRefreshPending = false;
                Qt.callLater(() => root.requestSnapshot());
            }
        }
    }

    Component {
        id: apComp
        WifiAccessPoint {}
    }
}
