import QtQuick
import qs.modules.common

// Keep a photograph of an opened comparison. Browsing the catalog only loads images.
QtObject {
    id: root
    property var frames: new Map()
    property int revision: 0

    function key(preset, monitor) {
        return revision + "/" + preset.id + "/" + Qt.md5(JSON.stringify(preset))
            + "/" + monitor.logicalWidth + "x" + monitor.logicalHeight + "/" + (monitor.output?.name ?? "");
    }
    function remember(key, result) {
        const next = new Map(frames);
        if (next.size >= 32) next.delete(next.keys().next().value);
        next.set(key, result); // The image:// URL belongs to the grab result.
        frames = next;
    }
    function invalidate() {
        revision++;
        if (frames.size) frames = new Map();
    }
    property Connections configChanges: Connections {
        target: Config
        function onDiskSynced() { root.invalidate() }
    }
    property Connections paletteChanges: Connections {
        target: Appearance.m3colors
        function onGeneratedRolesChanged() { root.invalidate() }
    }
}
