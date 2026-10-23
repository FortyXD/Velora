import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A sound device as a card: what kind it is, its name, and whether it's the one in use. Clicking picks it.
 */
RippleButton {
    id: root
    required property PwNode node
    property bool selected: false

    // From the node name: properties are only filled in for tracked nodes
    readonly property string lowerName: (root.node?.name ?? "").toLowerCase()
    readonly property string bus: root.lowerName.startsWith("bluez") ? "bluetooth" : root.lowerName.includes(".usb-") ? "usb" : ""
    readonly property string kind: root.lowerName.includes("hdmi") || root.lowerName.includes("displayport") ? "hdmi"
        : root.bus === "bluetooth" ? "bluetooth"
        : root.bus === "usb" ? "usb"
        : root.lowerName.includes("pci") ? "builtin" : "other"
    readonly property string symbol: {
        if (root.node?.isSink) {
            switch (root.kind) {
            case "hdmi": return "tv";
            case "bluetooth": return "headphones";
            case "usb": return "speaker";
            default: return "speaker";
            }
        }
        switch (root.kind) {
        case "bluetooth": return "headset_mic";
        case "usb": return "mic_external_on";
        default: return "mic";
        }
    }
    readonly property string kindText: {
        switch (root.kind) {
        case "hdmi": return Translation.tr("Screen (HDMI)");
        case "bluetooth": return Translation.tr("Bluetooth");
        case "usb": return Translation.tr("USB");
        case "builtin": return root.node?.isSink ? Translation.tr("Built-in speakers") : Translation.tr("Built-in microphone");
        default: return Translation.tr("Sound device");
        }
    }

    readonly property bool settingsSearchable: true
    property string searchText: `${Audio.friendlyDeviceName(root.node)} ${root.kindText}`

    implicitWidth: 230
    implicitHeight: 64
    buttonRadius: Appearance.rounding.normal
    colBackground: root.selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
    colBackgroundHover: root.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
    colRipple: root.selected ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer2Active

    contentItem: RowLayout {
        spacing: 10
        Rectangle {
            implicitWidth: 40
            implicitHeight: 40
            radius: 20
            color: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.symbol
                iconSize: 22
                fill: root.selected ? 1 : 0
                color: root.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: Audio.friendlyDeviceName(root.node)
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: root.selected ? ({ "wght": 600 }) : ({})
                color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                text: root.selected ? Translation.tr("In use · %1").arg(root.kindText) : root.kindText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
}
