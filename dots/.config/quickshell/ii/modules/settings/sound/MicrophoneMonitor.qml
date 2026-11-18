import QtQuick
import Quickshell.Io

Item {
    id: root
    required property bool active
    required property string sourceName
    required property string sinkName
    readonly property string route: active && sourceName && sinkName ? JSON.stringify([sourceName, sinkName]) : ""
    readonly property bool listening: childActive && process.running && activeRoute === route
    readonly property bool failed: route.length > 0 && route === failedRoute
    property bool childActive: false
    property bool stopping: false
    property string activeRoute: ""
    property string failedRoute: ""
    visible: false

    function updateRoute() {
        if (childActive) {
            if (activeRoute !== route && !stopping) {
                stopping = true;
                process.running = false;
            }
            return;
        }
        if (!route || failed) return;
        activeRoute = route;
        childActive = true;
        stopping = false;
        // Quickshell may be terminated while its window is still open.
        process.command = ["setpriv", "--pdeathsig", "TERM", "--", "pw-loopback", "--name", "velora_settings_monitor",
            "--capture", sourceName, "--playback", sinkName, "--channels", "1", "--channel-map", "[ MONO ]", "--latency", "10",
            "--capture-props", "{ node.name = velora_settings_monitor_capture node.dont-fallback = true node.dont-reconnect = true }",
            "--playback-props", "{ node.name = velora_settings_monitor_playback node.dont-fallback = true node.dont-reconnect = true }"];
        process.running = true;
    }
    onRouteChanged: { failedRoute = ""; Qt.callLater(updateRoute); }
    Component.onDestruction: process.running = false
    Process {
        id: process
        onExited: {
            if (!root.stopping && root.activeRoute === root.route) root.failedRoute = root.route;
            root.childActive = false;
            Qt.callLater(root.updateRoute);
        }
    }
}
