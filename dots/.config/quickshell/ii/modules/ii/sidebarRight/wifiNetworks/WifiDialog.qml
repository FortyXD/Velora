import qs
import qs.services
import qs.modules.settings.network
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 600
    // WindowDialog fades instead of destroying its children. Closing it must
    // discard the password field and the outstanding request.
    onShowChanged: if (!show && Network.connectionPending) Network.cancelPasswordPrompt()
    readonly property WifiAccessPoint passwordNetwork: Network.wifiNetworks.find(network => network.ssid === Network.passwordPromptSsid) ?? null

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
                        id: entryButton
                        Layout.fillWidth: true
                        wifiNetwork: networkEntry.modelData
                    }
                    RowLayout {
                        visible: Network.failedNetworkKey === networkEntry.modelData.key
                        Layout.fillWidth: true
                        Layout.leftMargin: Appearance.rounding.large + 30
                        Layout.rightMargin: Appearance.rounding.large
                        Layout.bottomMargin: 10
                        StyledText {
                            Layout.fillWidth: true
                            text: Network.wifiErrorMessage
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colError
                        }
                        DialogButton {
                            buttonText: Translation.tr("Try again")
                            onClicked: Network.connectToWifiNetwork(networkEntry.modelData)
                        }
                    }
                    Loader {
                        active: root.show && Network.connectionPending && Network.operationKey === networkEntry.modelData.key
                        visible: active
                        Layout.fillWidth: true
                        Layout.leftMargin: Appearance.rounding.large + 30
                        Layout.rightMargin: Appearance.rounding.large
                        Layout.bottomMargin: 10
                        sourceComponent: PasswordForm {
                            errorText: Network.wifiErrorMessage
                            busy: !Network.awaitingPassword
                            promptToken: Network.secretRequest
                            onAccepted: password => Network.submitPassword(password)
                            onCanceled: { Network.cancelPasswordPrompt(); entryButton.forceActiveFocus(); }
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
        text: Network.snapshotError || (root.passwordNetwork || Network.failedNetworkKey ? "" : Network.wifiErrorMessage) // Password errors show at the network
        textFormat: Text.PlainText
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        Layout.fillWidth: true
        DialogButton {
            Layout.fillWidth: true
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["env", "QS_SETTINGS_PAGE=wifi", "QS_SETTINGS_SEARCH=", "qs", "-p", Quickshell.shellPath("settings.qml")]);
                GlobalStates.closeSidebars();
            }
        }
    }
}
