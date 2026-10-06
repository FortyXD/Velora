pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.network
import qs.modules.common

/** NetworkManager state and controls for the right sidebar. */
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
    property string credentialErrorSsid: ""
    property string wifiErrorMessage: ""
    property string snapshotError: ""
    property string connectErrorBuffer: ""
    property bool snapshotRefreshPending: false

    readonly property bool wifiConnecting: connectionPending || wifiStatus === "connecting"
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(network => network.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        const rank = network => network.active ? 0 : network.savedUuid ? 1 : 2;
        return rank(a) - rank(b) || b.strength - a.strength || a.ssid.localeCompare(b.ssid);
    })
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
    }

    function targetNetwork() {
        return wifiNetworks.find(network => network.ssid === wifiConnectSsid) ?? null;
    }

    function beginConnection(network) {
        if (!network || !wifiEnabled || connectionPending || network.active) return;
        if (network.isSecure && !network.savedUuid) {
            network.askingPassword = true;
            passwordPromptSsid = network.ssid;
            wifiErrorMessage = "";
            return;
        }
        passwordPromptSsid = "";
        credentialErrorSsid = "";
        network.askingPassword = false;
        network.errorText = "";
        wifiErrorMessage = "";
        credentialErrorSsid = "";
        wifiConnectSsid = network.ssid;
        connectErrorBuffer = "";
        connectionPending = true;
        if (network.savedUuid) {
            connectProc.exec(["nmcli", "connection", "up", "uuid", network.savedUuid]);
        } else {
            const command = ["nmcli", "device", "wifi", "connect", network.ssid];
            if (network.bssid) command.push("bssid", network.bssid);
            connectProc.exec(command);
        }
    }

    function connectToWifiNetwork(network: WifiAccessPoint): void {
        beginConnection(network);
    }

    function changePassword(network: WifiAccessPoint, password: string): void {
        if (!network || connectionPending || !password) return;
        network.errorText = "";
        wifiErrorMessage = "";
        wifiConnectSsid = network.ssid;
        connectErrorBuffer = "";
        connectionPending = true;
        if (network.savedUuid) {
            passwordProc.exec({
                environment: { PASSWORD: password, UUID: network.savedUuid },
                command: ["sh", "-c", 'nmcli connection modify uuid "$UUID" wifi-sec.psk "$PASSWORD" && nmcli connection up uuid "$UUID"']
            });
        } else {
            passwordProc.exec({
                environment: { PASSWORD: password, SSID: network.ssid, BSSID: network.bssid },
                command: ["sh", "-c", 'nmcli device wifi connect "$SSID" password "$PASSWORD" bssid "$BSSID"']
            });
        }
    }

    function finishConnection(exitCode: int): void {
        const target = targetNetwork();
        if (exitCode !== 0) {
            const message = connectErrorBuffer.trim().split("\n").find(line => line.trim().length > 0) ?? Translation.tr("Connection failed");
            const needsPassword = /secrets|password|passphrase|authentication/i.test(connectErrorBuffer);
            const shouldAsk = needsPassword && !(target?.savedCredentials ?? false);
            passwordPromptSsid = shouldAsk ? wifiConnectSsid : "";
            credentialErrorSsid = needsPassword && !shouldAsk && (target?.savedUuid ?? "") ? wifiConnectSsid : "";
            wifiErrorMessage = needsPassword
                ? (shouldAsk ? Translation.tr("Password rejected. Try again.") : Translation.tr("Saved password was rejected. You can update it below."))
                : message;
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
        update();
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
        id: connectProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        stderr: SplitParser {
            onRead: line => root.connectErrorBuffer += line + "\n"
        }
        onExited: (exitCode, exitStatus) => root.finishConnection(exitCode)
    }

    Process {
        id: passwordProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        stderr: SplitParser {
            onRead: line => root.connectErrorBuffer += line + "\n"
        }
        onExited: (exitCode, exitStatus) => root.finishConnection(exitCode)
    }

    Process {
        id: disconnectProc
        onExited: root.update()
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
                    root.snapshotError = "Could not read Wi-Fi networks";
                    return;
                }
                if (snapshot.error) {
                    root.snapshotError = snapshot.error;
                    return;
                }
                root.snapshotError = "";
                const networks = snapshot.networks ?? [];
                const current = root.wifiNetworks;
                for (const previous of [...current]) {
                    if (networks.some(network => network.ssid === previous.ssid)) continue;
                    current.splice(current.indexOf(previous), 1);
                    previous.destroy();
                }
                for (const network of networks) {
                    const existing = current.find(item => item.ssid === network.ssid);
                    if (existing) existing.lastIpcObject = network;
                    else current.push(apComp.createObject(root, { lastIpcObject: network }));
                }
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
