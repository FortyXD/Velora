import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Storage, opened from General: how full each disk is, and a few ways to make room.
 */
ContentPage {
    id: root

    property var disks: [] // { source, target, size, used, avail } in bytes
    property real trashSize: -1 // Bytes, -1 until measured
    property string analyzer: "" // A disk usage app, if one is installed

    // Decimal units, the ones disks are sold in
    function formatBytes(bytes) {
        if (bytes >= 1e12) return Translation.tr("%1 TB").arg((bytes / 1e12).toFixed(2));
        if (bytes >= 1e9) return Translation.tr("%1 GB").arg((bytes / 1e9).toFixed(1));
        if (bytes >= 1e6) return Translation.tr("%1 MB").arg(Math.round(bytes / 1e6));
        return Translation.tr("%1 KB").arg(Math.round(bytes / 1e3));
    }

    function refresh() {
        diskUsage.running = true;
        trashUsage.running = true;
    }
    // Measured again each time the page is opened
    onPageShownChanged: if (root.pageShown) root.refresh()
    Component.onCompleted: root.refresh()

    Process {
        id: diskUsage
        command: ["df", "-B1", "--output=source,target,size,used,avail",
            "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "overlay", "-x", "squashfs", "-x", "ramfs"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = new Set();
                const disks = [];
                for (const line of text.trim().split("\n").slice(1)) {
                    const fields = line.trim().split(/\s+/);
                    if (fields.length < 5) continue;
                    const [size, used, avail] = fields.slice(-3).map(Number);
                    const source = fields[0];
                    const target = fields.slice(1, -3).join(" "); // Mount points can have spaces
                    // Boot partitions aren't room for files, and a disk mounted several times (btrfs subvolumes) counts once
                    if (size <= 0 || /^\/(boot|efi)(\/|$)/.test(target) || seen.has(source)) continue;
                    seen.add(source);
                    disks.push({ source, target, size, used, avail });
                }
                root.disks = disks;
            }
        }
    }

    Process {
        id: trashUsage
        command: ["sh", "-c", 'du -sb "${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files" 2>/dev/null | cut -f1']
        stdout: StdioCollector {
            onStreamFinished: root.trashSize = Number(text.trim()) || 0
        }
    }

    Process {
        id: emptyTrash
        command: ["gio", "trash", "--empty"]
        onExited: (exitCode, exitStatus) => root.refresh()
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v filelight || command -v baobab || command -v qdirstat"]
        stdout: StdioCollector {
            onStreamFinished: root.analyzer = text.trim().split("\n")[0] ?? ""
        }
    }

    // One disk: what it is, a bar of how full it is, and the numbers
    component DiskRow: ColumnLayout {
        id: diskRow
        required property var modelData
        readonly property real fraction: diskRow.modelData.size > 0 ? diskRow.modelData.used / diskRow.modelData.size : 0
        readonly property bool removable: /^\/(run\/media|media|mnt)\//.test(diskRow.modelData.target)
        Layout.fillWidth: true
        Layout.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ConfigIconTile {
                icon: diskRow.removable ? "usb" : "hard_drive"
                tileColor: ColorUtils.mix("#8E8E93", Appearance.colors.colPrimary, 0.82)
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: diskRow.modelData.target === "/" ? SystemInfo.distroName
                        : diskRow.modelData.target.split("/").pop() || diskRow.modelData.target
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 of %2 used").arg(root.formatBytes(diskRow.modelData.used)).arg(root.formatBytes(diskRow.modelData.size))
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            StyledText {
                text: Translation.tr("%1 available").arg(root.formatBytes(diskRow.modelData.avail))
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        Rectangle { // How full
            Layout.fillWidth: true
            implicitHeight: 10
            radius: height / 2
            color: Appearance.colors.colSecondaryContainer
            Rectangle {
                width: Math.max(parent.height, parent.width * diskRow.fraction)
                height: parent.height
                radius: height / 2
                color: diskRow.fraction > 0.9 ? Appearance.colors.colError : Appearance.colors.colPrimary
                Behavior on width {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
        }
    }

    ContentSection {
        icon: "hard_drive"
        title: ""
        searchText: `${Translation.tr("Storage")} ${Translation.tr("Disk")} ${Translation.tr("Available")}`

        Repeater {
            model: root.disks
            delegate: DiskRow {}
        }
    }

    ContentSection {
        icon: "cleaning_services"
        title: Translation.tr("Make room")

        ConfigNavRow {
            id: trashRow
            property bool armed: false
            buttonIcon: "delete"
            title: armed ? Translation.tr("Click again to empty the trash") : Translation.tr("Empty Trash")
            description: Translation.tr("Files in the trash still take up space until it's emptied")
            valueText: root.trashSize < 0 ? "" : root.trashSize === 0 ? Translation.tr("Empty") : root.formatBytes(root.trashSize)
            trailingIcon: ""
            enabled: root.trashSize > 0 && !emptyTrash.running
            onClicked: {
                if (!armed) {
                    armed = true;
                    trashDisarmTimer.restart();
                    return;
                }
                armed = false;
                emptyTrash.running = true;
            }
            Timer {
                id: trashDisarmTimer
                interval: 4000
                onTriggered: trashRow.armed = false
            }
        }

        ConfigNavRow {
            visible: root.analyzer.length > 0
            buttonIcon: "donut_large"
            title: Translation.tr("See what takes up space")
            description: Translation.tr("Opens %1, which shows the folders by size").arg(root.analyzer.split("/").pop())
            trailingIcon: "open_in_new"
            onClicked: Quickshell.execDetached([root.analyzer])
        }
    }
}
