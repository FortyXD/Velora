pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Wayland
import qs

QtObject {
    id: root
    property bool active: false
    property var current: []
    property var windows: []
    property var displayed: []
    property var readyWindows: []
    property bool componentReady: false
    // Bound decoded-image memory independently of how many apps the pointer visits.
    property int retainedLimit: 8
    readonly property var openWindows: ToplevelManager.toplevels.values

    function refresh() {
        if (!componentReady) return;
        if (!active || GlobalStates.screenLocked) {
            displayed = []; readyWindows = []; windows = []; return;
        }
        const wanted = current.filter(window => window && openWindows.includes(window));
        const previous = displayed.filter(window => openWindows.includes(window) && readyWindows.includes(window));
        // Keep the complete previous group until every card in the requested group is ready.
        const protectedWindows = previous.filter(window => !wanted.includes(window)).concat(wanted);
        const retained = windows.filter(window => window && openWindows.includes(window) && !protectedWindows.includes(window));
        const next = (retainedLimit > 0 ? retained.slice(-retainedLimit) : []).concat(protectedWindows);
        readyWindows = readyWindows.filter(window => next.includes(window));
        displayed = previous;
        windows = next;
        presentReady();
    }
    function presentReady() {
        if (!active || GlobalStates.screenLocked) return;
        const wanted = current.filter(window => window && openWindows.includes(window));
        if (wanted.length === 0) { displayed = []; return; }
        if (wanted.every(window => readyWindows.includes(window))) {
            displayed = wanted;
            const retained = windows.filter(window => !wanted.includes(window));
            const next = (retainedLimit > 0 ? retained.slice(-retainedLimit) : []).concat(wanted);
            readyWindows = readyWindows.filter(window => next.includes(window));
            windows = next;
        }
    }
    function setReady(window, ready) {
        if (!active || GlobalStates.screenLocked || !windows.includes(window)) return;
        if (ready === readyWindows.includes(window)) return;
        readyWindows = ready ? readyWindows.concat([window]) : readyWindows.filter(item => item !== window);
        if (!ready) displayed = displayed.filter(item => item !== window);
        presentReady();
    }
    onActiveChanged: refresh()
    onCurrentChanged: refresh()
    onOpenWindowsChanged: refresh()
    onRetainedLimitChanged: refresh()
    Component.onCompleted: { componentReady = true; refresh(); }
    property Connections lockConnection: Connections {
        target: GlobalStates
        function onScreenLockedChanged() { root.refresh(); }
    }
}
