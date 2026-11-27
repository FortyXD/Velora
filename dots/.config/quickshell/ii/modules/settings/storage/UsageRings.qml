pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: chart
    required property var frame
    required property var formatBytes
    required property var labelFor
    property bool canGoUp: false
    property int legendIndex: -1
    signal activated(var entry)
    signal up()

    implicitWidth: 264
    implicitHeight: 264
    readonly property real radius: Math.max(0, Math.min(width, height) / 2 - 4)
    readonly property real hole: radius * 0.44
    readonly property real band: (radius - hole) / 3
    readonly property color accent: Appearance.colors.colPrimary
    readonly property color track: Appearance.colors.colLayer3
    readonly property bool dark: Appearance.m3colors.darkmode
    readonly property real turn: 2 * Math.PI
    readonly property real pixel: 1 / Math.max(1, Screen.devicePixelRatio)
    property real progress: 1
    property var origin: null
    readonly property var returnSector: origin && !origin.focus && origin.id >= 0
        ? sectorFor(sectors, origin.id, origin.offset) : null

    function sectorFor(items, id, offset) {
        return items.find(s => s.entry.id === id && (s.entry.offset ?? 0) === offset) ?? null;
    }

    // Capture the geometry on screen before the new folder replaces the current one.
    function transitionTo(next) {
        const previous = next && frame ? drawnSectors : [];
        reveal.stop();
        if (!next || Appearance.animationSpeed <= 0) {
            origin = null;
            progress = 1;
            return;
        }
        origin = { id: frame?.id ?? -1, offset: frame?.offset ?? 0, sectors: previous,
                   focus: sectorFor(previous, next.id, next.offset) };
        progress = 0;
        reveal.restart();
    }

    NumberAnimation {
        id: reveal
        target: chart
        property: "progress"
        from: 0; to: 1
        duration: Appearance.scaledDuration(chart.origin?.id >= 0 ? 300 : 440)
        easing.type: Easing.OutCubic
        onFinished: chart.origin = null
    }

    function colorFor(entry, index) {
        if (entry.more) return Appearance.colors.colOutline;
        const hue = accent.hslSaturation > 0.12 ? accent.hslHue : 0.57;
        return Qt.hsla((hue + index * 0.618034) % 1, dark ? 0.54 : 0.61, dark ? 0.70 : 0.45, 1);
    }

    function innerRadius(depth) { return hole + depth * band + 1; }
    function outerRadius(depth) { return hole + (depth + 1) * band - 1; }

    readonly property var sectors: {
        const result = [];
        function append(entries, total, start, span, depth, branch, tint, prefix) {
            if (!total || chart.band <= 2) return;
            const inner = chart.innerRadius(depth), outer = chart.outerRadius(depth);
            const mid = (inner + outer) / 2;
            let end = start;
            for (let i = 0; i < entries.length; i++) {
                const entry = entries[i];
                const at = end;
                end = Math.min(start + span, at + span * (entry.bytes / total));
                const sweep = end - at;
                const gap = (chart.turn - sweep) * mid < chart.pixel ? 0 : Math.min(0.85 / mid, sweep / 4);
                // Leave subpixel slices in the size totals and legend. Draw and hit-test
                // only the area between the visible edges of each sector.
                if ((sweep - 2 * gap) * mid < chart.pixel) continue;
                const base = depth === 0 ? chart.colorFor(entry, i) : tint;
                const color = depth === 0 ? base : Qt.hsla((base.hslHue + 1 + (i % 3 - 1) * 0.018) % 1,
                    base.hslSaturation * 0.92, base.hslLightness + (chart.dark ? -0.055 : 0.065), 1);
                const label = chart.labelFor(entry);
                const index = depth === 0 ? i : branch;
                result.push({ entry, start: at + gap, end: end - gap, inner, outer, depth, color, branch: index, label: prefix + label });
                if (entry.children?.length)
                    append(entry.children, entry.bytes, at, sweep, depth + 1, index, color, prefix + label + "/");
            }
        }
        if (frame) append(frame.children, frame.bytes, 0, turn, 0, -1, null, "");
        return result;
    }

    // At zero the entire map fits inside the chosen wedge. At one it fills the chart.
    function unfold(items, wedge, amount) {
        if (!wedge || amount >= 1) return items;
        const folded = 1 - amount;
        const angleScale = amount + folded * (wedge.end - wedge.start) / turn;
        const radiusScale = (wedge.outer - wedge.inner) / Math.max(1, radius - hole);
        function radiusAt(r) { return amount * r + folded * (wedge.inner + (r - hole) * radiusScale); }
        return items.map(s => Object.assign({}, s, {
            start: folded * wedge.start + angleScale * s.start, end: folded * wedge.start + angleScale * s.end,
            inner: radiusAt(s.inner), outer: radiusAt(s.outer)
        }));
    }
    readonly property var drawnSectors: {
        if (!origin || progress >= 1) return sectors;
        if (origin.id >= 0) return unfold(sectors, origin.focus, progress);
        const drawn = [];
        for (const sector of sectors) {
            const delay = sector.depth * 0.09;
            const edge = turn * Math.max(0, (progress - delay) / (1 - delay));
            if (edge > sector.start)
                drawn.push(Object.assign({}, sector, {end: Math.min(edge, sector.end)}));
        }
        return drawn;
    }

    function hit(x, y) {
        if (origin?.id >= 0 && progress < 0.5) return null;
        const dx = x - width / 2, dy = y - height / 2;
        const distance = Math.hypot(dx, dy);
        if (distance < hole || distance >= radius) return null;
        const angle = (Math.atan2(dy, dx) + Math.PI / 2 + turn) % turn;
        return drawnSectors.find(s => distance >= s.inner && distance < s.outer && angle >= s.start && angle < s.end) ?? null;
    }
    readonly property var hoveredSector: pointer.containsMouse ? hit(pointer.mouseX, pointer.mouseY) : null
    readonly property bool overCenter: pointer.containsMouse && Math.hypot(pointer.mouseX - width / 2, pointer.mouseY - height / 2) < hole
    readonly property var detail: hoveredSector?.entry ?? frame?.children[legendIndex] ?? null
    onDrawnSectorsChanged: plot.requestPaint()
    onProgressChanged: plot.requestPaint()
    onHoveredSectorChanged: plot.requestPaint()
    onLegendIndexChanged: plot.requestPaint()
    onTrackChanged: plot.requestPaint()

    Canvas {
        id: plot
        anchors.fill: parent
        antialiasing: true
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (chart.band <= 2) return;
            const cx = width / 2, cy = height / 2;
            function fillSector(inner, outer, start, end, color) {
                const a = start - Math.PI / 2, b = end - Math.PI / 2;
                const mid = (a + b) / 2;
                ctx.beginPath();
                // Qt Canvas can collapse a reverse 360° arc. Two arcs preserve the hole.
                ctx.arc(cx, cy, outer, a, mid, false);
                ctx.arc(cx, cy, outer, mid, b, false);
                ctx.lineTo(cx + inner * Math.cos(b), cy + inner * Math.sin(b));
                ctx.arc(cx, cy, inner, b, mid, true);
                ctx.arc(cx, cy, inner, mid, a, true);
                ctx.closePath();
                ctx.fillStyle = color;
                ctx.fill();
            }
            ctx.globalAlpha = chart.origin?.id < 0 ? chart.progress : 1;
            for (let i = 0; i < 3; ++i)
                fillSector(chart.innerRadius(i), chart.outerRadius(i), 0, chart.turn, chart.track);
            function paintSectors(items, opacity, interactive) {
                if (opacity <= 0) return;
                ctx.globalAlpha = opacity;
                for (const s of items) {
                    const active = interactive && (s === chart.hoveredSector || s.branch === chart.legendIndex);
                    fillSector(s.inner, s.outer, s.start, s.end, active ? Qt.lighter(s.color, 1.20) : s.color);
                }
            }
            const old = chart.origin;
            if (old && !chart.returnSector)
                paintSectors(old.sectors, 1 - chart.progress, false);
            paintSectors(chart.drawnSectors, old?.id >= 0 ? chart.progress : 1, true);
            if (chart.returnSector)
                paintSectors(chart.unfold(old.sectors, chart.returnSector, 1 - chart.progress), 1 - chart.progress, false);
            ctx.globalAlpha = 1;
        }
    }

    Column {
        anchors.centerIn: parent
        opacity: chart.progress
        width: Math.max(0, chart.hole * 1.78)
        spacing: 1
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: chart.detail ? chart.labelFor(chart.detail) : chart.overCenter && chart.canGoUp
                ? Translation.tr("Up one level") : Translation.tr("On disk")
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: chart.frame ? chart.formatBytes(chart.detail?.bytes ?? chart.frame.bytes) : "…"
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.larger
            fontSizeMode: Text.Fit
            font.weight: Font.DemiBold
        }
        StyledText {
            visible: !!chart.detail && chart.frame?.bytes > 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: visible ? Math.round(chart.detail.bytes * 100 / chart.frame.bytes) + "%" : ""
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: chart.hoveredSector || (chart.overCenter && chart.canGoUp) ? Qt.PointingHandCursor : Qt.ArrowCursor
        property var pressedEntry: null
        onPressed: event => pressedEntry = chart.hit(event.x, event.y)?.entry ?? null
        onClicked: event => {
            const entry = chart.hit(event.x, event.y)?.entry;
            if (entry && pressedEntry && entry.id === pressedEntry.id && entry.offset === pressedEntry.offset && entry.uri === pressedEntry.uri)
                chart.activated(entry);
            else if (!pressedEntry && Math.hypot(event.x - chart.width / 2, event.y - chart.height / 2) < chart.hole && chart.canGoUp)
                chart.up();
        }
    }
}
