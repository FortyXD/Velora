import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "storage"

/**
 * Storage, opened from General.
 */
ContentPage {
    id: root

    property var disks: [] // { source, target, size, used, avail } in bytes
    property var mountPoints: []
    property real trashSize: -1 // Bytes, -1 until measured
    property string analyzer: "" // A disk usage app, if one is installed
    readonly property bool canNavigateBack: explorer.item?.canGoUp ?? false
    function navigateBack() { explorer.item?.goUp(); }

    // Decimal units, the ones disks are sold in
    function formatBytes(bytes) {
        const locale = Qt.locale(Translation.languageCode);
        if (bytes >= 1e12) return Translation.tr("%1 TB").arg((bytes / 1e12).toLocaleString(locale, "f", 2));
        if (bytes >= 1e9) return Translation.tr("%1 GB").arg((bytes / 1e9).toLocaleString(locale, "f", 1));
        if (bytes >= 1e6) return Translation.tr("%1 MB").arg((bytes / 1e6).toLocaleString(locale, "f", 1));
        if (bytes >= 1e3) return Translation.tr("%1 KB").arg(Math.round(bytes / 1e3));
        return Translation.tr("%1 B").arg(bytes);
    }

    function refresh() {
        diskUsage.running = true;
        trashUsage.running = true;
    }
    // Measured again each time the page is opened
    onPageShownChanged: {
        if (root.pageShown) root.refresh();
        else {
            diskUsage.running = false;
            trashUsage.running = false;
        }
    }
    Component.onCompleted: if (root.pageShown) root.refresh()

    Process {
        id: diskUsage
        command: ["df", "-B1", "--output=source,size,used,avail,target",
            "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "overlay", "-x", "squashfs", "-x", "ramfs"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = new Set();
                const disks = [];
                const mounts = [];
                for (const line of text.split("\n").slice(1)) {
                    const fields = line.match(/^(.+?)\s+(\d+)\s+(\d+)\s+(-?\d+)\s+(\/.*)$/);
                    if (!fields) continue;
                    const [, source, sizeText, usedText, availText, target] = fields;
                    const [size, used, avail] = [sizeText, usedText, availText].map(Number);
                    if (size <= 0 || /^\/(boot|efi)(\/|$)/.test(target)) continue;
                    mounts.push(target);
                    // Subvolumes can be explored separately but share the same free space.
                    if (seen.has(source)) continue;
                    seen.add(source);
                    disks.push({ source, target, size, used, avail });
                }
                root.disks = disks;
                root.mountPoints = mounts;
            }
        }
    }

    Process {
        id: trashUsage
        command: ["du", "-sb", "--", (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/Trash/files"]
        stdout: StdioCollector {
            onStreamFinished: root.trashSize = parseInt(text, 10) || 0
        }
    }

    Process {
        id: emptyTrash
        command: ["gio", "trash", "--empty"]
        onExited: {
            reuseScan.stop();
            if (root.pageShown) {
                root.refresh();
                if (explorer.item) explorer.item.startScan(explorer.item.scanPath);
            }
        }
    }

    // Keep one completed tree briefly for back/forward navigation. An unfinished
    // scan is still cancelled as soon as the user leaves the page.
    Timer {
        id: reuseScan
        objectName: "storageResultLifetime"
        interval: 60000
    }

    Process {
        running: root.pageShown
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
        icon: "donut_large"
        title: Translation.tr("Explore folder sizes")
        Loader {
            id: explorer
            objectName: "storageExplorerLoader"
            Layout.fillWidth: true
            Layout.margins: 12
            active: root.pageShown || reuseScan.running
            sourceComponent: StorageExplorer {
                mountPoints: root.mountPoints
                formatBytes: root.formatBytes
                onScanningChanged: {
                    if (!scanning && !failed) reuseScan.restart();
                    else reuseScan.stop();
                }
                onFailedChanged: if (failed) reuseScan.stop()
            }
        }
    }

    ContentSection {
        icon: "hard_drive"
        title: ""
        visible: root.disks.length > 0
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
