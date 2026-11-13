pragma Singleton
import Quickshell

/**
 * Where a dragged display may magnetically land, decided per axis.
 *
 * The model follows the mature tools in this space rather than inventing rules:
 * arandr (the reference XRandR GUI) snaps each axis on its own to the neighbour's
 * near edge, far edge and centre, and uses a tolerance measured in *widget* pixels
 * so the feel does not change with zoom. Keeping the axes independent is what lets
 * a shorter display slide along a taller one, and adding the centre target is what
 * fixes the complaint people hit on Windows, where only the top and bottom edges
 * snap and unequal displays cannot be lined up in the middle.
 *
 * Nothing here decides whether snapping is wanted: the caller passes a tolerance of
 * zero to place a display exactly where the pointer left it.
 */
Singleton {
    id: root

    // Pointer pixels, not desktop pixels: the canvas is zoomed far out.
    readonly property real widgetTolerance: 6

    /**
     * boxes: [{ name, x, y, width, height }] in desktop coordinates.
     * name: the display being moved. moving: its { width, height }.
     * Returns the candidate origins { x: [...], y: [...] } for that display.
     */
    function targets(boxes, name, moving, bounds) {
        let xs = [], ys = [];
        const add = (list, value) => { if (list.indexOf(value) < 0) list.push(value); };
        for (const other of boxes ?? []) {
            if (!other || other.name === name) continue;
            // Flush on either side of this neighbour, and centred on it.
            add(xs, other.x);
            add(xs, other.x + other.width);
            add(xs, other.x - moving.width);
            add(xs, other.x + other.width - moving.width);
            add(xs, Math.round(other.x + other.width / 2 - moving.width / 2));
            add(ys, other.y);
            add(ys, other.y + other.height);
            add(ys, other.y - moving.height);
            add(ys, other.y + other.height - moving.height);
            add(ys, Math.round(other.y + other.height / 2 - moving.height / 2));
        }
        // The edges of the drawn area itself, so a display can be lined up with the
        // layout instead of only with its neighbours.
        if (bounds) {
            add(xs, bounds.x);
            add(xs, bounds.x + bounds.width);
            add(xs, bounds.x + Math.round((bounds.width - moving.width) / 2));
            add(ys, bounds.y);
            add(ys, bounds.y + bounds.height);
            add(ys, bounds.y + Math.round((bounds.height - moving.height) / 2));
        }
        return { x: xs, y: ys };
    }

    /** Nearest candidate on one axis within tolerance, or the free value. */
    function axis(values, value, tolerance) {
        const result = { value: value, snapped: false };
        if (!(tolerance > 0)) return result;
        let best = null;
        for (const candidate of values ?? []) {
            const distance = Math.abs(candidate - value);
            if (distance <= tolerance && (!best || distance < best.distance)) best = { candidate: candidate, distance: distance };
        }
        if (best) { result.value = best.candidate; result.snapped = true; }
        return result;
    }

    /**
     * Where the dragged display should sit, and which lines to draw as feedback.
     * x/y are the pointer's desktop coordinates; tolerance is in desktop pixels.
     */
    function suggest(boxes, name, moving, x, y, tolerance, bounds) {
        const found = targets(boxes, name, moving, bounds);
        const snappedX = axis(found.x, x, tolerance);
        const snappedY = axis(found.y, y, tolerance);
        const guide = { x: snappedX.snapped ? snappedX.value : null, y: snappedY.snapped ? snappedY.value : null };
        return {
            x: Math.round(snappedX.value), y: Math.round(snappedY.value),
            guide: (guide.x === null && guide.y === null) ? null : guide,
            // Which kind of alignment won, for the label the canvas shows.
            aligned: snappedX.snapped || snappedY.snapped
        };
    }
}
