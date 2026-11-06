.pragma library

function keyFor(metric) {
    return metric === "charge" ? "percentage" : metric === "voltage" ? "voltage_v" : "battery_power_w";
}
function unitFor(metric) { return metric === "charge" ? "%" : metric === "voltage" ? "V" : "W"; }
function valid(value) { return typeof value === "number" && isFinite(value); }
function domain(points, metric) {
    if (metric === "charge") return [0, 100];
    const key = keyFor(metric);
    const values = points.map(p => p[key]).filter(valid);
    if (values.length === 0) return metric === "voltage" ? [0, 1] : [-1, 1];
    let low = Math.min.apply(null, values), high = Math.max.apply(null, values);
    if (metric === "power") {
        low = Math.min(0, low);
        high = Math.max(0, high);
        if (low === 0 && high === 0) return [-1, 1];
        const step = Math.max(1, Math.pow(10, Math.floor(Math.log10(Math.max(Math.abs(low), Math.abs(high), 1)))));
        return [low < 0 ? Math.floor((low - step * 0.2) / step) * step : 0,
            high > 0 ? Math.ceil((high + step * 0.2) / step) * step : 0];
    }
    const pad = Math.max(0.1, (high - low) * 0.15);
    return [Math.max(0, Math.floor((low - pad) * 10) / 10), Math.ceil((high + pad) * 10) / 10];
}
function segments(points, metric) {
    const key = keyFor(metric);
    const result = [];
    let segment = [];
    for (const point of points) {
        if (point.gap_before || (point.gaps_before ?? []).includes(key) || !valid(point[key])) {
            if (segment.length) result.push(segment);
            segment = [];
        }
        if (valid(point[key])) segment.push(point);
    }
    if (segment.length) result.push(segment);
    return result;
}
// Monotone Hermite slopes keep curves smooth without inventing overshoot/peaks.
function tangents(points) {
    if (points.length < 2) return [0];
    const slopes = [];
    for (let i = 1; i < points.length; ++i)
        slopes.push((points[i].y - points[i - 1].y) / Math.max(0.001, points[i].x - points[i - 1].x));
    const m = [slopes[0]];
    for (let i = 1; i < points.length - 1; ++i)
        m.push(slopes[i - 1] * slopes[i] <= 0 ? 0 : 2 * slopes[i - 1] * slopes[i] / (slopes[i - 1] + slopes[i]));
    m.push(slopes[slopes.length - 1]);
    for (let i = 0; i < slopes.length; ++i) {
        if (slopes[i] === 0) { m[i] = 0; m[i + 1] = 0; continue; }
        const a = m[i] / slopes[i], b = m[i + 1] / slopes[i];
        const length = Math.sqrt(a * a + b * b);
        if (length > 3) { m[i] = 3 * a / length * slopes[i]; m[i + 1] = 3 * b / length * slopes[i]; }
    }
    return m;
}
function nearest(points, timestamp, metric) {
    const key = keyFor(metric);
    let best = null, distance = Infinity;
    for (const segment of segments(points, metric)) {
        if (timestamp < segment[0].timestamp - 1 || timestamp > segment[segment.length - 1].timestamp + 1) continue;
        for (const point of segment) {
            const d = Math.abs(point.timestamp - timestamp);
            if (d < distance) { best = point; distance = d; }
        }
    }
    return best;
}
