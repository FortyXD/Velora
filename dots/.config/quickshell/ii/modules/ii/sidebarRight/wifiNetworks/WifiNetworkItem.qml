import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.services.network
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    required property WifiAccessPoint wifiNetwork
    readonly property bool connecting: Network.connectionPending && Network.wifiConnectSsid === (wifiNetwork?.ssid ?? "")
    enabled: wifiNetwork !== null && Network.wifiEnabled && !Network.connectionPending
    active: (wifiNetwork?.active ?? false) || (wifiNetwork?.askingPassword ?? false) || connecting

    onClicked: {
        if (wifiNetwork && !wifiNetwork.active) Network.connectToWifiNetwork(wifiNetwork);
    }

    contentItem: RowLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 10

        MaterialSymbol {
            iconSize: Appearance.font.pixelSize.larger
            property int strength: root.wifiNetwork?.strength ?? 0
            text: strength > 80 ? "signal_wifi_4_bar" : strength > 60 ? "network_wifi_3_bar" : strength > 40 ? "network_wifi_2_bar" : strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
            color: Appearance.colors.colOnSurfaceVariant
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
                text: root.wifiNetwork?.ssid ?? ""
                textFormat: Text.PlainText
            }
            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
                text: root.connecting ? Translation.tr("Connecting…") : Network.credentialErrorSsid === (root.wifiNetwork?.ssid ?? "") ? Translation.tr("Saved password rejected") : (root.wifiNetwork?.active ?? false) ? Translation.tr("Connected") : (root.wifiNetwork?.savedUuid ?? "") ? Translation.tr("Saved network") : (root.wifiNetwork?.isSecure ?? false) ? Translation.tr("Password required") : Translation.tr("Available network")
            }
        }
        MaterialSymbol {
            visible: root.connecting
            text: "sync"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 1000
                loops: Animation.Infinite
                running: root.connecting
            }
        }
        MaterialSymbol {
            visible: !root.connecting && ((root.wifiNetwork?.isSecure ?? false) || (root.wifiNetwork?.active ?? false))
            text: (root.wifiNetwork?.active ?? false) ? "check" : "lock"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
