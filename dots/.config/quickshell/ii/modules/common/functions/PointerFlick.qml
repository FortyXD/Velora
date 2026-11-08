pragma Singleton
import Quickshell

/**
 * How fast the pointer is being taken away from an edge, from the hover events
 * themselves. Nothing polls the compositor: a bar popup only knows where the
 * pointer was while it was still inside the widget, and that is enough to tell
 * a slow move toward the popup from a flick that means "get out of the way".
 */
Singleton {
    id: root

    // A gap this long means the stream stalled (a frame hitch, or the pointer
    // left and came back), so the pair says nothing about speed.
    readonly property real maxSampleGapMs: 120

    /**
     * Pixels per second along the axis that leads away from the edge.
     * `previous`/`current` are the perpendicular coordinates in item space,
     * `sign` is +1 when growing coordinates point away from the edge.
     */
    function awaySpeed(previous, current, previousMs, currentMs, sign) {
        if (previous < 0) return 0;
        const elapsed = currentMs - previousMs;
        if (elapsed <= 0 || elapsed > root.maxSampleGapMs) return 0;
        return sign * (current - previous) * 1000 / elapsed;
    }

    /**
     * Smoothed speed, never negative: moving back toward the edge is not
     * "away", and one fast frame should not decide the whole gesture.
     */
    function smooth(previousSpeed, sample) {
        return previousSpeed * 0.5 + Math.max(0, sample) * 0.5;
    }

    function isFlick(speed, threshold) {
        return threshold > 0 && speed >= threshold;
    }
}
