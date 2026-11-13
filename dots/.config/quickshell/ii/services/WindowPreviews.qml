pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root
    property var subscriptions: ({})
    property var frames: ({})
    property int nextToken: 0
    property bool ready: false
    readonly property bool wanted: Object.keys(subscriptions).length > 0 && !GlobalStates.screenLocked

    function acquire(id, width, height, live, cursor) {
        const token = ++nextToken;
        subscriptions = Object.assign({}, subscriptions, {[token]: {id, width, height, live, cursor, refresh: 0}});
        flushTimer.restart();
        return token;
    }
    function release(token) {
        const updated = Object.assign({}, subscriptions);
        delete updated[token];
        subscriptions = updated;
        const retained = {};
        for (const item of Object.values(updated)) if (frames[item.id]) retained[item.id] = frames[item.id];
        frames = retained;
        flushTimer.restart();
    }
    function update(token, id, width, height, live, cursor) {
        const previous = subscriptions[token];
        if (!previous) return;
        if (previous.id === id && previous.width === width && previous.height === height
            && previous.live === live && previous.cursor === cursor) return;
        subscriptions = Object.assign({}, subscriptions, {[token]: {id, width, height, live, cursor, refresh:previous.refresh}});
        if (previous.id !== id && !Object.values(subscriptions).some(item => item.id === previous.id)) {
            const retained = Object.assign({}, frames);
            delete retained[previous.id];
            frames = retained;
        }
        flushTimer.restart();
    }
    function refresh(token) {
        if (!subscriptions[token]) return;
        subscriptions[token].refresh++;
        flushTimer.restart();
    }
    function send() {
        if (!ready) return;
        const merged = {};
        if (!GlobalStates.screenLocked) for (const item of Object.values(subscriptions)) {
            const previous = merged[item.id];
            merged[item.id] = previous ? {id:item.id, width:Math.max(item.width, previous.width),
                height:Math.max(item.height, previous.height), live:item.live || previous.live,
                cursor:item.cursor || previous.cursor, refresh:Math.max(item.refresh, previous.refresh)} : item;
        }
        worker.write(JSON.stringify({op:"set", windows:Object.values(merged)}) + "\n");
    }
    function handle(line) {
        try {
            const message = JSON.parse(line);
            if (message.event === "ready") { ready = true; send(); }
            else if (message.event === "frame" && wanted && Object.values(subscriptions).some(item => item.id === message.id)) {
                frames = Object.assign({}, frames, {[message.id]: {
                    source: "file://" + message.path + "?revision=" + message.revision,
                    width: message.width, height: message.height
                }});
            }
        } catch (error) { console.warn("[WindowPreviews]", error); }
    }
    onWantedChanged: {
        if (!wanted) { send(); frames = {}; }
        else worker.running = true;
        stopTimer.restart();
    }
    Timer { id: flushTimer; interval: 20; onTriggered: root.send() }
    Timer { id: stopTimer; interval: 200; onTriggered: if (!root.wanted) worker.running = false }
    Timer { id: retryTimer; interval: 3000; onTriggered: if (root.wanted) worker.running = true }
    Process {
        id: worker
        command: ["/usr/bin/python3", "-I", Quickshell.shellPath("scripts/window-previews.py")]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => root.handle(line) }
        onExited: { root.ready = false; if (root.wanted) retryTimer.restart(); }
    }
}
