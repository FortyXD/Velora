import QtQuick
import Quickshell

// The usable part of the editor column inside the settings viewport.
Item {
    id: area
    property Item column
    TransformWatcher { id: mapping; a: area.parent; b: area.column }
    readonly property rect available: {
        mapping.transform;
        if (!parent) return Qt.rect(0, 0, 0, 0);
        if (column) {
            const rect = column.mapToItem(parent, 0, 0, column.width, column.height);
            const left = Math.max(0, rect.x), top = Math.max(0, rect.y);
            const right = Math.min(parent.width, rect.x + rect.width), bottom = Math.min(parent.height, rect.y + rect.height);
            if (right > left && bottom > top) {
                // Borrow only the space the controls need while the navigation rail expands.
                const width = Math.max(right - left, Math.min(parent.width, 400));
                const x = Math.max(0, Math.min((left + right - width) / 2, parent.width - width));
                return Qt.rect(x, top, width, bottom - top);
            }
        }
        return Qt.rect(0, 0, parent.width, parent.height);
    }
    x: available.x
    y: available.y
    width: available.width
    height: available.height
}
