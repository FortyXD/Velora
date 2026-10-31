import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.network

/** Every saved connection that isn't a Wi-Fi network, as in plasma-nm's list, and adding new ones. */
ContentPage {
    id: page

    property string errorText: ""
    property string exportUuid: ""
    property bool adding: false

    // Stable lists, so rows aren't rebuilt with every snapshot (see WifiConfig)
    property var vpnKeys: []
    property var otherKeys: []
    function updateKeys(): void {
        const keys = types => Network.profiles.filter(types).map(profile => profile.uuid);
        const nextVpn = keys(profile => profile.connectionType === "vpn" || profile.connectionType === "wireguard");
        const nextOther = keys(profile => !["vpn", "wireguard", "802-11-wireless"].includes(profile.connectionType));
        if (JSON.stringify(nextVpn) !== JSON.stringify(page.vpnKeys)) page.vpnKeys = nextVpn;
        if (JSON.stringify(nextOther) !== JSON.stringify(page.otherKeys)) page.otherKeys = nextOther;
    }
    Component.onCompleted: page.updateKeys()
    Connections {
        target: Network
        function onProfilesChanged() {
            page.updateKeys();
        }
    }

    readonly property var vpnKinds: (Network.state.vpnPlugins ?? []).map(service => ({ service, name: service.split(".").pop() }))

    function create(type, service, initial): void {
        ProfileEditor.startNew(type, service, initial);
        page.adding = false;
        ApplicationWindow.window?.openPage("connection-editor");
    }

    function importFile(path: string): void {
        page.errorText = "";
        ConnectivityBackend.call("network.importVpn", { path }, (result, error) => {
            if (error) page.errorText = Translation.tr(error.message);
        });
    }

    function exportTo(path: string): void {
        page.errorText = "";
        ConnectivityBackend.call("network.exportVpn", { uuid: page.exportUuid, path }, (result, error) => {
            if (error) page.errorText = Translation.tr(error.message);
        });
    }

    NoticeBox {
        visible: page.errorText.length > 0 || Network.snapshotError.length > 0
        Layout.fillWidth: true
        materialIcon: "error"
        text: page.errorText || Network.snapshotError
    }

    ContentSection {
        icon: "vpn_key"
        title: "VPN"
        Repeater {
            model: page.vpnKeys
            delegate: ConnectionRow {
                required property var modelData
                uuid: modelData
                onExportRequested: {
                    page.exportUuid = modelData;
                    exportDialog.open();
                }
            }
        }
        StyledText {
            visible: page.vpnKeys.length === 0
            Layout.fillWidth: true
            Layout.margins: 12
            text: Translation.tr("No VPN yet. Add one below, or import its configuration file.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        icon: "lan"
        title: Translation.tr("Other connections")
        visible: page.otherKeys.length > 0
        Repeater {
            model: page.otherKeys
            delegate: ConnectionRow {
                required property var modelData
                uuid: modelData
            }
        }
    }

    ContentSection {
        icon: "wifi"
        title: "Wi-Fi"
        ConfigNavRow {
            buttonIcon: "bookmark"
            title: Translation.tr("Saved Wi-Fi networks")
            valueText: `${Network.savedNetworks.length}`
            onClicked: ApplicationWindow.window?.openPage("wifi")
        }
    }

    ContentSection {
        icon: "add"
        title: Translation.tr("Add a connection")

        ConfigNavRow {
            buttonIcon: "upload_file"
            title: Translation.tr("Import a VPN from a file")
            description: Translation.tr("An OpenVPN .ovpn or WireGuard .conf file")
            onClicked: importDialog.open()
        }
        Repeater {
            model: page.vpnKinds
            delegate: ConfigNavRow {
                required property var modelData
                buttonIcon: "vpn_key"
                title: Translation.tr("VPN: %1").arg(modelData.name)
                onClicked: page.create("vpn", modelData.service, { "connection.id": `VPN ${modelData.name}` })
            }
        }
        ConfigNavRow {
            buttonIcon: "vpn_lock"
            title: "WireGuard"
            onClicked: page.create("wireguard", "", { "connection.id": "WireGuard", "connection.interface-name": "wg0" })
        }
        ConfigNavRow {
            buttonIcon: "wifi"
            title: Translation.tr("Wi-Fi network")
            description: Translation.tr("For one that needs an enterprise sign-in, or isn't around yet")
            onClicked: page.create("802-11-wireless", "", { "connection.id": "" })
        }
        ConfigNavRow {
            buttonIcon: "cable"
            title: Translation.tr("Cable")
            onClicked: page.create("802-3-ethernet", "", { "connection.id": Translation.tr("Cable") })
        }
        ConfigNavRow {
            buttonIcon: "router"
            title: "DSL (PPPoE)"
            onClicked: page.create("pppoe", "", { "connection.id": "DSL" })
        }
        ConfigNavRow {
            buttonIcon: "hub"
            title: Translation.tr("Bridge")
            onClicked: page.create("bridge", "", { "connection.id": Translation.tr("Bridge"), "connection.interface-name": "br0" })
        }
        ConfigNavRow {
            buttonIcon: "link"
            title: Translation.tr("Bond")
            onClicked: page.create("bond", "", { "connection.id": Translation.tr("Bond"), "connection.interface-name": "bond0" })
        }
        ConfigNavRow {
            buttonIcon: "account_tree"
            title: "VLAN"
            onClicked: page.create("vlan", "", { "connection.id": "VLAN" })
        }
    }

    FileDialog {
        id: importDialog
        nameFilters: [Translation.tr("VPN configuration (*.ovpn *.conf)"), Translation.tr("All files (*)")]
        onAccepted: page.importFile(FileUtils.trimFileProtocol(decodeURIComponent(selectedFile.toString())))
    }
    FileDialog {
        id: exportDialog
        fileMode: FileDialog.SaveFile
        nameFilters: [Translation.tr("VPN configuration (*.ovpn *.conf)")]
        onAccepted: page.exportTo(FileUtils.trimFileProtocol(decodeURIComponent(selectedFile.toString())))
    }
}
