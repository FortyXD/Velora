import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.network

ContentPage {
    id: page
    readonly property var current: Network.active
    // Keep the rows when a scan changes signal levels without changing their order.
    property var nearby: []
    function updateNearby(): void {
        const networks = Network.wifiNetworks.filter(network => !network.active).sort((a, b) =>
            Number(b.known) - Number(a.known) || b.strength - a.strength || a.ssid.localeCompare(b.ssid));
        if (networks.length !== page.nearby.length || networks.some((network, index) => network !== page.nearby[index])) page.nearby = networks;
    }
    property string query: ""
    readonly property var matching: page.query.trim().length === 0 ? page.nearby
        : page.nearby.filter(network => network.ssid.toLowerCase().includes(page.query.trim().toLowerCase()))
    property bool currentExpanded: false
    onCurrentChanged: page.currentExpanded = false
    onCurrentExpandedChanged: if (!page.currentExpanded) {
        page.changingPassword = false;
        currentPassword.clear();
    }
    onPageShownChanged: if (!page.pageShown) page.currentExpanded = false

    // Which saved networks to list, by UUID. A row reads its own details, so this only changes when the
    // list does, not with every signal level, and open rows stay open.
    property string savedQuery: ""
    property var savedKeys: []
    function updateSavedKeys(): void {
        const needle = page.savedQuery.trim().toLowerCase();
        const keys = Network.savedNetworks.filter(profile => needle.length === 0 || profile.ssid.toLowerCase().includes(needle) || profile.id.toLowerCase().includes(needle)).map(profile => profile.uuid);
        if (keys.length !== page.savedKeys.length || keys.some((key, index) => key !== page.savedKeys[index])) page.savedKeys = keys;
    }
    onSavedQueryChanged: page.updateSavedKeys()
    Connections {
        target: Network
        function onWifiNetworksChanged() {
            page.updateNearby();
        }
        function onStateChanged() {
            Qt.callLater(page.updateNearby);
        }
        function onSavedNetworksChanged() {
            page.updateSavedKeys();
        }
    }
    Component.onCompleted: {
        page.updateNearby();
        page.updateSavedKeys();
    }

    readonly property var details: Network.state.wifiDetails ?? null
    readonly property var ethernetDevice: Network.state.ethernetDetails
        ?? (Network.state.devices ?? []).find(device => device.deviceType === 1) ?? null
    readonly property var currentSaved: page.current ? (Network.profileByUuid[page.current.savedUuid] ?? null) : null

    // Sharing the connection
    property string hotspotError: ""
    property bool hotspotStarting: false
    property bool changingPassword: false
    property bool joiningHidden: false

    function signalWord(strength) {
        return strength > 70 ? Translation.tr("Strong signal") : strength > 40 ? Translation.tr("Good signal") : Translation.tr("Weak signal");
    }

    // A fresh list as soon as the page is shown, then every half a minute while it stays open
    Timer {
        interval: 30000
        repeat: true
        running: page.pageShown && Network.wifiEnabled
        triggeredOnStart: true
        onTriggered: Network.rescanWifi()
    }

    NoticeBox {
        visible: Network.snapshotError.length > 0
        Layout.fillWidth: true
        materialIcon: "error"
        text: Network.snapshotError
    }

    NoticeBox {
        visible: Network.available && !Network.wifiHardwareEnabled
        Layout.fillWidth: true
        materialIcon: "airplanemode_active"
        text: Translation.tr("Wi-Fi is turned off by a switch or key on this computer.")
    }

    NoticeBox {
        visible: Network.connectivity === "portal"
        Layout.fillWidth: true
        materialIcon: "login"
        text: Translation.tr("This network wants you to sign in before it gives you internet access.")
        DialogButton {
            buttonText: Translation.tr("Open sign-in page")
            onClicked: Network.openPublicWifiPortal()
        }
    }

    ConnectionHeader {
        icon: !Network.wifiEnabled ? "wifi_off" : page.current ? Network.strengthSymbol(page.current.strength) : "wifi"
        iconColor: page.heroColor
        busy: Network.wifiConnecting
        title: Translation.tr("Wi-Fi")
        subtitle: !Network.wifiEnabled ? Translation.tr("Off")
            : Network.wifiConnecting ? Translation.tr("Connecting…")
            : page.current ? page.current.ssid
            : Translation.tr("Not connected")
        detail: !Network.wifiEnabled ? Translation.tr("Turn it on to see the networks around you")
            : page.current ? [page.signalWord(page.current.strength), Network.frequencyBand(page.current.frequency), page.current.isSecure ? Translation.tr("Secured") : Translation.tr("Open network")].filter(part => part.length > 0).join(" · ")
            : Translation.tr("%1 networks nearby").arg(page.nearby.length)
        checked: Network.wifiEnabled
        switchLabel: Translation.tr("Turn Wi-Fi on or off")
        onToggled: Network.enableWifi(!Network.wifiEnabled)

        ConfigSwitch {
            buttonIcon: "airplanemode_active"
            text: Translation.tr("Airplane mode")
            description: Translation.tr("Turns off Wi-Fi, mobile data and Bluetooth, and brings back only what was on")
            autoToggle: false
            checked: Network.airplaneMode
            onClicked: Network.setAirplaneMode(!Network.airplaneMode)
        }
    }

    ContentSection {
        icon: "wifi"
        title: Translation.tr("This network")
        visible: page.current !== null

        ConfigNavRow {
            objectName: "currentNetworkSummary"
            buttonIcon: page.current ? Network.strengthSymbol(page.current.strength) : "wifi"
            title: page.current?.ssid ?? ""
            description: Translation.tr("Connected")
            valueText: page.current ? `${page.current.strength}% · ${page.signalWord(page.current.strength)}` : ""
            trailingIcon: "expand_more"
            trailingIconRotation: page.currentExpanded ? 180 : 0
            onClicked: page.currentExpanded = !page.currentExpanded
        }

        NetworkRevealer {
            objectName: "currentNetworkDetails"
            expanded: page.currentExpanded
            animationsEnabled: page.pageShown
            onExpandRequested: page.currentExpanded = true
            spacing: 0

            InfoRow {
                buttonIcon: "language"
                title: Translation.tr("IP address")
                valueText: (Network.wifiDetails.ip ?? "").split("/")[0]
            }
            InfoRow {
                buttonIcon: "router"
                title: Translation.tr("Router")
                valueText: Network.wifiDetails.gateway ?? ""
            }
            InfoRow {
                buttonIcon: "dns"
                title: Translation.tr("DNS servers")
                valueText: (Network.wifiDetails.dns ?? []).join(", ")
            }
            InfoRow {
                buttonIcon: page.current ? Network.strengthSymbol(page.current.strength) : "wifi"
                title: Translation.tr("Signal")
                valueText: page.current ? `${page.current.strength}% · ${Network.frequencyBand(page.current.frequency)}` : ""
            }
            InfoRow {
                buttonIcon: "encrypted"
                title: Translation.tr("Security")
                valueText: page.current ? (page.current.security || Translation.tr("None")) : ""
            }
            InfoRow {
                buttonIcon: "speed"
                title: Translation.tr("Link speed")
                valueText: (page.details?.speed ?? 0) > 0 ? Translation.tr("%1 Mbit/s").arg(page.details.speed) : ""
            }
            InfoRow {
                buttonIcon: "tag"
                title: Translation.tr("Channel")
                valueText: (page.current?.lastIpcObject.channel ?? 0) > 0 ? `${page.current.lastIpcObject.channel}` : ""
            }
            InfoRow {
                buttonIcon: "router"
                title: Translation.tr("Access point (BSSID)")
                valueText: page.current?.bssid ?? ""
            }
            InfoRow {
                buttonIcon: "memory"
                title: Translation.tr("This computer's address (MAC)")
                valueText: page.details?.hwAddress ?? ""
            }
            InfoRow {
                buttonIcon: "language"
                title: Translation.tr("IPv6 address")
                valueText: (page.details?.ip6.addresses ?? []).join(", ")
            }
            InfoRow {
                buttonIcon: "dns"
                title: Translation.tr("IPv6 DNS servers")
                valueText: (page.details?.ip6.dns ?? []).join(", ")
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 8
                spacing: 6
                DialogButton {
                    buttonText: Translation.tr("Disconnect")
                    onClicked: Network.disconnectWifiNetwork()
                }
                DialogButton {
                    visible: (page.current?.isSecure ?? false) && (page.current?.savedUuid ?? "").length > 0
                    buttonText: Translation.tr("Change password")
                    onClicked: page.changingPassword = !page.changingPassword
                }
                DialogButton {
                    visible: (page.current?.savedUuid ?? "").length > 0
                    buttonText: Translation.tr("Edit")
                    onClicked: Network.editProfile(page.current.savedUuid)
                }
                Item {
                    Layout.fillWidth: true
                }
                ForgetButton {
                    visible: (page.current?.savedUuid ?? "").length > 0
                    label: Translation.tr("Forget this network")
                    onConfirmed: Network.forgetWifiNetwork(page.current.savedUuid)
                }
            }

            SavedPasswordBox {
                id: currentPassword
                visible: page.current !== null && ["wep", "wpa-psk", "sae"].includes(page.currentSaved?.securityType ?? "")
                uuid: page.current?.savedUuid ?? ""
                Layout.fillWidth: true
                Layout.margins: 12
                Connections {
                    target: page
                    function onPageShownChanged() {
                        if (!page.pageShown) currentPassword.clear();
                    }
                }
            }

            NetworkRevealer {
                id: currentPasswordDetails
                expanded: page.changingPassword && page.current !== null
                animationsEnabled: page.pageShown
                onExpandRequested: page.changingPassword = true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                bottomPadding: 12

                Loader {
                    active: currentPasswordDetails.visible
                    Layout.fillWidth: true
                    sourceComponent: PasswordForm {
                        acceptText: Translation.tr("Save")
                        placeholderText: Translation.tr("New password")
                        busy: Network.connectionPending
                        onAccepted: password => {
                            Network.changePassword(page.current, password);
                            page.changingPassword = false;
                        }
                        onCanceled: page.changingPassword = false
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "cable"
        title: Translation.tr("Ethernet")
        visible: page.ethernetDevice !== null

        ConfigNavRow {
            buttonIcon: "lan"
            tileColor: page.heroColor
            title: page.ethernetDevice?.interface || Translation.tr("Ethernet")
            valueText: Translation.tr("Enabled")
            description: Network.ethernet ? Translation.tr("Connected") : Translation.tr("Not connected")
            onClicked: ApplicationWindow.window?.openPage("connections")
        }

        InfoRow {
            buttonIcon: "lan"
            title: Translation.tr("IP address")
            valueText: (Network.ethernetDetails.ip ?? "").split("/")[0]
        }
        InfoRow {
            buttonIcon: "router"
            title: Translation.tr("Router")
            valueText: Network.ethernetDetails.gateway ?? ""
        }
    }

    ContentSection {
        icon: "wifi_find"
        title: Translation.tr("Networks nearby")
        description: Translation.tr("Click a network to join it. Networks you joined before are remembered and joined again by themselves.")

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 6
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                text: !Network.wifiEnabled ? Translation.tr("Wi-Fi is off")
                    : Network.wifiScanning ? Translation.tr("Looking for networks…")
                    : page.nearby.length === 0 ? Translation.tr("No other networks found")
                    : Translation.tr("%1 networks").arg(page.nearby.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            DialogButton {
                visible: !Network.wifiEnabled
                buttonText: Translation.tr("Turn on")
                onClicked: Network.enableWifi(true)
            }
            RippleButton {
                id: refreshButton
                visible: Network.wifiEnabled
                enabled: !Network.wifiScanning
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                colBackgroundHover: Appearance.colors.colLayer3Hover
                onClicked: Network.rescanWifi(true)
                contentItem: StatusIcon {
                    text: "refresh"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                    busy: Network.wifiScanning
                }
                StyledToolTip {
                    text: Translation.tr("Look again")
                }
            }
        }

        SearchField {
            visible: Network.wifiEnabled && page.nearby.length > 6
            placeholderText: Translation.tr("Find a network")
            onTextChanged: page.query = text
        }

        ContentSubsection {
            visible: Network.wifiEnabled && page.matching.length > 0
            Repeater {
                model: page.matching
                delegate: WifiNetworkRow {
                    required property var modelData
                    network: modelData
                }
            }
        }
        StyledText {
            visible: Network.wifiEnabled && page.query.length > 0 && page.matching.length === 0
            Layout.fillWidth: true
            Layout.margins: 10
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("No network called “%1” nearby").arg(page.query.trim())
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        id: hotspotSection
        icon: "wifi_tethering"
        title: Translation.tr("Share this connection")
        description: Translation.tr("Turns this computer into a Wi-Fi hotspot. On most computers that disconnects it from the Wi-Fi network it's using now.")
        visible: Network.canShareConnection

        ConfigTextRow {
            id: hotspotName
            visible: !Network.hotspotActive
            label: Translation.tr("Hotspot name")
            placeholderText: "Velora"
            wrapMode: TextEdit.NoWrap
        }
        Loader {
            active: !Network.hotspotActive
            visible: active
            Layout.fillWidth: true
            Layout.margins: 12
            sourceComponent: PasswordForm {
                focusOnShow: false
                allowEmpty: true
                acceptText: Translation.tr("Start sharing")
                placeholderText: Translation.tr("Password, or none for an open hotspot")
                busy: page.hotspotStarting
                errorText: page.hotspotError
                onAccepted: password => {
                    page.hotspotError = "";
                    page.hotspotStarting = true;
                    Network.startHotspot(hotspotName.value.trim() || "Velora", password, error => {
                        page.hotspotStarting = false;
                        if (error) page.hotspotError = Translation.tr(error.message);
                    });
                }
                onCanceled: page.hotspotError = ""
            }
        }
        RowLayout {
            visible: Network.hotspotActive
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Sharing this computer's connection over Wi-Fi")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            DialogButton {
                buttonText: Translation.tr("Stop sharing")
                onClicked: Network.stopHotspot()
            }
        }
    }

    ContentSection {
        icon: "more_horiz"
        title: Translation.tr("More")

        ConfigNavRow {
            buttonIcon: "visibility_off"
            title: Translation.tr("Join a hidden network")
            description: Translation.tr("For networks that don't show their name")
            trailingIcon: "expand_more"
            trailingIconRotation: page.joiningHidden ? 180 : 0
            enabled: Network.wifiEnabled
            onClicked: page.joiningHidden = !page.joiningHidden
        }
        NetworkRevealer {
            id: hiddenNetworkDetails
            expanded: page.joiningHidden
            animationsEnabled: page.pageShown
            onExpandRequested: page.joiningHidden = true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            bottomPadding: 12
            spacing: 8
            ConfigTextRow {
                id: hiddenName
                Layout.leftMargin: 0
                Layout.rightMargin: 0
                placeholderText: Translation.tr("Network name")
                wrapMode: TextEdit.NoWrap
            }
            Loader {
                active: hiddenNetworkDetails.visible
                Layout.fillWidth: true
                sourceComponent: PasswordForm {
                    focusOnShow: false
                    allowEmpty: true
                    acceptText: Translation.tr("Join")
                    placeholderText: Translation.tr("Password, if it has one")
                    busy: Network.connectionPending
                    errorText: Network.wifiConnectSsid === "" && hiddenName.value.length > 0 ? Network.wifiErrorMessage : ""
                    onAccepted: password => Network.connectToHiddenNetwork(hiddenName.value.trim(), password)
                    onCanceled: page.joiningHidden = false
                }
            }
        }
        ConfigNavRow {
            buttonIcon: "tune"
            title: Translation.tr("All connections")
            description: Translation.tr("VPN, cable, fixed addresses, proxy and everything else about your connections")
            onClicked: ApplicationWindow.window?.openPage("connections")
        }
    }

    ContentSection {
        id: savedSection
        icon: "bookmark"
        title: Translation.tr("Saved passwords")
        description: Translation.tr("Passwords and settings for the Wi-Fi networks this computer remembers.")
        visible: Network.savedNetworks.length > 0

        SearchField {
            visible: Network.savedNetworks.length > 6
            placeholderText: Translation.tr("Find a saved network")
            onTextChanged: page.savedQuery = text
        }

        Repeater {
            model: page.savedKeys
            delegate: SavedNetworkRow {
                required property var modelData
                uuid: modelData
                pageShown: page.pageShown
            }
        }

        StyledText {
            visible: page.savedKeys.length === 0
            Layout.fillWidth: true
            Layout.margins: 10
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("No saved network called “%1”").arg(page.savedQuery.trim())
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    component SearchField: TextField {
        id: searchField
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        placeholderTextColor: Appearance.colors.colSubtext
        color: Appearance.colors.colOnLayer2
        leftPadding: 14
        topPadding: 9
        bottomPadding: 9
        font.pixelSize: Appearance.font.pixelSize.small
        background: Rectangle {
            implicitHeight: 38
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3
            border.width: searchField.activeFocus ? 2 : 0
            border.color: Appearance.colors.colPrimary
        }
    }
}
