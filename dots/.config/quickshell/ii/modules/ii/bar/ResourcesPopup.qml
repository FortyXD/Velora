import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

/**
 * Memory, swap and CPU as bars, then the apps using the most of them.
 * Apps can be closed from here; the list is only sampled while the popup is open.
 */
StyledPopup {
    id: root
    interactive: true

    function formatKB(kb) {
        if (kb >= 1024 * 1024) return (kb / (1024 * 1024)).toFixed(1) + " GB";
        return Math.round(kb / 1024) + " MB";
    }
    function formatCpu(fraction) {
        const percent = fraction * 100;
        return `${percent.toFixed(percent < 10 ? 1 : 0)}%`;
    }

    // Apps: processes grouped by command, so a browser's many processes show up as one entry
    property string sortKey: "memory" // or "cpu"
    property var apps: []
    property bool appsLoaded: false
    readonly property var shownApps: apps.slice()
        .sort((a, b) => sortKey === "cpu" ? b.cpu - a.cpu : b.memoryKb - a.memoryKb)
        .slice(0, 5)
    // Closing these would take the session down with them
    readonly property list<string> protectedCommands: ["qs", "quickshell", "Hyprland", "systemd", "(sd-pam)",
        "pipewire", "pipewire-pulse", "wireplumber", "dbus-daemon", "dbus-broker", "dbus-broker-lau", "Xwayland",
        "hypridle", "xdg-desktop-por", "xdg-document-po", "xdg-permission-"]
    property string confirmCommand: "" // App whose close button waits for a second click

    function appName(command) {
        return TaskbarApps.desktopEntryFor(command)?.name || (command.charAt(0).toUpperCase() + command.slice(1));
    }

    function parseApps(text) {
        let cpuCount = 1;
        const groups = {};
        for (const line of text.split("\n")) {
            if (line.startsWith("N ")) {
                cpuCount = parseInt(line.slice(2)) || 1;
                continue;
            }
            const parts = line.split("\t");
            if (parts.length < 4) continue;
            const command = parts[3];
            if (command === "top") continue; // The sampler itself
            const group = groups[command] ?? (groups[command] = { command: command, pids: [], memoryKb: 0, cpu: 0 });
            group.pids.push(parts[0]);
            group.memoryKb += Number(parts[2]) || 0;
            group.cpu += Number(parts[1]) || 0;
        }
        root.apps = Object.values(groups).map(group => Object.assign(group, { cpu: group.cpu / 100 / cpuCount }));
        root.appsLoaded = true;
    }

    function closeApp(app) {
        Quickshell.execDetached(["kill", "-TERM", ...app.pids]);
        root.confirmCommand = "";
        refreshSoonTimer.restart();
    }

    property Process appsProcess: Process {
        command: [FileUtils.trimFileProtocol(`${Directories.scriptPath}/system/top-apps.sh`)]
        stdout: StdioCollector {
            onStreamFinished: root.parseApps(this.text)
        }
    }
    property Timer appsTimer: Timer {
        interval: 3500
        repeat: true
        triggeredOnStart: true
        running: root.active
        onTriggered: if (!root.appsProcess.running) root.appsProcess.running = true
    }
    property Timer refreshSoonTimer: Timer {
        interval: 700
        onTriggered: if (!root.appsProcess.running) root.appsProcess.running = true
    }
    property Timer confirmTimer: Timer {
        interval: 3000
        onTriggered: root.confirmCommand = ""
    }
    onActiveChanged: if (!active) confirmCommand = ""

    component UsageCard: ColumnLayout {
        id: card
        required property string icon
        required property string title
        required property string valueText
        required property real fraction
        property bool warning: false
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            MaterialSymbol {
                text: card.icon
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: card.title
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                text: card.valueText
                font.pixelSize: Appearance.font.pixelSize.small
                color: card.warning ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
            }
        }
        Rectangle { // Track
            Layout.fillWidth: true
            implicitHeight: 6
            radius: height / 2
            color: Appearance.colors.colSecondaryContainer

            Rectangle {
                height: parent.height
                radius: height / 2
                width: parent.width * Math.max(0, Math.min(1, card.fraction))
                color: card.warning ? Appearance.colors.colError : Appearance.colors.colPrimary
                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }
    }

    component SortButton: RippleButton {
        id: sortButton
        required property string key
        required property string label
        implicitHeight: 24
        implicitWidth: sortLabel.implicitWidth + 16
        buttonRadius: Appearance.rounding.full
        toggled: root.sortKey === key
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive
        onClicked: root.sortKey = key
        contentItem: StyledText {
            id: sortLabel
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: sortButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
            text: sortButton.label
        }
    }

    Item {
        anchors.centerIn: parent
        implicitWidth: 300
        implicitHeight: contentColumn.implicitHeight

        ColumnLayout {
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            UsageCard {
                icon: "memory"
                title: Translation.tr("Memory")
                valueText: `${root.formatKB(ResourceUsage.memoryUsed)} / ${root.formatKB(ResourceUsage.memoryTotal)}`
                fraction: ResourceUsage.memoryUsedPercentage
                warning: ResourceUsage.memoryUsedPercentage * 100 >= Config.options.bar.resources.memoryWarningThreshold
            }
            UsageCard {
                visible: ResourceUsage.swapTotal > 0
                icon: "swap_horiz"
                title: "Swap"
                valueText: `${root.formatKB(ResourceUsage.swapUsed)} / ${root.formatKB(ResourceUsage.swapTotal)}`
                fraction: ResourceUsage.swapUsedPercentage
                warning: ResourceUsage.swapUsedPercentage * 100 >= Config.options.bar.resources.swapWarningThreshold
            }
            UsageCard {
                icon: "planner_review"
                title: "CPU"
                valueText: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                fraction: ResourceUsage.cpuUsage
                warning: ResourceUsage.cpuUsage * 100 >= Config.options.bar.resources.cpuWarningThreshold
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Apps")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                }
                SortButton {
                    key: "memory"
                    label: Translation.tr("Memory")
                }
                SortButton {
                    key: "cpu"
                    label: "CPU"
                }
            }

            StyledText {
                visible: !root.appsLoaded
                text: Translation.tr("Loading…")
                color: Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.appsLoaded
                spacing: 2

                Repeater {
                    model: root.shownApps

                    delegate: RowLayout {
                        id: appRow
                        required property var modelData
                        readonly property bool confirming: root.confirmCommand === modelData.command
                        readonly property bool closable: !root.protectedCommands.includes(modelData.command)
                        Layout.fillWidth: true
                        spacing: 8

                        IconImage {
                            implicitSize: 20
                            source: Quickshell.iconPath(AppSearch.guessIcon(appRow.modelData.command), "application-x-executable")
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: appRow.confirming ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
                            text: appRow.confirming ? Translation.tr("Close %1?").arg(root.appName(appRow.modelData.command))
                                : root.appName(appRow.modelData.command)
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            text: root.sortKey === "cpu" ? root.formatCpu(appRow.modelData.cpu) : root.formatKB(appRow.modelData.memoryKb)
                        }
                        RippleButton {
                            id: closeButton
                            implicitWidth: 24
                            implicitHeight: 24
                            buttonRadius: Appearance.rounding.full
                            enabled: appRow.closable
                            opacity: appRow.closable ? 1 : 0
                            colBackground: appRow.confirming ? Appearance.colors.colErrorContainer : "transparent"
                            colBackgroundHover: appRow.confirming ? Appearance.colors.colErrorContainerHover : Appearance.colors.colLayer1Hover
                            onClicked: {
                                if (appRow.confirming) {
                                    root.closeApp(appRow.modelData);
                                } else {
                                    root.confirmCommand = appRow.modelData.command;
                                    root.confirmTimer.restart();
                                }
                            }
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: appRow.confirming ? "check" : "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: appRow.confirming ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }
        }
    }
}
