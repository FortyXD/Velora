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
    readonly property var nearby: Network.friendlyWifiNetworks.filter(network => !network.active)
    // Search, then two groups: networks you joined before, and the rest (new, or saved but never joined)
    property string query: ""
    readonly property var matching: page.query.trim().length === 0 ? page.nearby
        : page.nearby.filter(network => network.ssid.toLowerCase().includes(page.query.trim().toLowerCase()))
    readonly property var knownNearby: page.matching.filter(network => network.known)
    readonly property var otherNearby: page.matching.filter(network => !network.known)
    property bool showAllSaved: false
    property bool showAllNearby: false // The strongest few first: two dozen rows took over half a second to build
    property bool joiningHidden: false

    function signalWord(strength) {
        return strength > 70 ? Translation.tr("Strong signal") : strength > 40 ? Translation.tr("Good signal") : Translation.tr("Weak signal");
    }

    Component.onCompleted: Network.trackDetails = true
    // Settings pages stay instantiated behind each other: never retain a
    // partially entered or revealed password on a hidden page.
    onPageShownChanged: if (!pageShown) {
        if (Network.connectionPending) Network.cancelPasswordPrompt();
        page.joiningHidden = false;
    }

    // A fresh list as soon as the page is shown, then every half a minute while it stays open
    Timer {
        interval: 30000
        repeat: true
        running: page.pageShown && Network.wifiEnabled
        triggeredOnStart: true
        onTriggered: Network.rescanWifi()
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
    }

    ContentSection {
        icon: "wifi"
        title: Translation.tr("This network")
        visible: page.current !== null

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

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 8
            spacing: 6
            DialogButton {
                buttonText: Translation.tr("Disconnect")
                onClicked: Network.disconnectWifiNetwork()
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


    }

    StyledText {
        Layout.fillWidth: true
        visible: text.length > 0 && !Network.awaitingPassword && !Network.failedNetworkKey && !(page.joiningHidden && Network.operationHidden)
        text: Network.snapshotError || Network.wifiErrorMessage
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Appearance.colors.colError
    }

    ContentSection {
        icon: "cable"
        title: Translation.tr("Ethernet")
        visible: Network.ethernet

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
        description: Translation.tr("Click a network to join it. Saved networks may ask for a password again.")

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
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "refresh"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                    RotationAnimation on rotation {
                        running: Network.wifiScanning
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1000
                        onStopped: parent.rotation = 0
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Look again")
                }
            }
        }

        TextField {
            id: networkSearch
            visible: Network.wifiEnabled && page.nearby.length > 6
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            placeholderText: Translation.tr("Find a network")
            placeholderTextColor: Appearance.colors.colSubtext
            color: Appearance.colors.colOnLayer2
            leftPadding: 14
            topPadding: 9
            bottomPadding: 9
            font.pixelSize: Appearance.font.pixelSize.small
            onTextChanged: page.query = text
            background: Rectangle {
                implicitHeight: 38
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer3
                border.width: networkSearch.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
            }
        }

        ContentSubsection {
            visible: Network.wifiEnabled && page.knownNearby.length > 0
            title: Translation.tr("Your networks")
            Repeater {
                model: page.knownNearby
                delegate: WifiNetworkRow {
                    required property var modelData
                    network: modelData
                }
            }
        }
        ContentSubsection {
            visible: Network.wifiEnabled && page.otherNearby.length > 0
            title: Translation.tr("Other networks")
            Repeater {
                model: page.showAllNearby || page.query.length > 0 ? page.otherNearby : page.otherNearby.slice(0, 8)
                delegate: WifiNetworkRow {
                    required property var modelData
                    network: modelData
                }
            }
            ConfigNavRow {
                visible: page.otherNearby.length > 8 && page.query.length === 0
                buttonIcon: page.showAllNearby ? "expand_less" : "expand_more"
                title: page.showAllNearby ? Translation.tr("Show fewer") : Translation.tr("Show all %1").arg(page.otherNearby.length)
                trailingIcon: ""
                onClicked: page.showAllNearby = !page.showAllNearby
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
        icon: "bookmark"
        title: Translation.tr("Saved networks")
        description: Translation.tr("Networks this computer remembers that are out of range right now.")
        visible: Network.savedOutOfRange.length > 0

        Repeater {
            model: page.showAllSaved ? Network.savedOutOfRange : Network.savedOutOfRange.slice(0, 5)
            delegate: RowLayout {
                id: savedRow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                Layout.leftMargin: 12
                Layout.rightMargin: 8
                spacing: 12
                ConfigIconTile {
                    icon: "wifi"
                }
                StyledText {
                    Layout.fillWidth: true
                    text: savedRow.modelData.ssid
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                ForgetButton {
                    onConfirmed: Network.forgetWifiNetwork(savedRow.modelData.uuid)
                }
            }
        }

        ConfigNavRow {
            visible: Network.savedOutOfRange.length > 5
            buttonIcon: page.showAllSaved ? "expand_less" : "expand_more"
            title: page.showAllSaved ? Translation.tr("Show fewer") : Translation.tr("Show all %1").arg(Network.savedOutOfRange.length)
            trailingIcon: ""
            onClicked: page.showAllSaved = !page.showAllSaved
        }
    }

    ContentSection {
        icon: "more_horiz"
        title: Translation.tr("More")

        ConfigNavRow {
            buttonIcon: "visibility_off"
            title: Translation.tr("Join a hidden network")
            description: Translation.tr("For networks that don't show their name")
            trailingIcon: page.joiningHidden ? "expand_less" : "expand_more"
            enabled: Network.wifiEnabled
            onClicked: {
                if (page.joiningHidden && Network.operationHidden) Network.cancelPasswordPrompt();
                page.joiningHidden = !page.joiningHidden;
            }
        }
        ColumnLayout {
            visible: page.joiningHidden
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 8
            ConfigTextRow {
                id: hiddenName
                enabled: !Network.connectionPending
                Layout.leftMargin: 0
                Layout.rightMargin: 0
                placeholderText: Translation.tr("Network name")
                wrapMode: TextEdit.NoWrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: Network.operationHidden && !Network.connectionPending && text.length > 0
                text: Network.wifiErrorMessage
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Appearance.colors.colError
            }
            ComboBox {
                id: hiddenSecurity
                Layout.fillWidth: true
                enabled: !Network.connectionPending
                model: [Translation.tr("WPA2 Personal"), Translation.tr("WPA3 Personal"), Translation.tr("Open network")]
            }
            DialogButton {
                visible: !Network.connectionPending
                buttonText: Translation.tr("Join")
                enabled: hiddenName.value.length > 0
                onClicked: Network.connectToHiddenNetwork(hiddenName.value, ["wpa-psk", "sae", "open"][hiddenSecurity.currentIndex])
            }
            Loader {
                active: Network.connectionPending && Network.operationHidden && page.pageShown
                visible: active
                Layout.fillWidth: true
                sourceComponent: PasswordForm {
                    busy: !Network.awaitingPassword
                    promptToken: Network.secretRequest
                    errorText: Network.wifiErrorMessage
                    onAccepted: password => Network.submitPassword(password)
                    onCanceled: { Network.cancelPasswordPrompt(); page.joiningHidden = false; }
                }
            }
        }
    }
}
