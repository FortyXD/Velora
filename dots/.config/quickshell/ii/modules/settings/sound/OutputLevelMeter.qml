import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root
    required property PwNode node
    required property bool active
    required property bool sampling
    readonly property int bucketCount: 54
    property var history: []
    property real peak: 0
    readonly property real level: active && sampling && monitor.peak > 0
        ? Math.max(0, Math.min(1, 1 + 20 * Math.log10(monitor.peak) / 60)) : 0
    Layout.fillWidth: true
    Layout.margins: 14
    spacing: 6

    PwNodePeakMonitor {
        id: monitor
        node: root.node
        enabled: root.active && root.sampling && !!root.node
    }
    onLevelChanged: peak = Math.max(peak, level)
    function clear() { peak = 0; history = []; }
    onNodeChanged: clear()
    onActiveChanged: if (!active) clear()
    Timer {
        interval: 100
        repeat: true
        running: root.active && (root.peak > 0 || root.history.some(value => value > 0))
        onTriggered: {
            root.history = root.history.slice(1 - root.bucketCount).concat(root.peak);
            root.peak = root.level;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Rectangle {
            implicitWidth: 7; implicitHeight: 7; radius: 4
            color: root.level > 0 ? plot.ink : Appearance.colors.colOutlineVariant
        }
        StyledText {
            Layout.fillWidth: true
            text: root.level > 0 ? Translation.tr("Audio playing") : Translation.tr("Silence")
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.small
        }
        StyledText {
            text: root.level > 0 ? Math.round(60 * (root.level - 1)) + " dBFS" : "−∞ dBFS"
            color: plot.ink
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.normal
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        ColumnLayout {
            Layout.fillHeight: true
            spacing: 0
            Repeater {
                model: ["0", "−30", "−60"]
                StyledText {
                    required property string modelData
                    required property int index
                    Layout.fillHeight: true
                    verticalAlignment: index === 0 ? Text.AlignTop : index === 1 ? Text.AlignVCenter : Text.AlignBottom
                    text: modelData
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
        Canvas {
            id: plot
            Layout.fillWidth: true
            implicitHeight: 64
            readonly property color ink: Appearance.colors.colPrimary
            readonly property color grid: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.6)
            onInkChanged: requestPaint()
            onGridChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const bottom = height - 2;
                ctx.lineWidth = 1;
                ctx.strokeStyle = grid;
                for (const y of [1, height / 2, bottom]) {
                    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                }
                const samples = root.history;
                ctx.beginPath();
                const offset = samples.length - root.bucketCount;
                const step = width / (root.bucketCount - 1);
                let previousY = bottom - (samples[offset] ?? 0) * (height - 4);
                ctx.moveTo(0, previousY);
                for (let i = 1; i < root.bucketCount; ++i) {
                    const y = bottom - (samples[offset + i] ?? 0) * (height - 4);
                    ctx.quadraticCurveTo((i - 1) * step, previousY, (i - 0.5) * step, (y + previousY) / 2);
                    previousY = y;
                }
                ctx.lineTo(width, previousY);
                ctx.strokeStyle = ink; ctx.lineWidth = 2; ctx.lineJoin = "round"; ctx.stroke();
                ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath();
                const fill = ctx.createLinearGradient(0, 0, 0, height);
                fill.addColorStop(0, Qt.rgba(ink.r, ink.g, ink.b, 0.52));
                fill.addColorStop(1, Qt.rgba(ink.r, ink.g, ink.b, 0.06));
                ctx.fillStyle = fill; ctx.fill();
            }
        }
    }
    onHistoryChanged: plot.requestPaint()
    RowLayout {
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("−5 s")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            text: Translation.tr("Now")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
}
