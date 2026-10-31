import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A saved Wi-Fi network, whether it is around or not: what protocol it uses and when it was last joined.
 * Clicking unfolds its password, a QR code for phones, and the connection controls.
 */
ColumnLayout {
    id: root
    required property string uuid
    property bool pageShown: true
    readonly property var profile: Network.profileByUuid[root.uuid] ?? null
    readonly property var accessPoint: Network.wifiNetworks.find(network => network.savedUuid === root.uuid) ?? null
    readonly property string name: root.profile?.ssid || root.profile?.id || ""
    readonly property bool active: (root.profile?.activeState ?? 0) === 2
    readonly property bool connecting: (Network.connectionPending && Network.wifiConnectSsid === root.name) || (root.profile?.activeState ?? 0) === 1
    readonly property bool inRange: root.profile?.inRange ?? false
    readonly property bool rejected: Network.credentialErrorSsid === root.name
    readonly property bool asking: (root.accessPoint?.askingPassword ?? false) || root.changingPassword || root.connecting
    readonly property bool hasPassword: ["wep", "wpa-psk", "sae"].includes(root.profile?.securityType ?? "")
    property bool expanded: false
    property bool changingPassword: false
    readonly property alias passwordBox: passwordBox
    readonly property string statusText: root.connecting ? Translation.tr("Connecting…")
        : root.rejected ? Translation.tr("Saved password rejected")
        : root.active ? Translation.tr("Connected")
        : (root.profile?.timestamp ?? 0) === 0 ? Translation.tr("Never connected")
        : root.inRange ? Translation.tr("In range")
        : Translation.tr("Out of range")

    function lastUsedText(): string {
        const seconds = root.profile?.timestamp ?? 0;
        if (seconds === 0) return "";
        return Translation.tr("Joined %1").arg(Qt.formatDate(new Date(seconds * 1000), Qt.locale(), Locale.ShortFormat));
    }

    function primaryAction(): void {
        root.expanded = !root.expanded;
    }

    onExpandedChanged: if (!root.expanded) passwordBox.clear()
    onPageShownChanged: if (!root.pageShown) {
        root.expanded = false;
        root.changingPassword = false;
        passwordBox.clear();
    }

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
        enabled: !Network.connectionPending || root.connecting
        onClicked: root.primaryAction()

        contentItem: RowLayout {
            spacing: 12

            ConfigIconTile {
                icon: root.inRange ? Network.strengthSymbol(root.profile?.signal ?? 0) : "wifi_off"
                active: root.active
                iconSize: 22
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: root.name
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
                    text: [root.statusText, Network.securityLabel(root.profile?.securityType ?? ""), root.lastUsedText()].filter(part => part.length > 0).join(" · ")
                }
            }

            StatusIcon {
                visible: root.connecting
                text: ""
                iconSize: 18
                color: Appearance.colors.colSubtext
                busy: root.connecting && !Network.awaitingPassword
            }

            RippleButton {
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                colBackgroundHover: Appearance.colors.colLayer3Hover
                onClicked: root.expanded = !root.expanded
                contentItem: MaterialSymbol {
                    text: "expand_more"
                    rotation: root.expanded ? 180 : 0
                    Behavior on rotation {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                }
                StyledToolTip {
                    text: root.expanded ? Translation.tr("Show less") : Translation.tr("Password and more")
                }
            }
        }
    }

    // Its password stopped working, or it never had a working one
    RowLayout {
        visible: root.rejected && !root.asking
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
            onClicked: {
                Network.credentialErrorSsid = "";
                root.changingPassword = true;
            }
        }
    }

    NetworkRevealer {
        id: passwordDetails
        expanded: root.asking
        animationsEnabled: root.pageShown
        onExpandRequested: root.changingPassword = true
        Layout.leftMargin: 50
        Layout.rightMargin: 12
        bottomPadding: 12

        Loader {
            active: passwordDetails.visible
            Layout.fillWidth: true
            sourceComponent: PasswordForm {
                errorText: root.accessPoint?.errorText ?? ""
                busy: root.connecting
                placeholderText: Translation.tr("New password")
                onAccepted: password => {
                    Network.changeProfilePassword(root.profile, password);
                    root.changingPassword = false;
                }
                onCanceled: {
                    root.changingPassword = false;
                    Network.cancelPasswordPrompt();
                }
            }
        }
    }

    NetworkRevealer {
        objectName: "savedNetworkDetails"
        expanded: root.expanded
        animationsEnabled: root.pageShown
        onExpandRequested: root.expanded = true
        Layout.leftMargin: 50
        Layout.rightMargin: 12
        bottomPadding: 12
        spacing: 8

        SavedPasswordBox {
            id: passwordBox
            visible: root.hasPassword
            uuid: root.uuid
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            DialogButton {
                visible: root.inRange && !root.active
                enabled: !Network.connectionPending
                buttonText: Translation.tr("Connect")
                onClicked: Network.connectProfile(root.profile)
            }
            DialogButton {
                visible: root.active
                buttonText: Translation.tr("Disconnect")
                onClicked: Network.deactivateProfile(root.uuid)
            }
            DialogButton {
                visible: root.hasPassword
                buttonText: Translation.tr("Change password")
                onClicked: root.changingPassword = !root.changingPassword
            }
            DialogButton {
                buttonText: Translation.tr("Edit")
                onClicked: Network.editProfile(root.uuid)
            }
            Item {
                Layout.fillWidth: true
            }
            ForgetButton {
                label: Translation.tr("Forget this network")
                onConfirmed: Network.forgetWifiNetwork(root.uuid)
            }
        }
    }
}
