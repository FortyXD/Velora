import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** The peers of the WireGuard profile being edited. */
ColumnLayout {
    id: root
    readonly property var peers: ProfileEditor.value("wireguard.peers", []) ?? []

    function update(index, name, value): void {
        const next = root.peers.map(peer => Object.assign({}, peer));
        if (value === "" || value === null) delete next[index][name];
        else next[index][name] = value;
        ProfileEditor.set("wireguard.peers", next);
    }

    Layout.fillWidth: true
    Layout.margins: 12
    spacing: 10

    Repeater {
        model: root.peers.length
        delegate: ColumnLayout {
            id: peerRow
            required property int index
            readonly property var peer: root.peers[peerRow.index] ?? ({})
            Layout.fillWidth: true
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Peer %1").arg(peerRow.index + 1)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                DialogButton {
                    buttonText: Translation.tr("Remove")
                    onClicked: ProfileEditor.set("wireguard.peers", root.peers.filter((peer, index) => index !== peerRow.index))
                }
            }
            RouteField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Public key")
                text: peerRow.peer["public-key"] ?? ""
                onTextEdited: root.update(peerRow.index, "public-key", text)
            }
            RouteField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Endpoint (host:port)")
                text: peerRow.peer.endpoint ?? ""
                onTextEdited: root.update(peerRow.index, "endpoint", text)
            }
            RouteField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Allowed addresses (comma-separated)")
                text: (peerRow.peer["allowed-ips"] ?? []).join(", ")
                onTextEdited: root.update(peerRow.index, "allowed-ips", text.split(/[,\s]+/).filter(item => item.length > 0))
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                RouteField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Preshared key (optional)")
                    echoMode: TextInput.Password
                    text: peerRow.peer["preshared-key"] ?? ""
                    onTextEdited: root.update(peerRow.index, "preshared-key", text)
                }
                RouteField {
                    Layout.preferredWidth: 160
                    placeholderText: Translation.tr("Keepalive, seconds")
                    text: `${peerRow.peer["persistent-keepalive"] ?? ""}`
                    onTextEdited: root.update(peerRow.index, "persistent-keepalive", text.length > 0 ? (parseInt(text) || 0) : null)
                }
            }
        }
    }

    DialogButton {
        buttonText: Translation.tr("Add a peer")
        onClicked: ProfileEditor.set("wireguard.peers", [...root.peers, { "allowed-ips": ["0.0.0.0/0", "::/0"] }])
    }
}
