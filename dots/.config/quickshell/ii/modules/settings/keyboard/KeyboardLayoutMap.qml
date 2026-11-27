import QtQuick
import Quickshell
import Quickshell.Io

Process {
    id: root
    required property bool needed
    required property string layout
    required property string variant
    readonly property string layoutId: layout + "/" + variant
    property var keys: ({})
    property bool unavailable: false
    property var cache: ({})
    property string request
    property string displayedId

    function updateMap() {
        if (!needed || displayedId === layoutId) return;
        const cached = cache[layoutId];
        if (cached !== undefined) {
            keys = cached ?? {};
            unavailable = cached === null;
            displayedId = layoutId;
        } else if (!running) {
            request = layoutId;
            command = [Quickshell.shellPath("scripts/helper"), "layout-keys", layout, variant];
            running = true;
        }
    }

    onLayoutIdChanged: Qt.callLater(updateMap)
    onNeededChanged: if (needed) Qt.callLater(updateMap)
    Component.onCompleted: Qt.callLater(updateMap)
    stdout: StdioCollector { id: output; waitForEnd: true }
    onExited: {
        let result = null;
        try { result = JSON.parse(output.text).keys ?? null; } catch (error) {}
        cache[request] = result;
        // Only publish the latest layout. Keep the old legends visible while a new map is compiling.
        Qt.callLater(updateMap);
    }
}
