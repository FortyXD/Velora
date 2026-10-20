pragma Singleton
import Quickshell

/**
 * Places the windows of one workspace inside a miniature so that every one of them can be seen.
 * Windows that sit side by side keep their real places. When they cover each other (a fullscreen or
 * maximized window over the rest, a pile of floating windows), all of them are spread out in a grid.
 */
Singleton {
    id: root

    // Share of the smaller window that has to be covered before the windows count as stacked
    readonly property real stackedOverlap: 0.5

    function overlapArea(a, b) {
        const width = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x);
        const height = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y);
        return width > 0 && height > 0 ? width * height : 0;
    }

    function needsSpread(windows) {
        if (windows.length < 2) return false;
        if (windows.some(win => win.fullscreen)) return true;
        for (let i = 0; i < windows.length; i++) {
            for (let j = i + 1; j < windows.length; j++) {
                const smaller = Math.min(windows[i].width * windows[i].height, windows[j].width * windows[j].height);
                if (smaller > 0 && root.overlapArea(windows[i], windows[j]) > smaller * root.stackedOverlap) return true;
            }
        }
        return false;
    }

    // windows: [{ key, x, y, width, height, fullscreen }] in the miniature's coordinates.
    // Returns { spread, rects: { key: { x, y, width, height } } }.
    function layout(windows, areaWidth, areaHeight, gap = 6) {
        let rects = {};
        const keepPlaces = () => {
            for (const win of windows) rects[win.key] = { "x": win.x, "y": win.y, "width": win.width, "height": win.height };
            return { "spread": false, "rects": rects };
        };
        if (!root.needsSpread(windows)) return keepPlaces();

        // In the reading order of their real places, so the grid still resembles the screen
        const ordered = [...windows].sort((a, b) => (a.y - b.y) || (a.x - b.x));
        const count = ordered.length;
        const fitIn = (win, cellWidth, cellHeight) => Math.min(1, cellWidth / Math.max(1, win.width), cellHeight / Math.max(1, win.height));

        // The column count that leaves the windows the most room
        let best = null;
        for (let columns = 1; columns <= count; columns++) {
            const rows = Math.ceil(count / columns);
            const cellWidth = (areaWidth - gap * (columns + 1)) / columns;
            const cellHeight = (areaHeight - gap * (rows + 1)) / rows;
            if (cellWidth <= 0 || cellHeight <= 0) continue;
            let covered = 0;
            for (const win of ordered) {
                const fit = fitIn(win, cellWidth, cellHeight);
                covered += win.width * fit * win.height * fit;
            }
            if (!best || covered > best.covered) best = { "columns": columns, "rows": rows, "cellWidth": cellWidth, "cellHeight": cellHeight, "covered": covered };
        }
        if (!best) return keepPlaces();

        for (let i = 0; i < count; i++) {
            const win = ordered[i];
            const row = Math.floor(i / best.columns);
            const column = i % best.columns;
            const inRow = Math.min(best.columns, count - row * best.columns);
            const rowOffset = (best.columns - inRow) * (best.cellWidth + gap) / 2; // A short last row is centered
            const fit = fitIn(win, best.cellWidth, best.cellHeight);
            const width = win.width * fit;
            const height = win.height * fit;
            rects[win.key] = {
                "x": gap + rowOffset + column * (best.cellWidth + gap) + (best.cellWidth - width) / 2,
                "y": gap + row * (best.cellHeight + gap) + (best.cellHeight - height) / 2,
                "width": width,
                "height": height
            };
        }
        return { "spread": true, "rects": rects };
    }
}
