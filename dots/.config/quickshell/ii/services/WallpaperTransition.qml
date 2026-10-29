pragma Singleton

import QtQuick
import Quickshell

// Rendering acknowledgements, rather than a guessed delay from a config change.
Singleton {
    id: root
    property var screens: ({})
    readonly property bool changing: Object.values(root.screens).some(state => state.pending)
    readonly property bool loading: Object.values(root.screens).some(state => state.pending && !state.startedAt)
    signal presented(string screenName, string path)
    signal started(string screenName, string path)

    // Pictures decoded ahead, before a preset covers the screen: switching to one is then instant.
    // Each screen reports the picture it holds ready.
    property var preloaded: ({})
    signal preloadRequested(string path)
    function preload(path) {
        root.preloadRequested(path);
    }
    function reportPreloaded(screenName, path) {
        const next = Object.assign({}, root.preloaded);
        next[screenName] = path;
        root.preloaded = next;
    }
    // Ready on every screen that shows wallpapers (none at all counts as ready)
    function isPreloaded(path) {
        return Object.keys(root.screens).every(name => root.preloaded[name] === path || root.screens[name]?.path === path);
    }

    function update(screenName, state) {
        const next = Object.assign({}, root.screens);
        next[screenName] = state;
        root.screens = next;
    }
    function begin(screenName, path) {
        const previous = root.screens[screenName];
        root.update(screenName, { path: previous?.path ?? "", wanted: path, pending: true, startedAt: 0, duration: 0 });
    }
    function present(screenName, path, duration = 700) {
        if (root.screens[screenName]?.wanted !== path) return;
        root.update(screenName, { path: path, wanted: path, pending: true, startedAt: Date.now(), duration: duration });
        root.presented(screenName, path);
        root.started(screenName, path);
    }
    function remainingDuration(fallback) {
        const remaining = Object.values(root.screens).filter(state => state.pending && state.startedAt)
            .map(state => Math.max(0, state.startedAt + state.duration - Date.now()));
        return remaining.length > 0 ? Math.max.apply(null, remaining) : fallback;
    }
    function finish(screenName, path) {
        const state = root.screens[screenName];
        if (state?.wanted !== path) return;
        root.update(screenName, { path: state.path, wanted: path, pending: false, startedAt: state.startedAt, duration: state.duration });
    }
    function remove(screenName) {
        const next = Object.assign({}, root.screens);
        delete next[screenName];
        root.screens = next;
    }
}
