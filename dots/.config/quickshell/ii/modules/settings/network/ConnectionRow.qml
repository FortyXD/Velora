import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** A saved connection of any kind: what it is and whether it's up, with buttons to run, edit and remove it. */
ColumnLayout {
    id: root
    required property string uuid
    readonly property var profile: Network.profileByUuid[root.uuid] ?? null
    readonly property int activeState: root.profile?.activeState ?? 0
    readonly property bool active: root.activeState === 2
    readonly property bool busy: root.activeState === 1 || root.starting
    readonly property bool exportable: ["openvpn", "vpnc", "wireguard"].includes(root.profile?.vpnType ?? "")
    property bool starting: false
    property string errorText: ""

    signal exportRequested()

    function icon(): string {
        const type = root.profile?.connectionType ?? "";
        if (type === "vpn" || type === "wireguard") return "vpn_key";
        if (type === "802-3-ethernet") return "lan";
        if (type === "802-11-wireless") return "wifi";
        if (type === "gsm" || type === "cdma") return "signal_cellular_alt";
        if (type === "bluetooth") return "bluetooth";
        return "settings_ethernet";
    }

    function typeLabel(): string {
        const type = root.profile?.connectionType ?? "";
        if (type === "vpn") return `VPN · ${root.profile.vpnType}`;
        if (type === "wireguard") return "WireGuard";
        if (type === "802-3-ethernet") return Translation.tr("Cable");
        if (type === "802-11-wireless") return "Wi-Fi";
        if (type === "gsm" || type === "cdma") return Translation.tr("Mobile network");
        if (type === "bluetooth") return "Bluetooth";
        return type;
    }

    function toggle(): void {
        root.errorText = "";
        if (root.active || root.activeState === 1) {
            Network.deactivateProfile(root.uuid);
            return;
        }
        root.starting = true;
        ConnectivityBackend.call("network.activate", { uuid: root.uuid }, (result, error) => {
            root.starting = false;
            if (error) root.errorText = Translation.tr(error.message);
        });
    }

    Layout.fillWidth: true
    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 8
        Layout.topMargin: 6
        Layout.bottomMargin: 6
        spacing: 12

        ConfigIconTile {
            icon: root.icon()
            active: root.active
            iconSize: 22
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: root.profile?.id ?? ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: [root.busy ? Translation.tr("Connecting…") : root.active ? Translation.tr("Connected") : "", root.typeLabel()].filter(part => part.length > 0).join(" · ")
            }
        }
        StatusIcon {
            visible: root.busy
            text: ""
            iconSize: 18
            color: Appearance.colors.colSubtext
            busy: root.busy
        }
        DialogButton {
            enabled: !root.starting && ((root.profile?.available ?? false) || root.active)
            buttonText: root.active || root.activeState === 1 ? Translation.tr("Disconnect") : Translation.tr("Connect")
            onClicked: root.toggle()
        }
        DialogButton {
            buttonText: Translation.tr("Edit")
            onClicked: Network.editProfile(root.uuid)
        }
        DialogButton {
            visible: root.exportable
            buttonText: Translation.tr("Export")
            onClicked: root.exportRequested()
        }
        ForgetButton {
            label: Translation.tr("Remove")
            onConfirmed: Network.forgetWifiNetwork(root.uuid)
        }
    }

    StyledText {
        visible: root.errorText.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 62
        Layout.rightMargin: 12
        Layout.bottomMargin: 8
        text: root.errorText
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colError
    }
}
