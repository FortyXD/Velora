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
    property int nextGeneration: 0
    property bool ready: false
    readonly property bool wanted: Object.keys(subscriptions).length > 0 && !GlobalStates.screenLocked

    // A holder pins Qt's already decoded pixmap. Active capture files can then
    // be unlinked, even if the next consumer belongs to a different popup.
    property var recent: []
    property int cacheLifetime: 30000
    property int lockGeneration: 0
    Component {
        id: holderFactory
        QtObject {
            id: holder
            required property var owner
            property string identifier
            property var frame: null
            property var grab: null
            property Image pin: Image { cache: true; asynchronous: true }
            property Timer expiry: Timer {
                interval: root.cacheLifetime
                onTriggered: {
                    if (Object.values(root.subscriptions).some(item => item.id === holder.identifier))
                        restart();
                    else root.forget(holder);
                }
            }
            property Connections closeConnection: Connections {
                target: holder.owner
                function onClosed() { root.forget(holder); }
            }
            onOwnerChanged: if (!owner) root.forget(holder)
        }
    }
    function forget(holder) {
        if (!recent.includes(holder)) return;
        recent = recent.filter(entry => entry !== holder);
        holder.frame = null;
        holder.pin.source = "";
        holder.grab = null;
        holder.destroy();
    }
    function cached(owner, id) {
        if (!owner || GlobalStates.screenLocked) return null;
        return recent.find(entry => entry.owner === owner && entry.identifier === id)?.frame ?? null;
    }
    function remember(owner, id, frame, grab = null) {
        if (!owner || !frame || GlobalStates.screenLocked) return;
        let holder = recent.find(entry => entry.owner === owner);
        if (!holder) holder = holderFactory.createObject(root, {owner: owner});
        if (holder.frame !== frame) {
            holder.identifier = id;
            holder.grab = grab;
            holder.pin.source = grab ? "" : frame.source;
            holder.frame = frame;
        }
        holder.expiry.restart();
        if (recent[0] !== holder)
            recent = [holder, ...recent.filter(entry => entry !== holder)];
        if (recent.length > 8) forget(recent[8]);
    }

    function generationFor(id) {
        return Object.values(subscriptions).find(item => item.id === id)?.generation ?? ++nextGeneration;
    }
    function acquire(id, width, height, live, cursor, priority = 0, sourceWidth = 0, sourceHeight = 0) {
        const token = ++nextToken;
        const generation = generationFor(id);
        subscriptions = Object.assign({}, subscriptions, {[token]: {id, width, height, live, cursor,
            priority, sourceWidth, sourceHeight, generation, refresh: 0}});
        flushTimer.start();
        return token;
    }
    function release(token) {
        const releasedId = subscriptions[token]?.id;
        const updated = Object.assign({}, subscriptions);
        delete updated[token];
        subscriptions = updated;
        const retained = {};
        for (const item of Object.values(updated)) if (frames[item.id]) retained[item.id] = frames[item.id];
        frames = retained;
        if (releasedId && !Object.values(updated).some(item => item.id === releasedId))
            recent.find(holder => holder.identifier === releasedId)?.expiry.restart();
        flushTimer.start();
    }
    function update(token, id, width, height, live, cursor, priority = 0, sourceWidth = 0, sourceHeight = 0) {
        const previous = subscriptions[token];
        if (!previous) return;
        if (previous.id === id && previous.width === width && previous.height === height
            && previous.live === live && previous.cursor === cursor && previous.priority === priority
            && previous.sourceWidth === sourceWidth && previous.sourceHeight === sourceHeight) return;
        const generation = previous.id === id ? previous.generation : generationFor(id);
        subscriptions = Object.assign({}, subscriptions, {[token]: {id, width, height, live, cursor,
            priority, sourceWidth, sourceHeight, generation, refresh: previous.refresh}});
        if (previous.id !== id && !Object.values(subscriptions).some(item => item.id === previous.id)) {
            const retained = Object.assign({}, frames);
            delete retained[previous.id];
            frames = retained;
        }
        flushTimer.start();
    }
    function refresh(token) {
        if (!subscriptions[token]) return;
        subscriptions[token].refresh++;
        flushTimer.start();
    }
    function send() {
        if (!ready) return;
        const merged = {};
        if (!GlobalStates.screenLocked) for (const item of Object.values(subscriptions)) {
            const previous = merged[item.id];
            merged[item.id] = previous ? Object.assign({}, item, {
                width: Math.max(item.width, previous.width), height: Math.max(item.height, previous.height),
                live: item.live || previous.live, cursor: item.cursor || previous.cursor,
                priority: Math.max(item.priority, previous.priority), refresh: Math.max(item.refresh, previous.refresh)
            }) : item;
        }
        worker.write(JSON.stringify({op: "set", windows: Object.values(merged).sort((a, b) => b.priority - a.priority)}) + "\n");
    }
    function handle(line) {
        try {
            const message = JSON.parse(line);
            if (message.event === "ready") { ready = true; send(); }
            else if (message.event === "frame" && wanted && Object.values(subscriptions).some(item =>
                item.id === message.id && item.generation === message.generation)) {
                frames = Object.assign({}, frames, {[message.id]: {
                    source: "file://" + message.path + "?revision=" + message.revision,
                    width: message.width, height: message.height
                }});
            }
        } catch (error) { console.warn("[WindowPreviews]", error); }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                root.lockGeneration++;
                for (const holder of root.recent.slice()) root.forget(holder);
                root.frames = {};
                root.send();
                worker.running = false;
            }
        }
    }
    onWantedChanged: {
        if (wanted) { stopTimer.stop(); worker.running = true; }
        else { send(); frames = {}; stopTimer.restart(); }
    }
    Timer { id: flushTimer; interval: 0; onTriggered: root.send() }
    Timer { id: stopTimer; interval: 3000; onTriggered: if (!root.wanted) worker.running = false }
    Timer { id: retryTimer; interval: 3000; onTriggered: if (root.wanted) worker.running = true }
    Process {
        id: worker
        command: [Quickshell.shellPath("scripts/helper"), "window-previews"]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => root.handle(line) }
        onExited: { root.ready = false; root.frames = {}; if (root.wanted) retryTimer.restart(); }
    }
}
