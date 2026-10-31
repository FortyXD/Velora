pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

/**
 * Questions from the system about connections: a password NetworkManager needs, a PIN a device asks for, a file
 * someone wants to send. They come one at a time, and answers go back through the daemon. Whatever it asks for
 * stays here only until answered.
 */
Singleton {
    id: root

    property var queue: []
    readonly property var current: root.queue[0] ?? null
    readonly property string kind: root.current?.kind ?? ""
    // A note with a code to type on the other device: nothing to answer, only to dismiss
    readonly property bool isNote: root.kind === "bluetooth-show-code"
    readonly property bool needsInput: root.fields.length > 0

    readonly property string symbol: {
        if (root.kind === "secrets") return root.current.connectionType === "vpn" ? "vpn_key" : "wifi_password";
        if (root.kind === "bluetooth-file") return "file_download";
        return "bluetooth";
    }

    readonly property string title: {
        const name = root.current?.deviceName ?? root.current?.connectionName ?? "";
        switch (root.kind) {
        case "secrets": return root.current.retry ? Translation.tr("“%1” didn't accept that").arg(name) : Translation.tr("“%1” needs a password").arg(name);
        case "bluetooth-pin":
        case "bluetooth-passkey": return Translation.tr("Pairing with “%1”").arg(name);
        case "bluetooth-confirm": return Translation.tr("Pairing with “%1”").arg(name);
        case "bluetooth-show-code": return Translation.tr("Pairing with “%1”").arg(name);
        case "bluetooth-authorize": return Translation.tr("“%1” wants to pair").arg(name);
        case "bluetooth-service": return Translation.tr("“%1” wants to connect").arg(name);
        case "bluetooth-file": return Translation.tr("“%1” is sending a file").arg(name);
        default: return "";
        }
    }

    readonly property string message: {
        switch (root.kind) {
        case "secrets": return root.current.message || (root.current.retry ? Translation.tr("Enter it again to connect.") : Translation.tr("Enter it to connect."));
        case "bluetooth-pin": return Translation.tr("Enter the PIN shown on the device, or its usual one (often 0000).");
        case "bluetooth-passkey": return Translation.tr("Enter the number shown on the device.");
        case "bluetooth-confirm": return Translation.tr("Check that the device shows this number:");
        case "bluetooth-show-code": return Translation.tr("Type this on the device, then press Enter on it:");
        case "bluetooth-authorize": return Translation.tr("Allow it to pair with this computer?");
        case "bluetooth-service": return root.current.service ? Translation.tr("Allow it to use: %1?").arg(Translation.tr(root.current.service)) : Translation.tr("Allow it to connect?");
        case "bluetooth-file": return Translation.tr("%1 (%2). It will be saved in %3.").arg(root.current.fileName).arg(root.sizeText(root.current.fileSize)).arg(root.current.folder);
        default: return "";
        }
    }

    readonly property string code: root.current?.code ?? ""

    readonly property var fields: {
        switch (root.kind) {
        case "secrets": return (root.current.fields ?? []).map(key => ({ key, label: root.secretLabel(key), hidden: key !== "challenge-response" }));
        case "bluetooth-pin": return [{ key: "pin", label: Translation.tr("PIN"), hidden: false }];
        case "bluetooth-passkey": return [{ key: "passkey", label: Translation.tr("Number"), hidden: false }];
        default: return [];
        }
    }

    readonly property string acceptText: {
        switch (root.kind) {
        case "bluetooth-confirm": return Translation.tr("They match");
        case "bluetooth-authorize":
        case "bluetooth-service": return Translation.tr("Allow");
        case "bluetooth-file": return Translation.tr("Accept");
        default: return Translation.tr("OK");
        }
    }

    readonly property string declineText: {
        switch (root.kind) {
        case "bluetooth-confirm": return Translation.tr("They don't");
        case "bluetooth-authorize":
        case "bluetooth-service":
        case "bluetooth-file": return Translation.tr("Decline");
        case "bluetooth-show-code": return Translation.tr("Close");
        default: return Translation.tr("Cancel");
        }
    }

    function secretLabel(key: string): string {
        switch (key) {
        case "psk":
        case "password": return Translation.tr("Password");
        case "wep-key0": return Translation.tr("WEP key");
        case "leap-password": return Translation.tr("LEAP password");
        case "private-key-password":
        case "cert-pass": return Translation.tr("Private key password");
        case "private-key": return Translation.tr("Private key");
        case "challenge-response": return Translation.tr("Code");
        default: return key;
        }
    }

    function sizeText(bytes: real): string {
        if (bytes >= 1048576) return Translation.tr("%1 MB").arg((bytes / 1048576).toFixed(1));
        if (bytes >= 1024) return Translation.tr("%1 KB").arg(Math.round(bytes / 1024));
        return Translation.tr("%1 bytes").arg(bytes);
    }

    function dropCurrent(): void {
        root.queue = root.queue.slice(1);
    }

    /** Answers the question on screen. `values` holds what was typed, by field key. */
    function answer(accepted: bool, values: var): void {
        const question = root.current;
        if (!question) return;
        root.dropCurrent();
        if (question.kind === "bluetooth-show-code") return;
        ConnectivityBackend.call("prompt.answer", { id: question.id, accepted, values: values ?? {} }, null);
    }

    Connections {
        target: ConnectivityBackend
        function onEvent(name, data) {
            if (name === "prompt") {
                root.queue = [...root.queue, data];
            } else if (name === "promptWithdrawn") {
                root.queue = root.queue.filter(question => question.id !== data.id);
            }
        }
        // Whatever was asked went away with the daemon
        function onReadyChanged() {
            if (!ConnectivityBackend.ready) root.queue = [];
        }
    }
}
