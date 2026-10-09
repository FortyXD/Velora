import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/**
 * CPU, memory, swap, temperature, disk and network at a glance.
 * Extra readings are only polled while the widget exists, i.e. while it's enabled.
 */
DesktopWidgetCard {
    id: root
    configEntryName: "systemMonitor"

    readonly property var options: Config.options.background.widgets.systemMonitor
    readonly property int interval: Config.options.resources.updateInterval

    // Temperature
    property string temperaturePath: ""
    property real temperature: -1
    Process {
        id: findTemperatureProc
        running: root.options.showTemperature
        command: ["bash", "-c", "for want in k10temp coretemp zenpower cpu_thermal acpitz; do for d in /sys/class/hwmon/hwmon*; do [ \"$(cat $d/name 2>/dev/null)\" = \"$want\" ] && [ -r $d/temp1_input ] && echo $d/temp1_input && exit; done; done; [ -r /sys/class/thermal/thermal_zone0/temp ] && echo /sys/class/thermal/thermal_zone0/temp"]
        stdout: StdioCollector {
            onStreamFinished: root.temperaturePath = text.trim()
        }
    }
    FileView {
        id: temperatureFile
        path: root.temperaturePath
        onLoaded: {
            const value = parseInt(temperatureFile.text());
            root.temperature = isNaN(value) ? -1 : value / 1000;
        }
    }

    // Disk usage of /
    property real diskUsed: 0
    property real diskSize: 1
    Process {
        id: diskProc
        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const numbers = text.trim().split("\n").pop().trim().split(/\s+/).map(Number);
                if (numbers.length === 2 && numbers[1] > 0) {
                    root.diskUsed = numbers[0];
                    root.diskSize = numbers[1];
                }
            }
        }
    }
    Timer {
        running: root.options.showDisk
        triggeredOnStart: true
        interval: 30000
        repeat: true
        onTriggered: diskProc.running = true
    }

    // Network speed, summed over all interfaces except loopback
    property real lastRx: -1
    property real lastTx: -1
    property real lastNetTime: 0
    property real rxSpeed: 0
    property real txSpeed: 0
    FileView {
        id: netFile
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0;
            for (const line of netFile.text().split("\n").slice(2)) {
                const parts = line.trim().split(/[:\s]+/);
                if (parts.length < 10 || parts[0] === "lo") continue;
                rx += Number(parts[1]);
                tx += Number(parts[9]);
            }
            const now = Date.now();
            if (root.lastRx >= 0 && now > root.lastNetTime) {
                const seconds = (now - root.lastNetTime) / 1000;
                root.rxSpeed = Math.max(0, (rx - root.lastRx) / seconds);
                root.txSpeed = Math.max(0, (tx - root.lastTx) / seconds);
            }
            root.lastRx = rx;
            root.lastTx = tx;
            root.lastNetTime = now;
        }
    }

    Timer {
        running: root.options.showNetwork || (root.options.showTemperature && root.temperaturePath.length > 0)
        triggeredOnStart: true
        interval: Math.max(1000, root.interval)
        repeat: true
        onTriggered: {
            if (root.options.showNetwork) netFile.reload();
            if (root.options.showTemperature && root.temperaturePath.length > 0) temperatureFile.reload();
        }
    }

    function formatBytes(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let value = bytes;
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return `${value >= 100 || unit === 0 ? Math.round(value) : value.toFixed(1)} ${units[unit]}`;
    }

    // One reading: icon, name, value and a bar or graph
    component Meter: ColumnLayout {
        id: meter
        property string icon
        property string label
        property string valueText
        property real fraction: 0
        property list<real> history: []
        property bool warning: fraction > 0.9
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: meter.icon
                iconSize: 18
                fill: 1
                color: meter.warning ? Appearance.colors.colError : root.colOnCardVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: meter.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.colOnCard
            }
            StyledText {
                text: meter.valueText
                font.family: Appearance.font.family.numbers
                font.variableAxes: Appearance.font.variableAxes.numbers
                font.pixelSize: Appearance.font.pixelSize.small
                color: meter.warning ? Appearance.colors.colError : root.colOnCard
            }
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: (root.options.showGraphs && meter.history.length > 1) ? 34 : 6

            Rectangle { // Bar
                visible: !(root.options.showGraphs && meter.history.length > 1)
                anchors.fill: parent
                radius: height / 2
                color: root.colLayer
                Rectangle {
                    width: Math.max(height, parent.width * Math.min(1, Math.max(0, meter.fraction)))
                    height: parent.height
                    radius: height / 2
                    color: meter.warning ? Appearance.colors.colError : root.colAccent
                    Behavior on width {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }
            Rectangle { // Graph
                visible: root.options.showGraphs && meter.history.length > 1
                anchors.fill: parent
                radius: Appearance.rounding.verysmall
                color: root.colLayer
                clip: true
                Graph {
                    anchors.fill: parent
                    values: meter.history
                    points: Config.options.resources.historyLength
                    alignment: Graph.Alignment.Right
                    color: meter.warning ? Appearance.colors.colError : root.colAccent
                    fillOpacity: 0.3
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        implicitWidth: 280
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: "monitor_heart"
                iconSize: 22
                fill: 1
                color: root.colAccent
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("System")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: root.colOnCard
            }
            StyledText {
                visible: root.options.showTemperature && root.temperature >= 0
                text: `${Math.round(root.temperature)}°C`
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.temperature >= 85 ? Appearance.colors.colError : root.colOnCardVariant
            }
        }

        Meter {
            visible: root.options.showCpu
            icon: "memory"
            label: Translation.tr("CPU")
            fraction: ResourceUsage.cpuUsage
            valueText: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
            history: ResourceUsage.cpuUsageHistory
        }
        Meter {
            visible: root.options.showMemory
            icon: "memory_alt"
            label: Translation.tr("Memory")
            fraction: ResourceUsage.memoryUsedPercentage
            valueText: `${root.formatBytes(ResourceUsage.memoryUsed * 1024)} / ${root.formatBytes(ResourceUsage.memoryTotal * 1024)}`
            history: ResourceUsage.memoryUsageHistory
        }
        Meter {
            visible: root.options.showSwap && ResourceUsage.swapTotal > 1
            icon: "swap_horiz"
            label: Translation.tr("Swap")
            fraction: ResourceUsage.swapUsedPercentage
            valueText: `${Math.round(ResourceUsage.swapUsedPercentage * 100)}%`
        }
        Meter {
            visible: root.options.showTemperature && root.temperature >= 0
            icon: "thermostat"
            label: Translation.tr("CPU temperature")
            fraction: root.temperature / 100
            warning: root.temperature >= 85
            valueText: `${Math.round(root.temperature)}°C`
        }
        Meter {
            visible: root.options.showDisk
            icon: "hard_drive"
            label: Translation.tr("Disk")
            fraction: root.diskUsed / root.diskSize
            valueText: `${root.formatBytes(root.diskUsed)} / ${root.formatBytes(root.diskSize)}`
        }
        RowLayout { // Network
            visible: root.options.showNetwork
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: "network_check"
                iconSize: 18
                fill: 1
                color: root.colOnCardVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Network")
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.colOnCard
            }
            MaterialSymbol {
                text: "arrow_downward"
                iconSize: 16
                color: root.colAccent
            }
            StyledText {
                text: `${root.formatBytes(root.rxSpeed)}/s`
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.colOnCard
            }
            MaterialSymbol {
                text: "arrow_upward"
                iconSize: 16
                color: root.colAccent
            }
            StyledText {
                text: `${root.formatBytes(root.txSpeed)}/s`
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.colOnCard
            }
        }
    }
}
