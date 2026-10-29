pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.onboarding
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
            readonly property bool asking: Network.passwordPromptSsid === modelData.ssid

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
                            visible: !entry.modelData.active
                            implicitHeight: 32
                            implicitWidth: connectText.implicitWidth + 24
                            buttonRadius: height / 2
                            colBackground: Appearance.colors.colLayer2
                            onClicked: Network.connectToWifiNetwork(entry.modelData)
                            contentItem: StyledText {
                                id: connectText
                                horizontalAlignment: Text.AlignHCenter
                                text: Network.wifiConnecting && Network.wifiConnectSsid === entry.modelData.ssid
                                    ? Translation.tr("Connecting…") : Translation.tr("Connect")
                            }
                        }
                    }
                    // The password, right under its network
                    RowLayout {
                        visible: entry.asking
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 40
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            TextInput {
                                id: password
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: Text.AlignVCenter
                                echoMode: TextInput.Password
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.normal
                                onVisibleChanged: if (visible) forceActiveFocus()
                                onAccepted: Network.changePassword(entry.modelData, text)
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: password.text.length === 0
                                    text: Translation.tr("Password")
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                        RippleButton {
                            implicitHeight: 40
                            implicitWidth: joinText.implicitWidth + 28
                            buttonRadius: height / 2
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: Network.changePassword(entry.modelData, password.text)
                            contentItem: StyledText {
                                id: joinText
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("Join")
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                    StyledText {
                        visible: (entry.modelData.errorText ?? "").length > 0
                        Layout.fillWidth: true
                        text: entry.modelData.errorText ?? ""
                        color: Appearance.colors.colError
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
