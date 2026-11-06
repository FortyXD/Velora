pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "ChartMath.js" as ChartMath

ContentSection {
    id: root
    property bool pageActive: true
    title: Translation.tr("Power analytics")
    icon: "monitoring"
    description: Translation.tr("Battery measurements, not charger input or total laptop power. Positive watts = discharge; negative watts = charging. Gaps mean no measurements, including sleep.")

    StyledText {
        Layout.fillWidth: true
        Layout.margins: 12
        visible: !PowerAnalytics.enabled && PowerAnalytics.error.length > 0
        text: PowerAnalytics.error
        color: Appearance.colors.colError
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
    Loader {
        Layout.fillWidth: true
        active: PowerAnalytics.enabled
        visible: active
        sourceComponent: ColumnLayout {
            id: panel
            property int windowSeconds: 1200
            property string metric: "power"
            property var history: ({ points: [], stats: {}, sample_count: 0, window_start: Date.now() / 1000 - 1200, window_end: Date.now() / 1000 })
            property bool loading: true
            property string readError: ""
            property bool readerBusy: false
            readonly property bool wanted: root.pageActive && panel.visible && PowerAnalytics.enabled
            readonly property var current: PowerAnalytics.fresh ? PowerAnalytics.latest : null
            spacing: 16
            Layout.margins: 14

            function number(value, digits, unit) {
                return ChartMath.valid(value) ? `${value.toFixed(digits)}${unit.length ? " " + unit : ""}` : "—";
            }
            function refreshReader() {
                restartReader.stop();
                if (panel.readerBusy) {
                    reader.running = false;
                    return; // Reconfigure only after this launch has exited and stdout drained.
                }
                if (panel.wanted) restartReader.restart();
            }
            onWantedChanged: refreshReader()
            onWindowSecondsChanged: { panel.loading = true; refreshReader(); }
            Component.onCompleted: refreshReader()
            Timer {
                id: restartReader
                interval: 150
                onTriggered: {
                    if (!panel.wanted || panel.readerBusy) return;
                    reader.activeWindow = panel.windowSeconds;
                    panel.readerBusy = true;
                    reader.running = true;
                }
            }
            Process {
                id: reader
                property int activeWindow: 1200
                command: ["python3", PowerAnalytics.scriptPath, "watch", "--state-dir", PowerAnalytics.stateDirectory,
                    "--window-seconds", String(activeWindow), "--points", "300"]
                stdout: SplitParser {
                    onRead: data => {
                        if (!panel.wanted || reader.activeWindow !== panel.windowSeconds) return;
                        try {
                            const result = JSON.parse(data);
                            if (!Array.isArray(result.points) || Math.abs(result.window_end - result.window_start - panel.windowSeconds) > 1) return;
                            panel.history = result;
                            panel.loading = false;
                            panel.readError = result.error ?? "";
                        } catch (e) {
                            panel.readError = Translation.tr("Could not read power history.");
                        }
                    }
                }
                stderr: SplitParser { onRead: data => panel.readError = data.slice(0, 300) }
                onExited: (exitCode, exitStatus) => {
                    panel.readerBusy = false;
                    if (panel.wanted && !restartReader.running) {
                        restartReader.interval = exitCode === 0 ? 150 : 2000;
                        restartReader.restart();
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: panel.current && panel.current.battery_power_w < 0 ? Translation.tr("Charging battery")
                            : panel.current && panel.current.battery_power_w > 0 ? Translation.tr("Battery discharge") : Translation.tr("Battery power")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        text: panel.number(panel.current ? Math.abs(panel.current.battery_power_w ?? NaN) : null, 2, "W")
                        color: Appearance.colors.colPrimary
                        font.pixelSize: 30
                        font.variableAxes: ({ "wght": 550 })
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Charge")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        text: panel.number(panel.current?.percentage, 1, "%")
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: 24
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Battery voltage")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        text: panel.number(panel.current?.voltage_v, 2, "V")
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: 24
                    }
                }
            }
            AnalyticsSegments {
                objectName: "powerHistoryRanges"
                Layout.fillWidth: true
                currentValue: panel.windowSeconds
                options: [{ label: Translation.tr("20 minutes"), value: 1200 },
                    { label: Translation.tr("1 hour"), value: 3600 }, { label: Translation.tr("8 hours"), value: 28800 }]
                onSelected: value => panel.windowSeconds = value
            }
            AnalyticsSegments {
                Layout.fillWidth: true
                currentValue: panel.metric
                options: [{ label: Translation.tr("Net power"), value: "power" },
                    { label: Translation.tr("Charge"), value: "charge" }, { label: Translation.tr("Voltage"), value: "voltage" }]
                onSelected: value => panel.metric = value
            }
            PowerHistoryChart {
                objectName: "powerHistoryChart"
                Layout.fillWidth: true
                history: panel.history
                metric: panel.metric
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                StyledText {
                    Layout.fillWidth: true
                    text: `${Translation.tr("Charged")}: ${panel.number(panel.history.stats?.energy_in_wh, 2, "Wh")}   ·   ${Translation.tr("Used")}: ${panel.number(panel.history.stats?.energy_out_wh, 2, "Wh")}`
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
                StyledText {
                    text: panel.loading ? Translation.tr("Updating…") : `${panel.history.sample_count ?? 0} · 2 s`
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: `${Translation.tr("Average net power")}: ${panel.number(panel.history.stats?.power_mean, 2, "W")}   ·   ${Translation.tr("Range")}: ${panel.number(panel.history.stats?.power_min, 1, "")} … ${panel.number(panel.history.stats?.power_max, 1, "W")}`
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            StyledText {
                Layout.fillWidth: true
                visible: (panel.history.sample_count ?? 0) < 2
                text: Translation.tr("History starts when analytics is enabled. Nothing is collected while it is off.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            StyledText {
                Layout.fillWidth: true
                visible: PowerAnalytics.error.length > 0 || panel.readError.length > 0
                text: PowerAnalytics.error || panel.readError
                color: Appearance.colors.colError
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    ConfigSwitch {
        buttonIcon: "monitoring"
        text: Translation.tr("Advanced power analytics")
        description: Translation.tr("Sample every 2 seconds and keep up to 8 hours on this device. Turning this off stops sampling and deletes all recorded measurements.")
        autoToggle: false
        checked: Config.options.battery.advancedAnalytics
        onClicked: Config.options.battery.advancedAnalytics = !checked
    }
}
