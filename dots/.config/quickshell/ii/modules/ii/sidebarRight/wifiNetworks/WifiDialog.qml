import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 600
    readonly property WifiAccessPoint passwordNetwork: Network.wifiNetworks.find(network => network.ssid === Network.passwordPromptSsid) ?? null
    readonly property WifiAccessPoint credentialErrorNetwork: Network.wifiNetworks.find(network => network.ssid === Network.credentialErrorSsid) ?? null

    WindowDialogTitle {
        text: Translation.tr("Network connections")
    }
    DialogButton {
        visible: !Network.wifiEnabled
        Layout.fillWidth: true
        buttonText: Translation.tr("Turn on Wi-Fi")
        onClicked: Network.enableWifi()
    }
    WindowDialogSeparator {
        visible: !Network.wifiScanning
    }
    RowLayout {
        Layout.fillWidth: true
        visible: Network.ethernet
        spacing: 12
        MaterialSymbol {
            text: "lan"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                text: Translation.tr("Ethernet")
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                text: Translation.tr("Connected")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
        MaterialSymbol {
            text: "check"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
    WindowDialogSeparator {
        visible: Network.ethernet
    }
    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }
    // A Repeater, not a ListView: when a scan re-sorts the networks while some rows are out of view,
    // the ListView creates and drops delegates during the row move and Qt 6.11 crashes the shell
    // (QQmlDelegateModel::_q_itemsMoved)
    StyledFlickable {
        id: networkList
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
        clip: true
        contentWidth: width
        contentHeight: networkColumn.implicitHeight

        Column {
            id: networkColumn
            width: networkList.width
            Repeater {
                model: ScriptModel {
                    values: Network.friendlyWifiNetworks
                }
                // The password is asked for right under the network that needs it
                delegate: ColumnLayout {
                    id: networkEntry
                    required property WifiAccessPoint modelData
                    width: networkColumn.width
                    spacing: 0
                    WifiNetworkItem {
                        Layout.fillWidth: true
                        wifiNetwork: networkEntry.modelData
                    }
                    ColumnLayout {
                        visible: networkEntry.modelData?.askingPassword ?? false
                        Layout.fillWidth: true
                        Layout.leftMargin: Appearance.rounding.large + 30
                        Layout.rightMargin: Appearance.rounding.large
                        Layout.bottomMargin: 10
                        spacing: 6
                        onVisibleChanged: {
                            passwordField.text = "";
                            if (visible) passwordField.forceActiveFocus();
                        }
                        MaterialTextField {
                            id: passwordField
                            Layout.fillWidth: true
                            enabled: !Network.connectionPending
                            placeholderText: Translation.tr("Password for %1").arg(networkEntry.modelData?.ssid ?? "")
                            echoMode: TextInput.Password
                            inputMethodHints: Qt.ImhSensitiveData
                            onAccepted: if (text.length > 0) Network.changePassword(networkEntry.modelData, text)
                            Keys.onEscapePressed: Network.cancelPasswordPrompt()
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            wrapMode: Text.Wrap
                            text: networkEntry.modelData?.errorText ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colError
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            DialogButton {
                                buttonText: Translation.tr("Cancel")
                                enabled: !Network.connectionPending
                                onClicked: Network.cancelPasswordPrompt()
                            }
                            DialogButton {
                                buttonText: Translation.tr("Connect")
                                enabled: passwordField.text.length > 0 && !Network.connectionPending
                                onClicked: Network.changePassword(networkEntry.modelData, passwordField.text)
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            parent: networkList // Stays put while the list scrolls
            anchors.centerIn: parent
            visible: Network.friendlyWifiNetworks.length === 0
            text: Network.wifiEnabled ? Translation.tr("No Wi-Fi networks") : Translation.tr("Wi-Fi is off")
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: text.length > 0
        wrapMode: Text.Wrap
        color: Appearance.colors.colError
        text: Network.snapshotError || (root.passwordNetwork ? "" : Network.wifiErrorMessage) // Password errors show at the network
        textFormat: Text.PlainText
    }
    DialogButton {
        Layout.fillWidth: true
        visible: root.credentialErrorNetwork !== null
        buttonText: Translation.tr("Update saved password")
        onClicked: Network.requestPasswordUpdate()
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
                GlobalStates.closeSidebars();
            }
        }
        Item { Layout.fillWidth: true }
        DialogButton {
            visible: Network.active !== null
            buttonText: Translation.tr("Disconnect Wi-Fi")
            onClicked: Network.disconnectWifiNetwork()
        }
        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
