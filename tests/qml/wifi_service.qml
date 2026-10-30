import QtQuick
import Quickshell
import "services"
import "modules/settings/network"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        width: 640
        height: 160
        PasswordForm {
            id: form
            anchors.fill: parent
            busy: !Network.awaitingPassword
            promptToken: Network.secretRequest
            errorText: Network.wifiErrorMessage
            onAccepted: password => Network.submitPassword(password)
            onCanceled: Network.cancelPasswordPrompt()
        }
    }
    property int phase: 0
    property int ticks: 0
    property string oldOperation: ""
    function field() { return form.children[0].children[0]; }
    function check(condition, label) {
        if (!condition) { console.error("WIFI TEST", label); Qt.exit(2); }
    }
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            ticks++;
            if (ticks > 110) { console.error("WIFI TEST timeout", phase); Qt.exit(3); }
            switch (phase) {
            case 0:
                if (!Network.wifiEnabled || !Network.wifiNetworks.length) return;
                Network.connectToWifiNetwork(Network.wifiNetworks[0]); phase++; break;
            case 1:
                if (!Network.awaitingPassword) return;
                check(!form.busy && Network.secretRequest === "1", "initial prompt");
                check(field().activeFocus, "initial focus");
                oldOperation = Network.operationId;
                field().text = " credential-sentinel-я\n ";
                form.submit();
                check(form.text === "", "submit clears synchronously");
                phase++; break;
            case 2:
                if (Network.secretRequest !== "2") return;
                check(Network.wifiErrorMessage.length > 0, "retry message");
                check(field().activeFocus, "retry focus");
                field().text = "replacement-credential-sentinel";
                form.submit(); phase++; break;
            case 3:
                if (Network.connectionPending) return;
                check(!Network.wifiErrorMessage && !Network.passwordPromptSsid && !Network.operationId, "success clears state");
                Network.backendEvent(JSON.stringify({event:"secret-required",operation:oldOperation,request:"stale"}));
                check(!Network.awaitingPassword, "late event ignored");
                Network.connectToHiddenNetwork(" hidden name ", "sae"); phase++; break;
            case 4:
                if (!Network.awaitingPassword) return;
                check(Network.operationHidden, "hidden path");
                field().text = "credential-sentinel-to-cancel";
                form.cancel();
                check(form.text === "" && !Network.connectionPending, "cancel clears");
                phase++; break;
            case 5:
                Network.connectToHiddenNetwork("crash", "wpa-psk"); phase++; break;
            case 6:
                if (Network.connectionPending) return;
                check(!Network.backendReady && Network.wifiErrorMessage.length > 0, "backend death recoverable");
                Network.connectToHiddenNetwork("restart", "wpa-psk"); phase++; break;
            case 7:
                if (!Network.awaitingPassword) return;
                check(Network.backendReady, "lazy restart");
                form.cancel();
                phase++; break;
            case 8:
                check(!Network.awaitingPassword && !Network.connectionPending, "cancel stale reply ignored");
                console.log("WIFI SERVICE CHECKS PASSED"); Qt.quit(); break;
            }
        }
    }
}
