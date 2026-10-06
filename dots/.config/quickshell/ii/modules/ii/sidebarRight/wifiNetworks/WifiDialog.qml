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
    ListView {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
        clip: true
        spacing: 0
        model: ScriptModel {
            values: Network.friendlyWifiNetworks
        }
        delegate: WifiNetworkItem {
            required property WifiAccessPoint modelData
            wifiNetwork: modelData
            width: ListView.view.width
        }
        StyledText {
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
        text: Network.snapshotError || Network.wifiErrorMessage
        textFormat: Text.PlainText
    }
    DialogButton {
        Layout.fillWidth: true
        visible: root.credentialErrorNetwork !== null
        buttonText: Translation.tr("Update saved password")
        onClicked: Network.requestPasswordUpdate()
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.passwordNetwork !== null
        spacing: 8
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: Translation.tr("Password for %1").arg(root.passwordNetwork?.ssid ?? "")
            color: Appearance.colors.colOnSurfaceVariant
        }
        MaterialTextField {
            id: passwordField
            Layout.fillWidth: true
            enabled: !Network.connectionPending
            placeholderText: Translation.tr("Password")
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData
            onAccepted: {
                if (root.passwordNetwork) Network.changePassword(root.passwordNetwork, text);
            }
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
                onClicked: {
                    if (root.passwordNetwork) Network.changePassword(root.passwordNetwork, passwordField.text);
                }
            }
        }
        onVisibleChanged: {
            if (!visible) passwordField.text = "";
        }
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
                GlobalStates.sidebarRightOpen = false;
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
