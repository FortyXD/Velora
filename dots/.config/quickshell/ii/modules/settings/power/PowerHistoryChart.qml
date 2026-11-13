pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "ChartMath.js" as ChartMath

/** Real timestamps, honest gaps and bounded monotone interpolation. No invented history. */
Item {
    id: root
    property var history: ({ points: [], window_start: 0, window_end: 1 })
    property string metric: "power"
    property var frame: null
    property var previous: null
    property real blend: 1
    property var hoveredPoint: null
    readonly property real leftInset: 48
    readonly property real rightInset: 12
    readonly property real topInset: 16
    readonly property real bottomInset: 30
    implicitHeight: 252
    implicitWidth: 480
    clip: true

    function refresh() {
        const points = root.history.points ?? [];
        const bounds = ChartMath.domain(points, root.metric);
        root.previous = root.frame;
        root.frame = { points: points, metric: root.metric, key: ChartMath.keyFor(root.metric),
            low: bounds[0], high: bounds[1], start: root.history.window_start ?? 0,
            end: root.history.window_end ?? 1, unit: ChartMath.unitFor(root.metric) };
        root.hoveredPoint = null;
        if (root.previous !== null && root.previous.points.length > 0 && root.visible) {
            root.blend = 0;
            transition.restart();
        } else {
            transition.stop();
            root.blend = 1;
        }
        plot.requestPaint();
    }
    onHistoryChanged: refresh()
    onMetricChanged: refresh()
    onBlendChanged: plot.requestPaint()
    onWidthChanged: plot.requestPaint()
    onHeightChanged: plot.requestPaint()
    onVisibleChanged: {
        if (!visible) { transition.stop(); root.previous = null; root.blend = 1; }
        else plot.requestPaint();
    }
    Component.onCompleted: refresh()

    NumberAnimation {
        id: transition
        target: root
        property: "blend"
        to: 1
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        onFinished: root.previous = null
    }
    Canvas {
        id: plot
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (root.frame === null) return;
            function draw(frame, alpha) {
                if (!frame || alpha <= 0) return;
                const w = width - root.leftInset - root.rightInset;
                const h = height - root.topInset - root.bottomInset;
                if (w <= 0 || h <= 0) return;
                const span = Math.max(1, frame.end - frame.start);
                const range = Math.max(0.001, frame.high - frame.low);
                function xOf(t) { return root.leftInset + (t - frame.start) / span * w; }
                function yOf(v) { return root.topInset + (frame.high - v) / range * h; }
                ctx.save();
                ctx.globalAlpha = alpha;
                ctx.font = `${Appearance.font.pixelSize.smaller}px "${Appearance.font.family.main}"`;
                ctx.textBaseline = "middle";
                for (let i = 0; i < 3; ++i) {
                    const value = frame.high - range * i / 2;
                    const y = yOf(value);
                    ctx.globalAlpha = alpha * 0.13;
                    ctx.strokeStyle = Appearance.colors.colSubtext;
                    ctx.lineWidth = 1;
                    ctx.beginPath(); ctx.moveTo(root.leftInset, y); ctx.lineTo(width - root.rightInset, y); ctx.stroke();
                    ctx.globalAlpha = alpha;
                    ctx.fillStyle = Appearance.colors.colSubtext;
                    ctx.textAlign = "right";
                    const precision = frame.metric === "voltage" ? 1 : range / 2 < 1 ? Math.min(3, Math.ceil(-Math.log10(range / 2))) : 0;
                    ctx.fillText(value.toFixed(precision), root.leftInset - 10, y);
                }
                ctx.textAlign = "left";
                ctx.fillText(frame.unit, 2, 6);
                for (let i = 0; i < 3; ++i) {
                    ctx.textAlign = i === 0 ? "left" : i === 2 ? "right" : "center";
                    const stamp = frame.start + span * i / 2;
                    ctx.fillText(Qt.formatTime(new Date(stamp * 1000), "HH:mm"), root.leftInset + w * i / 2, height - 10);
                }
                if (frame.metric === "power" && frame.low < 0 && frame.high > 0) {
                    ctx.globalAlpha = alpha * 0.35;
                    ctx.beginPath(); ctx.moveTo(root.leftInset, yOf(0)); ctx.lineTo(width - root.rightInset, yOf(0)); ctx.stroke();
                    ctx.globalAlpha = alpha;
                }
                ctx.save();
                ctx.beginPath(); ctx.rect(root.leftInset, root.topInset - 2, w, h + 4); ctx.clip();
                const segments = ChartMath.segments(frame.points, frame.metric);
                for (const segment of segments) {
                    const p = segment.map(sample => ({ x: xOf(sample.timestamp), y: yOf(sample[frame.key]) }));
                    if (p.length === 1) {
                        ctx.fillStyle = Appearance.colors.colPrimary;
                        ctx.beginPath(); ctx.arc(p[0].x, p[0].y, 2.5, 0, Math.PI * 2); ctx.fill();
                        continue;
                    }
                    const slopes = ChartMath.tangents(p);
                    ctx.beginPath(); ctx.moveTo(p[0].x, p[0].y);
                    for (let i = 1; i < p.length; ++i) {
                        const dx = (p[i].x - p[i - 1].x) / 3;
                        ctx.bezierCurveTo(p[i - 1].x + dx, p[i - 1].y + slopes[i - 1] * dx,
                            p[i].x - dx, p[i].y - slopes[i] * dx, p[i].x, p[i].y);
                    }
                    ctx.strokeStyle = Appearance.colors.colPrimary;
                    ctx.lineWidth = 2;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";
                    ctx.stroke();
                    const baseline = frame.metric === "power" ? yOf(0) : root.topInset + h;
                    ctx.lineTo(p[p.length - 1].x, baseline); ctx.lineTo(p[0].x, baseline); ctx.closePath();
                    const gradient = ctx.createLinearGradient(0, root.topInset, 0, root.topInset + h);
                    const col = Appearance.colors.colPrimary;
                    gradient.addColorStop(0, Qt.rgba(col.r, col.g, col.b, 0.16));
                    gradient.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0.02));
                    ctx.fillStyle = gradient; ctx.fill();
                }
                ctx.restore();
                ctx.restore();
            }
            if (root.blend < 1) draw(root.previous, 1 - root.blend);
            draw(root.frame, root.blend);
            if (root.hoveredPoint !== null) {
                const frame = root.frame;
                const x = root.leftInset + (root.hoveredPoint.timestamp - frame.start) / Math.max(1, frame.end - frame.start) * (width - root.leftInset - root.rightInset);
                ctx.strokeStyle = Appearance.colors.colSubtext;
                ctx.globalAlpha = 0.4;
                ctx.beginPath(); ctx.moveTo(x, root.topInset); ctx.lineTo(x, height - root.bottomInset); ctx.stroke();
                ctx.globalAlpha = 1;
            }
        }
    }
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: {
            if (root.frame === null || mouseX < root.leftInset || mouseX > width - root.rightInset) {
                root.hoveredPoint = null;
            } else {
                const fraction = (mouseX - root.leftInset) / Math.max(1, width - root.leftInset - root.rightInset);
                const stamp = root.frame.start + fraction * (root.frame.end - root.frame.start);
                // Nearest lookup is restricted to continuous recorded segments.
                root.hoveredPoint = ChartMath.nearest(root.frame.points, stamp, root.metric);
            }
            plot.requestPaint();
        }
        onExited: { root.hoveredPoint = null; plot.requestPaint(); }
    }
    Rectangle {
        visible: root.hoveredPoint !== null
        x: Math.max(root.leftInset, Math.min(root.width - width - 8, hover.mouseX - width / 2))
        y: 2
        implicitWidth: tooltip.implicitWidth + 20
        implicitHeight: 28
        radius: Appearance.rounding.small
        color: Appearance.colors.colSecondaryContainer
        StyledText {
            id: tooltip
            anchors.centerIn: parent
            text: root.hoveredPoint ? `${Qt.formatTime(new Date(root.hoveredPoint.timestamp * 1000), "HH:mm:ss")}  ·  ${root.hoveredPoint[ChartMath.keyFor(root.metric)].toFixed(2)} ${ChartMath.unitFor(root.metric)}` : ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
    StyledText {
        anchors.centerIn: parent
        visible: root.frame === null || ChartMath.segments(root.frame.points, root.metric).length === 0
        text: Translation.tr("Waiting for measurements…")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
    }
}
