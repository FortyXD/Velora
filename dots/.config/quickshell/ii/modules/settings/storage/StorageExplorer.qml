pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    required property var mountPoints
    required property var formatBytes
    readonly property string homePath: Quickshell.env("HOME") || "/"
    property string scanPath: homePath
    property Process worker: null
    property int requestedId: 0
    property int requestedOffset: 0
    property var frame: null
    property double scanned: 0
    property bool failed: false
    readonly property bool scanning: frame === null && !failed
    readonly property bool current: !!frame && frame.id === requestedId && frame.offset === requestedOffset && !failed
    readonly property bool canGoUp: current && (frame.parent !== null || frame.offset > 0)
    readonly property var entries: frame?.children ?? []
    readonly property string countText: Translation.tr("Items scanned: %1").arg(scanned.toLocaleString(Qt.locale(Translation.languageCode), "f", 0))
    spacing: 8

    function startScan(path) {
        const old = worker;
        worker = null;
        if (old) {
            old.running = false;
            old.destroy();
        }
        scanPath = path;
        chart.transitionTo(null);
        frame = null;
        scanned = 0;
        failed = false;
        requestedId = 0;
        requestedOffset = 0;
        worker = scanner.createObject(root, { scanRoot: path });
        worker.running = true;
    }
    function showFolder(id, offset) {
        if (!worker || !current) return;
        requestedId = id;
        requestedOffset = offset;
        worker.write(JSON.stringify([id, offset]) + "\n");
    }
    function goUp() {
        if (canGoUp)
            showFolder(frame.offset > 0 ? frame.id : frame.parent, frame.previousOffset);
    }
    function labelFor(entry) {
        return entry.more ? Translation.tr("More items (%1)").arg(entry.more) : entry.name;
    }
    function activate(entry) {
        if (!current) return;
        if (entry.id !== undefined) showFolder(entry.id, entry.offset ?? 0);
        else Quickshell.execDetached(["busctl", "--user", "call", "org.freedesktop.FileManager1",
            "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1", "ShowItems", "ass", "1", entry.uri, ""]);
    }
    Component.onCompleted: startScan(homePath)
    Component.onDestruction: if (worker) worker.running = false

    Component {
        id: scanner
        Process {
            id: process
            required property string scanRoot
            command: [Quickshell.shellPath("scripts/helper"), "storage-usage", scanRoot]
            environment: ({ VELORA_STORAGE_PROGRESS_ONLY: "1" })
            stdinEnabled: true
            stdout: SplitParser {
                onRead: data => {
                    if (process !== root.worker) return;
                    try {
                        const next = JSON.parse(data);
                        if (next.id !== root.requestedId || next.offset !== root.requestedOffset) return;
                        root.scanned = next.scanned;
                        if (next.done) {
                            chart.transitionTo(next);
                            root.frame = next;
                        }
                    } catch (error) {
                        root.failed = true;
                    }
                }
            }
            onExited: if (process === root.worker) root.failed = true
        }
    }

    component MapButton: IconToolbarButton {
        id: button
        required property string label
        implicitHeight: 38
        Layout.fillHeight: false
        Accessible.name: label
        Keys.onReturnPressed: click()
        Keys.onEnterPressed: click()
        StyledToolTip { text: button.label }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 3
        ChoiceDropdown {
            id: scope
            objectName: "storageLocation"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.maximumWidth: 300
            currentValue: root.scanPath
            options: {
                const options = [{ value: root.homePath, displayName: Translation.tr("Home folder"), icon: "home" }];
                for (const path of new Set(["/", ...root.mountPoints])) {
                    if (path !== root.homePath) options.push({ value: path,
                        displayName: path === "/" ? Translation.tr("System disk (/)") : path, icon: "hard_drive" });
                }
                return options;
            }
            Accessible.name: displayText
            onSelected: path => { if (path !== root.scanPath) root.startScan(path); }
        }
        Item { Layout.fillWidth: true; Layout.preferredWidth: 0 }
        MapButton {
            text: "arrow_upward"
            label: Translation.tr("Up one level")
            enabled: root.canGoUp
            onClicked: root.goUp()
        }
        MapButton {
            text: "folder_open"
            label: Translation.tr("Open folder")
            enabled: root.current
            onClicked: Qt.openUrlExternally(root.frame.uri)
        }
        MapButton {
            objectName: "storageRescan"
            text: "refresh"
            label: Translation.tr("Scan again")
            onClicked: root.startScan(root.scanPath)
        }
    }
    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        text: {
            const path = root.frame?.path ?? root.scanPath;
            const sector = chart.hoveredSector;
            if (sector && !sector.entry.more) return (path === "/" ? "/" : path + "/") + sector.label;
            return root.frame?.offset > 0 ? path + " · " + Translation.tr("Other items") : path;
        }
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: body.visible ? body.implicitHeight : Math.max(264, scanMessage.implicitHeight + 32)
        clip: true
        Behavior on implicitHeight {
            NumberAnimation { duration: Appearance.scaledDuration(210); easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: scanMessage
            anchors.centerIn: parent
            width: parent.width
            spacing: 4
            z: 1
            opacity: root.scanning || root.failed ? 1 : 0
            visible: root.scanning || root.failed || opacity > 0
            scale: 0.94 + opacity * 0.06
            Behavior on opacity {
                NumberAnimation { duration: Appearance.scaledDuration(150); easing.type: Easing.OutCubic }
            }

            StatusIcon {
                objectName: "storageScanIndicator"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72
                Layout.bottomMargin: 6
                iconSize: 46
                text: root.failed ? "folder_off" : "folder_open"
                color: root.failed ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                busy: root.scanning && Appearance.animationSpeed > 0
                Accessible.role: root.scanning ? Accessible.ProgressBar : Accessible.StaticText
                Accessible.name: scanTitle.text
                Accessible.description: root.scanning ? root.countText : ""
            }
            StyledText {
                id: scanTitle
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.failed ? Translation.tr("Could not read this folder") : Translation.tr("Scanning folders…")
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: !root.failed
                text: root.countText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        GridLayout {
            id: body
            visible: !!root.frame && !root.failed
            width: parent.width
            columns: width >= 500 ? 2 : 1
            columnSpacing: 18
            rowSpacing: 6

            UsageRings {
                id: chart
                objectName: "storageRings"
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                Layout.preferredWidth: Math.min(264, body.width * (body.columns === 2 ? 0.46 : 1))
                Layout.preferredHeight: Layout.preferredWidth
                frame: root.frame
                formatBytes: root.formatBytes
                labelFor: root.labelFor
                canGoUp: root.canGoUp
                onActivated: entry => root.activate(entry)
                onUp: root.goUp()
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                Repeater {
                    model: root.entries.length
                    delegate: RippleButton {
                        id: row
                        required property int index
                        readonly property var entry: root.entries[index] ?? null
                        highlighted: hovered || visualFocus || chart.hoveredSector?.branch === index
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        readonly property real entrance: Math.max(0, Math.min(1, chart.progress * 1.25 - index * 0.035))
                        opacity: entrance * (enabled ? 1 : 0.4)
                        transform: Translate { x: (chart.returnSector ? -12 : 12) * (1 - row.entrance) }
                        implicitHeight: 33
                        horizontalPadding: 8
                        verticalPadding: 2
                        enabled: root.current && !!entry
                        colBackground: highlighted ? Appearance.colors.colLayer2Hover : "transparent"
                        Accessible.name: entry ? root.labelFor(entry) + ", " + root.formatBytes(entry.bytes) : ""
                        Accessible.description: entry?.uri ? Translation.tr("Show in folder") : Translation.tr("Explore folder sizes")
                        onHoveredChanged: {
                            if (hovered) chart.legendIndex = index;
                            else if (chart.legendIndex === index) chart.legendIndex = -1;
                        }
                        Component.onDestruction: if (chart && chart.legendIndex === index) chart.legendIndex = -1
                        Keys.onReturnPressed: click()
                        Keys.onEnterPressed: click()
                        onClicked: if (entry) root.activate(entry)
                        contentItem: RowLayout {
                            spacing: 8
                            Rectangle {
                                implicitWidth: 9
                                implicitHeight: 9
                                radius: width / 2
                                color: row.entry ? chart.colorFor(row.entry, row.index) : "transparent"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: row.entry ? root.labelFor(row.entry) : ""
                                textFormat: Text.PlainText
                                elide: Text.ElideMiddle
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: row.entry ? root.formatBytes(row.entry.bytes) : ""
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            MaterialSymbol {
                                text: row.entry?.uri ? "folder_open" : "chevron_right"
                                iconSize: 16
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
                StyledText {
                    visible: root.entries.length === 0
                    Layout.fillWidth: true
                    text: root.frame?.unreadable ? Translation.tr("Could not read this folder") : Translation.tr("This folder is empty")
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: body.visible
        text: root.frame?.skipped ? root.countText + " · " + Translation.tr("Skipped: %1").arg(root.frame.skipped) : root.countText
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
