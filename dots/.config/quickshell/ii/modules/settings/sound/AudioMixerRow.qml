import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One app in the mixer: its icon and name, its own volume, mute, and which device it plays on (or listens to).
 */
Rectangle {
    id: root
    required property PwNode node
    readonly property bool playback: root.node?.isSink ?? true // Quickshell counts a playing stream as a sink
    readonly property var devices: root.playback ? Audio.outputDevices : Audio.inputDevices
    readonly property bool muted: root.node?.audio?.muted ?? false
    // The device this stream is linked to right now
    readonly property PwNode device: {
        for (const group of linkTracker.linkGroups) {
            const other = group.source?.id === root.node?.id ? group.target : group.source;
            if (other && !other.isStream) return other;
        }
        return null;
    }

    function moveTo(device) {
        const serial = root.node?.properties?.["object.serial"];
        if (!device || serial === undefined) return;
        Quickshell.execDetached(["pactl", root.playback ? "move-sink-input" : "move-source-output", String(serial), device.name]);
    }

    PwObjectTracker {
        objects: [root.node]
    }
    PwNodeLinkTracker {
        id: linkTracker
        node: root.node
    }

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + 20
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2

    RowLayout {
        id: row
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: 12
        }
        spacing: 12

        Item { // App icon, greyed out while muted
            implicitWidth: 36
            implicitHeight: 36
            StyledImage {
                id: appIcon
                anchors.fill: parent
                visible: false
                source: {
                    let icon = AppSearch.guessIcon(root.node?.properties["application.icon-name"] ?? "");
                    if (AppSearch.iconExists(icon)) return Quickshell.iconPath(icon, "image-missing");
                    icon = AppSearch.guessIcon(root.node?.properties["application.process.binary"] ?? root.node?.name ?? "");
                    return Quickshell.iconPath(icon, "image-missing");
                }
            }
            Desaturate {
                anchors.fill: appIcon
                source: appIcon
                desaturation: root.muted ? 1 : 0
                opacity: root.muted ? 0.4 : 1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
                text: Audio.appNodeDisplayName(root.node)
            }
            StyledText {
                visible: text.length > 0
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: root.node?.properties?.["media.name"] ?? ""
            }
            StyledSlider {
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.S
                value: root.node?.audio?.volume ?? 0
                onMoved: if (root.node?.audio) root.node.audio.volume = value
            }
        }

        RippleButton {
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: Appearance.rounding.full
            toggled: root.muted
            colBackgroundToggled: Appearance.colors.colErrorContainer
            colBackgroundToggledHover: Appearance.colors.colErrorContainerHover
            onClicked: if (root.node?.audio) root.node.audio.muted = !root.node.audio.muted
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: root.muted ? (root.playback ? "volume_off" : "mic_off") : (root.playback ? "volume_up" : "mic")
                iconSize: 20
                color: root.muted ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
            }
            StyledToolTip {
                text: root.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
            }
        }

        StyledComboBox { // Where it plays
            visible: root.devices.length > 1
            Layout.preferredWidth: 190
            model: root.devices.map(device => Audio.friendlyDeviceName(device))
            currentIndex: root.devices.findIndex(device => device.id === root.device?.id)
            onActivated: index => root.moveTo(root.devices[index])
        }
    }
}
