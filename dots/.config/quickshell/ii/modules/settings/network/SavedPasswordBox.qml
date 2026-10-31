import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A network's saved password: hidden until asked for, read from NetworkManager only then and dropped
 * again as soon as it isn't needed. Copying and the QR code happen in the daemon, without it coming here.
 */
ColumnLayout {
    id: root
    required property string uuid
    property string revealed: ""
    property string qrImage: ""
    property string errorText: ""
    property bool busy: false
    property bool copied: false

    function clear(): void {
        root.revealed = "";
        root.qrImage = "";
        root.errorText = "";
        root.copied = false;
    }

    function showError(error): void {
        root.errorText = error.code === "secrets_required" ? Translation.tr("No saved password was found for this network")
            : error.code === "permission_denied" ? Translation.tr("You aren't allowed to read this password")
            : Translation.tr(error.message);
    }

    function toggleReveal(): void {
        if (root.revealed.length > 0) {
            root.revealed = "";
            return;
        }
        root.errorText = "";
        root.busy = true;
        ConnectivityBackend.call("network.secrets", { uuid: root.uuid }, (result, error) => {
            root.busy = false;
            if (error) {
                root.showError(error);
                return;
            }
            const secret = result.secrets.find(entry => entry.section === "802-11-wireless-security" && (entry.key === "psk" || entry.key === "wep-key0"));
            if (secret) root.revealed = secret.value;
            else root.showError({ code: "secrets_required" });
        });
    }

    function copy(): void {
        root.errorText = "";
        ConnectivityBackend.call("network.copyPassword", { uuid: root.uuid }, (result, error) => {
            if (error) {
                root.showError(error);
                return;
            }
            root.copied = true;
            copiedTimer.restart();
        });
    }

    function toggleQr(): void {
        if (root.qrImage.length > 0) {
            root.qrImage = "";
            return;
        }
        root.errorText = "";
        root.busy = true;
        ConnectivityBackend.call("network.qrCode", { uuid: root.uuid }, (result, error) => {
            root.busy = false;
            if (error) root.showError(error);
            else root.qrImage = result.image;
        });
    }

    spacing: 8

    Timer {
        id: copiedTimer
        interval: 1500
        onTriggered: root.copied = false
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 42
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer3

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 4
            spacing: 2

            StyledText {
                id: passwordText
                Layout.fillWidth: true
                text: root.revealed.length > 0 ? root.revealed : "••••••••"
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                font.family: root.revealed.length > 0 ? Appearance.font.family.monospace : Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }

            PasswordAction {
                id: revealAction
                enabled: !root.busy
                symbol: root.revealed.length > 0 ? "visibility_off" : "visibility"
                tip: root.revealed.length > 0 ? Translation.tr("Hide password") : Translation.tr("Show password")
                onClicked: root.toggleReveal()
            }
            PasswordAction {
                enabled: !root.busy
                symbol: root.copied ? "check" : "content_copy"
                tip: Translation.tr("Copy password")
                onClicked: root.copy()
            }
            PasswordAction {
                enabled: !root.busy
                symbol: "qr_code_2"
                tip: Translation.tr("Show a QR code to share this network")
                onClicked: root.toggleQr()
            }
        }
    }

    Image {
        visible: root.qrImage.length > 0
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 220
        Layout.preferredHeight: 220
        source: root.qrImage
        fillMode: Image.PreserveAspectFit
        smooth: false
        cache: false // A picture of a password doesn't stay around
    }

    StyledText {
        visible: root.errorText.length > 0
        Layout.fillWidth: true
        text: root.errorText
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colError
    }

    component PasswordAction: RippleButton {
        id: action
        property string symbol
        property string tip
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer3Hover
        contentItem: MaterialSymbol {
            text: action.symbol
            iconSize: 18
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
        }
        StyledToolTip {
            text: action.tip
        }
    }
}
