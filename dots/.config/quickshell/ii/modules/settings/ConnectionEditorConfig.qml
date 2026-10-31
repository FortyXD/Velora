import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.network

/**
 * Every setting of one connection profile, in the sections its kind has, as in plasma-nm's editor. It edits
 * what `ProfileEditor` holds; a row anywhere can open it with `Network.editProfile`.
 */
ContentPage {
    id: page

    readonly property string type: ProfileEditor.connectionType
    readonly property bool isWifi: page.type === "802-11-wireless"
    readonly property bool isWired: page.type === "802-3-ethernet"
    readonly property bool isVpn: page.type === "vpn"
    readonly property bool isOpenVpn: page.isVpn && (ProfileEditor.value("vpn.service-type", ProfileEditor.newVpnService) ?? "").endsWith(".openvpn")
    readonly property bool isWireGuard: page.type === "wireguard"
    readonly property bool hasIp: !["bond-slave", "team-slave"].includes(page.type)
    readonly property string keyMgmt: ProfileEditor.value("802-11-wireless-security.key-mgmt", "") ?? ""
    readonly property string authAlg: ProfileEditor.value("802-11-wireless-security.auth-alg", "") ?? ""
    readonly property string securityChoice: page.keyMgmt === "" ? "none"
        : page.keyMgmt === "none" ? "wep"
        : page.keyMgmt === "ieee8021x" ? (page.authAlg === "leap" ? "leap" : "dynamic-wep")
        : page.keyMgmt
    readonly property bool usesEnterprise: page.securityChoice === "wpa-eap" || page.securityChoice === "wpa-eap-suite-b-192" || page.securityChoice === "dynamic-wep"
    readonly property bool wired8021x: ProfileEditor.value("802-1x.eap", null) !== null && (ProfileEditor.value("802-1x.eap", []) ?? []).length > 0
    readonly property string eapMethod: (ProfileEditor.value("802-1x.eap", []) ?? [])[0] ?? "peap"
    readonly property string ipv4Method: ProfileEditor.value("ipv4.method", "auto")
    readonly property string ipv6Method: ProfileEditor.value("ipv6.method", "auto")
    readonly property string macChoice: {
        const current = ProfileEditor.value(page.macKey, "") ?? "";
        return current === "" || ["permanent", "preserve", "random", "stable"].includes(current) ? current : "custom";
    }
    readonly property string macKey: page.isWifi ? "802-11-wireless.assigned-mac-address" : "802-3-ethernet.assigned-mac-address"
    readonly property var allKeys: Object.keys(ProfileEditor.fields).filter(key => !key.startsWith("vpn.")).sort()
    property bool showAll: false

    function chooseSecurity(choice: string): void {
        if (choice === "none") {
            ProfileEditor.clearSection("802-11-wireless-security");
            return;
        }
        const keyMgmts = { "wep": "none", "dynamic-wep": "ieee8021x", "leap": "ieee8021x" };
        ProfileEditor.set("802-11-wireless-security.key-mgmt", keyMgmts[choice] ?? choice);
        ProfileEditor.set("802-11-wireless-security.auth-alg", choice === "leap" ? "leap" : "");
        if (["wpa-eap", "wpa-eap-suite-b-192", "dynamic-wep"].includes(choice) && !page.wired8021x) ProfileEditor.set("802-1x.eap", ["peap"]);
    }

    function chooseEap(method: string): void {
        ProfileEditor.set("802-1x.eap", [method]);
    }

    function goBack(): void {
        ApplicationWindow.window?.openPage(page.isWifi ? "wifi" : "connections");
    }

    onPageShownChanged: if (!page.pageShown) ProfileEditor.forgetSecrets()

    NoticeBox {
        visible: ProfileEditor.pendingOpen.length > 0
        Layout.fillWidth: true
        materialIcon: "warning"
        text: Translation.tr("You have unsaved changes to “%1”.").arg(ProfileEditor.title)
        DialogButton {
            buttonText: Translation.tr("Keep editing")
            onClicked: ProfileEditor.pendingOpen = ""
        }
        DialogButton {
            buttonText: Translation.tr("Discard changes")
            onClicked: ProfileEditor.open(ProfileEditor.pendingOpen)
        }
    }

    NoticeBox {
        visible: !ProfileEditor.active
        Layout.fillWidth: true
        materialIcon: "info"
        text: Translation.tr("Choose a connection to edit.")
    }

    NoticeBox {
        visible: ProfileEditor.errorText.length > 0
        Layout.fillWidth: true
        materialIcon: "error"
        text: ProfileEditor.errorText
        DialogButton {
            visible: ProfileEditor.conflict
            buttonText: Translation.tr("Load the newer version")
            onClicked: {
                ProfileEditor.discard();
                ProfileEditor.reload();
            }
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("General")
        visible: ProfileEditor.active

        ProfileTextField {
            fieldKey: "connection.id"
            label: Translation.tr("Name")
        }
        ProfileSwitch {
            fieldKey: "connection.autoconnect"
            defaultValue: true
            buttonIcon: "autorenew"
            text: Translation.tr("Connect automatically")
        }
        ProfileTextField {
            fieldKey: "connection.autoconnect-priority"
            label: Translation.tr("Priority")
            description: Translation.tr("When several could connect, the highest goes first")
            placeholderText: "0"
        }
        ConfigSwitch {
            buttonIcon: "group"
            text: Translation.tr("All users may use this connection")
            autoToggle: false
            checked: (ProfileEditor.value("connection.permissions", []) ?? []).length === 0
            onClicked: ProfileEditor.set("connection.permissions", checked ? [`user:${Quickshell.env("USER")}:`] : [])
        }
        ProfileCombo {
            fieldKey: "connection.metered"
            defaultValue: 0
            icon: "data_usage"
            text: Translation.tr("Metered")
            description: Translation.tr("Whether data on this connection costs money")
            options: [
                { displayName: Translation.tr("Decide automatically"), value: 0 },
                { displayName: Translation.tr("Yes"), value: 1 },
                { displayName: Translation.tr("No"), value: 2 },
            ]
        }
        ProfileTextField {
            fieldKey: "connection.zone"
            label: Translation.tr("Firewall zone")
        }
        ProfileCombo {
            fieldKey: "connection.secondaries"
            visible: !page.isVpn && !page.isWireGuard
            defaultValue: []
            icon: "vpn_key"
            text: Translation.tr("Use this VPN automatically")
            currentValue: (ProfileEditor.value("connection.secondaries", []) ?? [])[0] ?? ""
            options: [
                { displayName: Translation.tr("None"), value: "" },
                ...Network.profiles.filter(profile => profile.connectionType === "vpn").map(profile => ({ displayName: profile.id, value: profile.uuid })),
            ]
            onSelected: value => ProfileEditor.set("connection.secondaries", value ? [value] : [])
        }
    }

    ContentSection {
        icon: "wifi"
        title: Translation.tr("Wi-Fi")
        visible: ProfileEditor.active && page.isWifi

        ProfileTextField {
            fieldKey: "802-11-wireless.ssid"
            label: Translation.tr("Network name (SSID)")
        }
        ProfileCombo {
            fieldKey: "802-11-wireless.mode"
            defaultValue: "infrastructure"
            icon: "router"
            text: Translation.tr("Mode")
            options: [
                { displayName: Translation.tr("Regular (joins a router)"), value: "infrastructure" },
                { displayName: Translation.tr("Ad-hoc (computer to computer)"), value: "adhoc" },
                { displayName: Translation.tr("Access point (shares a connection)"), value: "ap" },
            ]
        }
        ProfileSwitch {
            fieldKey: "802-11-wireless.hidden"
            buttonIcon: "visibility_off"
            text: Translation.tr("This network hides its name")
        }
        ProfileCombo {
            fieldKey: "802-11-wireless.band"
            icon: "settings_input_antenna"
            text: Translation.tr("Band")
            options: [
                { displayName: Translation.tr("Automatic"), value: "" },
                { displayName: "2.4 GHz", value: "bg" },
                { displayName: "5 GHz", value: "a" },
            ]
        }
        ProfileTextField {
            fieldKey: "802-11-wireless.channel"
            visible: (ProfileEditor.value("802-11-wireless.band", "") ?? "") !== ""
            label: Translation.tr("Channel")
            placeholderText: Translation.tr("Automatic")
        }
        ProfileTextField {
            fieldKey: "802-11-wireless.bssid"
            label: Translation.tr("Only this access point (BSSID)")
            placeholderText: "AA:BB:CC:DD:EE:FF"
        }
        ProfileTextField {
            fieldKey: "802-11-wireless.mac-address"
            label: Translation.tr("Only this Wi-Fi device (MAC)")
            placeholderText: "AA:BB:CC:DD:EE:FF"
        }
        ProfileTextField {
            fieldKey: "802-11-wireless.mtu"
            label: "MTU"
            placeholderText: Translation.tr("Automatic")
        }
        ConfigComboRow {
            icon: "shuffle"
            text: Translation.tr("Address this computer shows")
            options: page.macOptions
            currentValue: page.macChoice
            onSelected: value => ProfileEditor.set(page.macKey, value === "custom" ? "" : value)
        }
    }

    readonly property var macOptions: [
        { displayName: Translation.tr("Default"), value: "" },
        { displayName: Translation.tr("Its real address"), value: "permanent" },
        { displayName: Translation.tr("Keep the current one"), value: "preserve" },
        { displayName: Translation.tr("Random each time"), value: "random" },
        { displayName: Translation.tr("Random, the same for this network"), value: "stable" },
        { displayName: Translation.tr("A specific address"), value: "custom" },
    ]

    ContentSection {
        icon: "encrypted"
        title: Translation.tr("Security")
        visible: ProfileEditor.active && page.isWifi

        ConfigComboRow {
            icon: "shield"
            text: Translation.tr("Protocol")
            currentValue: page.securityChoice
            options: [
                { displayName: Translation.tr("None"), value: "none" },
                { displayName: "WEP", value: "wep" },
                { displayName: Translation.tr("Dynamic WEP"), value: "dynamic-wep" },
                { displayName: "LEAP", value: "leap" },
                { displayName: "WPA/WPA2", value: "wpa-psk" },
                { displayName: "WPA3", value: "sae" },
                { displayName: Translation.tr("Enhanced Open (OWE)"), value: "owe" },
                { displayName: Translation.tr("WPA/WPA2 Enterprise"), value: "wpa-eap" },
                { displayName: Translation.tr("WPA3 Enterprise 192-bit"), value: "wpa-eap-suite-b-192" },
            ]
            onSelected: value => page.chooseSecurity(value)
        }
        ProfileSecretField {
            visible: page.securityChoice === "wpa-psk" || page.securityChoice === "sae"
            fieldKey: "802-11-wireless-security.psk"
            flagsKey: "802-11-wireless-security.psk-flags"
        }
        ProfileSecretField {
            visible: page.securityChoice === "wep"
            fieldKey: "802-11-wireless-security.wep-key0"
            label: Translation.tr("WEP key")
            flagsKey: "802-11-wireless-security.wep-key-flags"
        }
        ProfileTextField {
            visible: page.securityChoice === "leap"
            fieldKey: "802-11-wireless-security.leap-username"
            label: Translation.tr("User name")
        }
        ProfileSecretField {
            visible: page.securityChoice === "leap"
            fieldKey: "802-11-wireless-security.leap-password"
            flagsKey: "802-11-wireless-security.leap-password-flags"
        }
    }

    ContentSection {
        icon: "cable"
        title: Translation.tr("Cable")
        visible: ProfileEditor.active && page.isWired

        ProfileTextField {
            fieldKey: "802-3-ethernet.mac-address"
            label: Translation.tr("Only this device (MAC)")
            placeholderText: "AA:BB:CC:DD:EE:FF"
        }
        ConfigComboRow {
            icon: "shuffle"
            text: Translation.tr("Address this computer shows")
            options: page.macOptions
            currentValue: page.macChoice
            onSelected: value => ProfileEditor.set(page.macKey, value === "custom" ? "" : value)
        }
        ProfileTextField {
            fieldKey: "802-3-ethernet.mtu"
            label: "MTU"
            placeholderText: Translation.tr("Automatic")
        }
        ProfileSwitch {
            fieldKey: "802-3-ethernet.auto-negotiate"
            buttonIcon: "sync_alt"
            text: Translation.tr("Agree on the speed automatically")
        }
        ProfileTextField {
            fieldKey: "802-3-ethernet.speed"
            label: Translation.tr("Speed, Mbit/s")
            placeholderText: Translation.tr("Automatic")
        }
        ProfileCombo {
            fieldKey: "802-3-ethernet.duplex"
            icon: "swap_horiz"
            text: Translation.tr("Duplex")
            options: [
                { displayName: Translation.tr("Automatic"), value: "" },
                { displayName: Translation.tr("Full"), value: "full" },
                { displayName: Translation.tr("Half"), value: "half" },
            ]
        }
        ProfileCombo {
            fieldKey: "802-3-ethernet.wake-on-lan"
            defaultValue: 1
            icon: "power_settings_new"
            text: Translation.tr("Wake on LAN")
            options: [
                { displayName: Translation.tr("Default"), value: 1 },
                { displayName: Translation.tr("Off"), value: 0x8000 },
                { displayName: Translation.tr("On a magic packet"), value: 0x40 },
            ]
        }
        ConfigSwitch {
            buttonIcon: "badge"
            text: Translation.tr("Sign in to the network (802.1X)")
            autoToggle: false
            checked: page.wired8021x
            onClicked: {
                if (page.wired8021x) ProfileEditor.clearSection("802-1x");
                else ProfileEditor.set("802-1x.eap", ["peap"]);
            }
        }
    }

    ContentSection {
        icon: "badge"
        title: Translation.tr("Enterprise sign-in")
        visible: ProfileEditor.active && ((page.isWifi && page.usesEnterprise) || (page.isWired && page.wired8021x))

        ConfigComboRow {
            icon: "key"
            text: Translation.tr("Method")
            currentValue: page.eapMethod
            options: [
                { displayName: "PEAP", value: "peap" },
                { displayName: "TTLS", value: "ttls" },
                { displayName: Translation.tr("TLS (certificate)"), value: "tls" },
                { displayName: "FAST", value: "fast" },
                { displayName: "PWD", value: "pwd" },
                { displayName: "LEAP", value: "leap" },
                { displayName: "MD5", value: "md5" },
            ]
            onSelected: value => page.chooseEap(value)
        }
        ProfileTextField {
            fieldKey: "802-1x.identity"
            label: Translation.tr("User name")
        }
        ProfileTextField {
            visible: ["peap", "ttls", "fast"].includes(page.eapMethod)
            fieldKey: "802-1x.anonymous-identity"
            label: Translation.tr("Anonymous name")
        }
        ProfileSecretField {
            visible: page.eapMethod !== "tls"
            fieldKey: "802-1x.password"
            flagsKey: "802-1x.password-flags"
        }
        ProfileCombo {
            visible: ["peap", "ttls", "fast"].includes(page.eapMethod)
            fieldKey: "802-1x.phase2-auth"
            icon: "lock"
            text: Translation.tr("Inner authentication")
            options: [
                { displayName: "MSCHAPv2", value: "mschapv2" },
                { displayName: "GTC", value: "gtc" },
                { displayName: "MD5", value: "md5" },
                { displayName: "PAP", value: "pap" },
                { displayName: "CHAP", value: "chap" },
                { displayName: "MSCHAP", value: "mschap" },
            ]
        }
        ProfileFileField {
            visible: page.eapMethod !== "leap" && page.eapMethod !== "pwd"
            fieldKey: "802-1x.ca-cert"
            label: Translation.tr("CA certificate")
        }
        ProfileTextField {
            visible: page.eapMethod !== "leap" && page.eapMethod !== "pwd"
            fieldKey: "802-1x.domain-suffix-match"
            label: Translation.tr("Server's domain")
        }
        ProfileFileField {
            visible: page.eapMethod === "tls"
            fieldKey: "802-1x.client-cert"
            label: Translation.tr("Your certificate")
        }
        ProfileFileField {
            visible: page.eapMethod === "tls"
            fieldKey: "802-1x.private-key"
            label: Translation.tr("Your private key")
        }
        ProfileSecretField {
            visible: page.eapMethod === "tls"
            fieldKey: "802-1x.private-key-password"
            label: Translation.tr("Private key password")
            flagsKey: "802-1x.private-key-password-flags"
        }
    }

    ContentSection {
        icon: "vpn_key"
        title: Translation.tr("VPN")
        visible: ProfileEditor.active && page.isOpenVpn

        ProfileTextField {
            fieldKey: "vpn.data.remote"
            label: Translation.tr("Server")
            placeholderText: "vpn.example.com"
        }
        ProfileCombo {
            fieldKey: "vpn.data.connection-type"
            defaultValue: "tls"
            icon: "badge"
            text: Translation.tr("Sign-in")
            options: [
                { displayName: Translation.tr("Certificates"), value: "tls" },
                { displayName: Translation.tr("Password"), value: "password" },
                { displayName: Translation.tr("Password and certificates"), value: "password-tls" },
                { displayName: Translation.tr("Static key"), value: "static-key" },
            ]
        }
        ProfileTextField {
            visible: (ProfileEditor.value("vpn.data.connection-type", "tls") ?? "").startsWith("password")
            fieldKey: "vpn.data.username"
            label: Translation.tr("User name")
        }
        ProfileSecretField {
            visible: (ProfileEditor.value("vpn.data.connection-type", "tls") ?? "").startsWith("password")
            fieldKey: "vpn.secrets.password"
            flagsKey: "vpn.data.password-flags"
            flagsAsText: true
        }
        ProfileFileField {
            fieldKey: "vpn.data.ca"
            label: Translation.tr("CA certificate")
        }
        ProfileFileField {
            visible: (ProfileEditor.value("vpn.data.connection-type", "tls") ?? "").endsWith("tls")
            fieldKey: "vpn.data.cert"
            label: Translation.tr("Your certificate")
        }
        ProfileFileField {
            visible: (ProfileEditor.value("vpn.data.connection-type", "tls") ?? "").endsWith("tls")
            fieldKey: "vpn.data.key"
            label: Translation.tr("Your private key")
        }
        ProfileSecretField {
            visible: (ProfileEditor.value("vpn.data.connection-type", "tls") ?? "").endsWith("tls")
            fieldKey: "vpn.secrets.cert-pass"
            label: Translation.tr("Private key password")
            flagsKey: "vpn.data.cert-pass-flags"
            flagsAsText: true
        }
        ProfileFileField {
            visible: (ProfileEditor.value("vpn.data.connection-type", "tls") ?? "") === "static-key"
            fieldKey: "vpn.data.static-key"
            label: Translation.tr("Static key")
        }
        ProfileTextField {
            fieldKey: "vpn.data.port"
            label: Translation.tr("Port")
            placeholderText: "1194"
        }
        ConfigSwitch {
            buttonIcon: "swap_vert"
            text: Translation.tr("Use TCP")
            autoToggle: false
            checked: ProfileEditor.value("vpn.data.proto-tcp", "no") === "yes"
            onClicked: ProfileEditor.set("vpn.data.proto-tcp", checked ? "no" : "yes")
        }
        ProfileTextField {
            fieldKey: "vpn.data.cipher"
            label: Translation.tr("Cipher")
            placeholderText: Translation.tr("Automatic")
        }
        ProfileTextField {
            fieldKey: "vpn.data.auth"
            label: Translation.tr("Message authentication (HMAC)")
            placeholderText: Translation.tr("Automatic")
        }
        ProfileFileField {
            fieldKey: "vpn.data.ta"
            label: Translation.tr("TLS authentication key")
        }
        ProfileTextField {
            fieldKey: "vpn.data.ta-dir"
            label: Translation.tr("TLS key direction (0 or 1)")
        }
    }

    ContentSection {
        icon: "data_object"
        title: Translation.tr("VPN settings")
        description: Translation.tr("Everything this VPN's plugin stores, by name")
        visible: ProfileEditor.active && page.isVpn

        Repeater {
            model: Object.keys(ProfileEditor.value("vpn.data", {}) ?? {}).sort()
            delegate: ProfileTextField {
                required property var modelData
                fieldKey: `vpn.data.${modelData}`
                label: modelData
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 6
            RouteField {
                id: newVpnKey
                Layout.fillWidth: true
                placeholderText: Translation.tr("Setting name")
            }
            RouteField {
                id: newVpnValue
                Layout.fillWidth: true
                placeholderText: Translation.tr("Value")
            }
            DialogButton {
                buttonText: Translation.tr("Add")
                enabled: newVpnKey.text.length > 0
                onClicked: {
                    ProfileEditor.set(`vpn.data.${newVpnKey.text}`, newVpnValue.text);
                    newVpnKey.text = "";
                    newVpnValue.text = "";
                }
            }
        }
    }

    ContentSection {
        icon: "vpn_lock"
        title: "WireGuard"
        visible: ProfileEditor.active && page.isWireGuard

        ProfileTextField {
            fieldKey: "connection.interface-name"
            label: Translation.tr("Interface name")
            placeholderText: "wg0"
        }
        ProfileSecretField {
            fieldKey: "wireguard.private-key"
            label: Translation.tr("Private key")
            flagsKey: "wireguard.private-key-flags"
        }
        ProfileTextField {
            fieldKey: "wireguard.listen-port"
            label: Translation.tr("Listening port")
            placeholderText: Translation.tr("Automatic")
        }
        ProfileTextField {
            fieldKey: "wireguard.mtu"
            label: "MTU"
            placeholderText: Translation.tr("Automatic")
        }
        PeerListEditor {}
    }

    ContentSection {
        icon: "language"
        title: "IPv4"
        visible: ProfileEditor.active && page.hasIp

        ProfileCombo {
            fieldKey: "ipv4.method"
            defaultValue: "auto"
            icon: "settings_ethernet"
            text: Translation.tr("Addresses")
            options: [
                { displayName: Translation.tr("Automatic (DHCP)"), value: "auto" },
                { displayName: Translation.tr("Fixed"), value: "manual" },
                { displayName: Translation.tr("Local network only"), value: "link-local" },
                { displayName: Translation.tr("Shared with other computers"), value: "shared" },
                { displayName: Translation.tr("Disabled"), value: "disabled" },
            ]
        }
        ProfileListField {
            visible: page.ipv4Method === "manual" || page.ipv4Method === "shared"
            fieldKey: "ipv4.address-data"
            label: Translation.tr("Addresses (address/prefix)")
            placeholderText: "192.168.1.10/24"
        }
        ProfileTextField {
            visible: page.ipv4Method === "manual"
            fieldKey: "ipv4.gateway"
            label: Translation.tr("Router")
            placeholderText: "192.168.1.1"
        }
        ProfileListField {
            visible: page.ipv4Method !== "disabled"
            fieldKey: "ipv4.dns"
            label: Translation.tr("DNS servers")
            placeholderText: "1.1.1.1, 8.8.8.8"
        }
        ProfileSwitch {
            visible: page.ipv4Method === "auto"
            fieldKey: "ipv4.ignore-auto-dns"
            buttonIcon: "dns"
            text: Translation.tr("Use only the DNS servers above")
        }
        ProfileListField {
            visible: page.ipv4Method !== "disabled"
            fieldKey: "ipv4.dns-search"
            label: Translation.tr("Search domains")
            placeholderText: "example.com"
        }
        ProfileTextField {
            visible: page.ipv4Method === "auto"
            fieldKey: "ipv4.dhcp-client-id"
            label: Translation.tr("DHCP client ID")
        }
        ProfileSwitch {
            visible: page.ipv4Method !== "disabled"
            fieldKey: "ipv4.never-default"
            buttonIcon: "alt_route"
            text: Translation.tr("Only for addresses on this network")
            description: Translation.tr("Internet traffic doesn't go through this connection")
        }
        ProfileSwitch {
            visible: page.ipv4Method !== "disabled"
            fieldKey: "ipv4.may-fail"
            defaultValue: true
            buttonIcon: "rule"
            text: Translation.tr("Connect even without IPv4")
        }
        RouteListEditor {
            visible: page.ipv4Method !== "disabled"
            fieldKey: "ipv4.route-data"
        }
    }

    ContentSection {
        icon: "language"
        title: "IPv6"
        visible: ProfileEditor.active && page.hasIp

        ProfileCombo {
            fieldKey: "ipv6.method"
            defaultValue: "auto"
            icon: "settings_ethernet"
            text: Translation.tr("Addresses")
            options: [
                { displayName: Translation.tr("Automatic"), value: "auto" },
                { displayName: Translation.tr("Automatic, DHCP only"), value: "dhcp" },
                { displayName: Translation.tr("Fixed"), value: "manual" },
                { displayName: Translation.tr("Local network only"), value: "link-local" },
                { displayName: Translation.tr("Shared with other computers"), value: "shared" },
                { displayName: Translation.tr("Ignore"), value: "ignore" },
                { displayName: Translation.tr("Disabled"), value: "disabled" },
            ]
        }
        ProfileListField {
            visible: page.ipv6Method === "manual"
            fieldKey: "ipv6.address-data"
            label: Translation.tr("Addresses (address/prefix)")
            placeholderText: "2001:db8::10/64"
        }
        ProfileTextField {
            visible: page.ipv6Method === "manual"
            fieldKey: "ipv6.gateway"
            label: Translation.tr("Router")
        }
        ProfileListField {
            visible: !["ignore", "disabled"].includes(page.ipv6Method)
            fieldKey: "ipv6.dns"
            label: Translation.tr("DNS servers")
            placeholderText: "2606:4700:4700::1111"
        }
        ProfileSwitch {
            visible: page.ipv6Method === "auto" || page.ipv6Method === "dhcp"
            fieldKey: "ipv6.ignore-auto-dns"
            buttonIcon: "dns"
            text: Translation.tr("Use only the DNS servers above")
        }
        ProfileCombo {
            visible: page.ipv6Method === "auto"
            fieldKey: "ipv6.ip6-privacy"
            defaultValue: -1
            icon: "privacy_tip"
            text: Translation.tr("Temporary addresses (privacy)")
            options: [
                { displayName: Translation.tr("Default"), value: -1 },
                { displayName: Translation.tr("Off"), value: 0 },
                { displayName: Translation.tr("On, preferring the regular one"), value: 1 },
                { displayName: Translation.tr("On, preferring the temporary one"), value: 2 },
            ]
        }
        ProfileSwitch {
            visible: !["ignore", "disabled"].includes(page.ipv6Method)
            fieldKey: "ipv6.never-default"
            buttonIcon: "alt_route"
            text: Translation.tr("Only for addresses on this network")
        }
        RouteListEditor {
            visible: !["ignore", "disabled"].includes(page.ipv6Method)
            fieldKey: "ipv6.route-data"
        }
    }

    ContentSection {
        icon: "public"
        title: Translation.tr("Proxy")
        visible: ProfileEditor.active && (page.isWifi || page.isWired)

        ProfileCombo {
            fieldKey: "proxy.method"
            defaultValue: 0
            icon: "public"
            text: Translation.tr("Proxy")
            options: [
                { displayName: Translation.tr("None"), value: 0 },
                { displayName: Translation.tr("Automatic configuration"), value: 1 },
            ]
        }
        ProfileTextField {
            visible: ProfileEditor.value("proxy.method", 0) === 1
            fieldKey: "proxy.pac-url"
            label: Translation.tr("Configuration address (PAC)")
            placeholderText: "http://example.com/proxy.pac"
        }
        ProfileSwitch {
            visible: ProfileEditor.value("proxy.method", 0) === 1
            fieldKey: "proxy.browser-only"
            buttonIcon: "language"
            text: Translation.tr("Only for web browsers")
        }
    }

    ContentSection {
        icon: "list"
        title: Translation.tr("All settings")
        description: Translation.tr("Everything NetworkManager stores about this connection, as it stores it")
        visible: ProfileEditor.active && !ProfileEditor.isNew

        ConfigNavRow {
            buttonIcon: page.showAll ? "expand_less" : "expand_more"
            title: page.showAll ? Translation.tr("Hide") : Translation.tr("Show all %1").arg(page.allKeys.length)
            trailingIcon: ""
            onClicked: page.showAll = !page.showAll
        }
        Repeater {
            model: page.showAll ? page.allKeys : []
            delegate: ProfileTextField {
                required property var modelData
                readonly property var stored: ProfileEditor.fields[modelData]
                fieldKey: modelData
                label: modelData
                monospace: true
                enabled: ["string", "number", "boolean"].includes(typeof stored)
                visible: stored !== null
                placeholderText: typeof stored === "object" ? JSON.stringify(stored) : ""
            }
        }
    }

    RowLayout {
        visible: ProfileEditor.active
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: ProfileEditor.saving ? Translation.tr("Saving…")
                : ProfileEditor.dirty ? Translation.tr("You have unsaved changes")
                : ProfileEditor.justSaved ? Translation.tr("Saved")
                : ""
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
        DialogButton {
            buttonText: Translation.tr("Back")
            onClicked: page.goBack()
        }
        DialogButton {
            enabled: ProfileEditor.dirty && !ProfileEditor.saving
            buttonText: Translation.tr("Discard changes")
            onClicked: ProfileEditor.discard()
        }
        DialogButton {
            enabled: (ProfileEditor.dirty || ProfileEditor.isNew) && !ProfileEditor.saving
            buttonText: Translation.tr("Save")
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            colEnabled: Appearance.colors.colOnPrimary
            onClicked: ProfileEditor.save()
        }
    }
}
