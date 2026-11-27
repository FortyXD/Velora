pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentSection {
    id: root
    objectName: "proxy-vpn"
    title: Translation.tr("Proxy and subscription VPNs")
    description: Translation.tr("VLESS, VMess, Shadowsocks, Trojan, Hysteria 1/2 and TUIC profiles connect all applications.")
    icon: "vpn_lock"
    property bool pageShown: true
    property var profiles: []
    property string activeId: ""
    property bool engine: false
    property bool loaded: false
    property string serviceError: ""
    property string errorText: ""
    property string action: ""
    property string targetId: ""
    property string payload: ""
    property var queued: null
    readonly property bool busy: (action !== "" && action !== "status") || queued !== null

    function run(actionName, args = {}) {
        const request = Object.assign({action: actionName}, args);
        if (root.action) {
            if (root.action === "status" && actionName !== "status" && !root.queued)
                root.queued = request;
            return;
        }
        if (actionName !== "status") root.errorText = "";
        root.targetId = args.id ?? "";
        root.payload = JSON.stringify(request);
        root.action = actionName;
        worker.running = true;
    }
    function importLink() {
        if (root.busy || !link.text.trim()) return;
        root.run("import", {link: link.text.trim()});
        link.clear();
    }
    function apply(result) {
        if (result.error) {
            root.errorText = Translation.tr(result.error);
            return;
        }
        if (JSON.stringify(root.profiles) !== JSON.stringify(result.profiles))
            root.profiles = result.profiles;
        root.activeId = result.active;
        root.engine = result.engine;
        root.serviceError = result.serviceError ? Translation.tr(result.serviceError) : "";
        root.loaded = true;
    }
    Component.onCompleted: if (pageShown) run("status")
    onPageShownChanged: {
        if (pageShown) run("status");
        else link.clear();
    }
    Timer {
        running: root.pageShown && root.visible && root.loaded
        interval: 5000
        repeat: true
        onTriggered: root.run("status")
    }
    Process {
        id: worker
        command: ["/usr/bin/python3", "-B", Quickshell.shellPath("scripts/network/proxy_vpn.py")]
        stdinEnabled: true
        stdout: StdioCollector { id: reply }
        onStarted: {
            write(root.payload + "\n");
            root.payload = "";
        }
        onExited: {
            try {
                root.apply(JSON.parse(reply.text));
            } catch (_) {
                root.errorText = Translation.tr("The VPN service did not respond.");
            }
            root.action = "";
            root.targetId = "";
            const next = root.queued;
            root.queued = null;
            if (next) root.run(next.action, next);
        }
    }
    FileDialog {
        id: fileDialog
        nameFilters: [Translation.tr("VPN profiles (*.txt *.sub *.json)"), Translation.tr("All files (*)")]
        onAccepted: root.run("import", {path: FileUtils.trimFileProtocol(decodeURIComponent(selectedFile.toString()))})
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 8
        MaterialTextField {
            id: link
            objectName: "proxyVpnLink"
            Layout.fillWidth: true
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            placeholderText: Translation.tr("Share link or subscription URL")
            enabled: !root.busy
            onAccepted: root.importLink()
        }
        DialogButton {
            buttonText: root.action === "import" ? Translation.tr("Importing…") : Translation.tr("Import")
            enabled: !!link.text.trim() && !root.busy
            onClicked: root.importLink()
        }
        DialogButton {
            buttonText: Translation.tr("From clipboard")
            enabled: !root.busy
            onClicked: {
                const value = (Quickshell.clipboardText ?? "").trim();
                if (value.length > 4 * 1024 * 1024) root.errorText = Translation.tr("The subscription is too large.");
                else if (value) root.run("import", {link: value});
                else root.errorText = Translation.tr("Clipboard is empty");
            }
        }
        DialogButton {
            buttonText: Translation.tr("From file…")
            enabled: !root.busy
            onClicked: fileDialog.open()
        }
    }
    ConfigNavRow {
        visible: root.loaded && !root.engine
        enabled: !root.busy
        buttonIcon: "download"
        title: root.action === "install" ? Translation.tr("Installing…") : Translation.tr("Install VPN engine")
        description: Translation.tr("sing-box connects these profiles for all applications.")
        onClicked: root.run("install")
    }
    Repeater {
        model: root.profiles
        delegate: ColumnLayout {
            id: row
            required property var modelData
            readonly property bool active: root.activeId === modelData.id
            Layout.fillWidth: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 8
                ConfigIconTile { icon: row.modelData.subscription ? "subscriptions" : "vpn_key"; active: row.active }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                        text: [row.active ? Translation.tr("Tunnel active") : "",
                               row.modelData.servers.length > 1 ? Translation.tr("Servers: %1").arg(row.modelData.servers.length)
                                   : row.modelData.servers[0].protocol.toUpperCase(),
                               row.modelData.skipped ? Translation.tr("Skipped entries: %1").arg(row.modelData.skipped) : ""]
                            .filter(s => s.length).join(" · ")
                    }
                }
                DialogButton {
                    enabled: !root.busy && !root.serviceError && (row.active || (!root.activeId && root.engine))
                    buttonText: root.action === "connect" && root.targetId === row.modelData.id ? Translation.tr("Connecting…")
                        : row.active ? Translation.tr("Disconnect") : Translation.tr("Connect")
                    onClicked: root.run(row.active ? "disconnect" : "connect", {id: row.modelData.id})
                }
                DialogButton {
                    visible: row.modelData.subscription
                    enabled: !row.active && !root.busy
                    buttonText: Translation.tr("Refresh")
                    onClicked: root.run("refresh", {id: row.modelData.id})
                }
                ForgetButton {
                    enabled: !row.active && !root.busy
                    label: Translation.tr("Remove")
                    onConfirmed: root.run("remove", {id: row.modelData.id})
                }
            }
            ConfigComboRow {
                visible: row.modelData.servers.length > 1
                enabled: !row.active && !root.busy
                text: Translation.tr("Server")
                icon: "dns"
                options: row.modelData.servers.map(s => ({value: s.id, displayName: s.name + " · " + s.protocol.toUpperCase()}))
                currentValue: row.modelData.selected
                onSelected: value => root.run("select", {id: row.modelData.id, server: value})
            }
        }
    }
    StyledText {
        visible: !!text
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        text: root.errorText || root.serviceError
        color: Appearance.colors.colError
        wrapMode: Text.Wrap
    }
}
