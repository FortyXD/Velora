import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets

/**
 * A Wi-Fi network in the settings list: signal, name and state; click to join it.
 * A secured network without a saved password asks for it right inside the row.
 */
ColumnLayout {
    id: root
    required property WifiAccessPoint network
    readonly property bool connecting: Network.connectionPending && Network.wifiConnectSsid === root.network.ssid
    readonly property bool rejected: Network.credentialErrorSsid === root.network.ssid
    readonly property bool saved: root.network.savedUuid.length > 0

    Layout.fillWidth: true
    spacing: 0

    RippleButton {
        id: rowButton
        Layout.fillWidth: true
        implicitHeight: 54
        leftPadding: 12
        rightPadding: 8
        buttonRadius: Appearance.rounding.small
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        enabled: Network.wifiEnabled && (!Network.connectionPending || root.connecting)
        onClicked: {
            if (!root.network.active && !root.network.askingPassword) Network.connectToWifiNetwork(root.network);
        }

        contentItem: RowLayout {
            spacing: 12

            ConfigIconTile {
                icon: Network.strengthSymbol(root.network.strength)
                active: root.network.active
                iconSize: 22
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: root.network.ssid
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.rejected ? Appearance.colors.colError : Appearance.colors.colSubtext
                    text: root.connecting ? Translation.tr("Connecting…")
                        : root.rejected ? Translation.tr("Saved password rejected")
                        : root.network.active ? Translation.tr("Connected")
                        : root.network.known ? Translation.tr("Joined before")
                        : root.network.isSecure ? Translation.tr("Needs a password")
                        : Translation.tr("Open network")
                }
            }

            StyledText {
                visible: rowButton.width > 420
                text: Network.frequencyBand(root.network.frequency)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StatusIcon {
                visible: root.connecting || (root.network.isSecure && !root.network.known)
                text: root.connecting ? "" : "lock"
                iconSize: 18
                color: Appearance.colors.colSubtext
                busy: root.connecting
            }

            ForgetButton {
                id: forgetButton
                // Keeps its place on every row so the columns line up; shown on hover only, so a list of
                // saved networks doesn't turn into a column of bins
                visible: !root.connecting
                enabled: root.saved
                opacity: root.saved && (rowButton.hovered || forgetButton.asking) ? 1 : 0
                onConfirmed: Network.forgetWifiNetwork(root.network.savedUuid)
            }
        }
    }

    // The saved password stopped working
    RowLayout {
        visible: root.rejected && !root.network.askingPassword
        Layout.fillWidth: true
        Layout.leftMargin: 50
        Layout.rightMargin: 12
        Layout.bottomMargin: 10
        spacing: 8
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The network didn't accept the saved password.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        DialogButton {
            buttonText: Translation.tr("Enter a new one")
            onClicked: Network.requestPasswordUpdate()
        }
    }

    Loader {
        active: root.network.askingPassword
        visible: active
        Layout.fillWidth: true
        Layout.leftMargin: 50
        Layout.rightMargin: 12
        Layout.bottomMargin: 12
        sourceComponent: PasswordForm {
            errorText: root.network.errorText
            busy: root.connecting
            onAccepted: password => Network.changePassword(root.network, password)
            onCanceled: Network.cancelPasswordPrompt()
        }
    }
}
