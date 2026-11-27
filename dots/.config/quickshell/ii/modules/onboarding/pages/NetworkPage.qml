pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.onboarding
import qs.modules.settings.network
import QtQuick
import QtQuick.Layouts

/**
 * Only without a connection: nearby Wi-Fi networks. Can always be skipped; without a network the
 * extras and online wallpapers just wait.
 */
PageScaffold {
    id: root
    title: Translation.tr("Connect to the internet")
    subtitle: Translation.tr("For wallpapers, weather and extras. You can skip this and connect later.")
    scrollable: true

    Component.onCompleted: {
        Network.enableWifi(true);
        Network.rescanWifi(true);
    }

    Reveal {
        order: 1
        visible: Network.wifi || Network.ethernet
        RowLayout {
            width: parent.width
            spacing: 10
            MaterialSymbol {
                text: "check_circle"
                iconSize: 24
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Connected to %1").arg(Network.networkName)
                textFormat: Text.PlainText
                color: Appearance.colors.colOnLayer0
            }
        }
    }

    Repeater {
        model: Network.friendlyWifiNetworks.slice(0, 12)

        delegate: Reveal {
            id: entry
            required property var modelData
            required property int index
            order: 2 + Math.min(entry.index, 8)
            readonly property bool asking: Network.passwordPromptKey !== "" && Network.passwordPromptKey === modelData.key
            readonly property bool connecting: Network.connectionPending && Network.wifiConnectKey === modelData.key

            Rectangle {
                width: parent.width
                implicitHeight: entryColumn.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: entry.modelData.active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                ColumnLayout {
                    id: entryColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 12
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        MaterialSymbol {
                            text: Network.strengthSymbol(entry.modelData.strength)
                            iconSize: 22
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: entry.modelData.ssid
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer1
                        }
                        MaterialSymbol {
                            visible: entry.modelData.isSecure
                            text: "lock"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                        }
                        RippleButton {
                            visible: !entry.modelData.active && (!entry.asking || (entry.connecting && !Network.awaitingPassword))
                            enabled: !Network.connectionPending
                            implicitHeight: 32
                            implicitWidth: connectText.implicitWidth + 24
                            buttonRadius: height / 2
                            colBackground: Appearance.colors.colLayer2
                            onClicked: Network.connectToWifiNetwork(entry.modelData)
                            contentItem: StyledText {
                                id: connectText
                                horizontalAlignment: Text.AlignHCenter
                                text: entry.connecting ? Translation.tr("Connecting…") : Translation.tr("Connect")
                            }
                        }
                    }
                    // The password, right under its network
                    Loader {
                        active: entry.asking
                        visible: active
                        Layout.fillWidth: true
                        sourceComponent: PasswordForm {
                            acceptText: Translation.tr("Join")
                            errorText: entry.modelData.errorText ?? ""
                            busy: entry.connecting && !Network.awaitingPassword
                            onAccepted: password => Network.changePassword(entry.modelData, password)
                            onCanceled: Network.cancelPasswordPrompt()
                        }
                    }
                    StyledText {
                        visible: !entry.asking && (entry.modelData.errorText ?? "").length > 0
                        Layout.fillWidth: true
                        text: entry.modelData.errorText ?? ""
                        textFormat: Text.PlainText
                        color: Appearance.colors.colError
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
