pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string suggestedHost: ""
    property string result: ""
    function pingHost(value: string): string {
        const raw = value.trim();
        const bracket = raw.match(/^\[([0-9a-fA-F:.%\w-]+)\](?::\d+)?$/);
        if (bracket) return bracket[1];
        const ipv6 = raw.split(":").length > 2;
        if (ipv6) return /^[a-f0-9:.]+(?:%[a-z0-9_.-]+)?$/i.test(raw) ? raw : "";
        if (/\s/.test(raw)) return "";
        const hostname = raw.match(/^([a-z0-9\u0080-\uFFFF][a-z0-9.\u0080-\uFFFF-]*)(?::\d+)?$/i);
        return hostname ? hostname[1] : "";
    }
    function start(): void {
        const name = pingHost(server.text);
        if (!name || probe.running) return;
        root.result = "";
        probe.command = ["timeout", "5", "ping", "-n", "-c", "1", "-W", "2", "-w", "3", "--", name];
        probe.running = true;
    }
    RowLayout {
        Layout.fillWidth: true
        MaterialTextField {
            id: server
            Layout.fillWidth: true
            text: root.suggestedHost
            placeholderText: Translation.tr("Hostname or IP address")
            enabled: !probe.running
            onTextChanged: root.result = ""
            onAccepted: root.start()
        }
        DialogButton {
            buttonText: probe.running ? Translation.tr("Pinging…") : Translation.tr("Ping")
            enabled: !probe.running && root.pingHost(server.text).length > 0
            onClicked: root.start()
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.result.length > 0
        text: root.result
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
    }
    Process {
        id: probe
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => {
            const latency = output.text.match(/time([=<])\s*([\d.]+)\s*ms/);
            root.result = code === 0 ? (latency ? (latency[1] === "<" ? "<" : "") + latency[2] + " ms" : Translation.tr("Server replied"))
                : /not permitted|permission denied|cap_net_raw/i.test(errors.text) ? Translation.tr("Ping needs permission to send ICMP on this computer.")
                : /unknown host|name or service not known|name resolution/i.test(errors.text) ? Translation.tr("Could not resolve this hostname.")
                : code === 127 ? Translation.tr("Install iputils to ping servers.")
                : Translation.tr("No ICMP reply. The server may block ping.");
        }
    }
}
