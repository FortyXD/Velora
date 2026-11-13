pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

Singleton {
    id: root
    property var chats: []
    property string query: ""
    property string problem: ""
    property int sequence: 0
    property var pending: ({})
    property var outbox: []
    property bool started: false
    readonly property bool locked: GlobalStates.screenLocked
    onLockedChanged: if (locked) chats = []
    function call(method, params, callback) {
        const id = ++sequence;
        pending[id] = callback ?? (() => {});
        const line = JSON.stringify({id, method, params}) + "\n";
        if (started) process.write(line);
        else { outbox = outbox.concat([line]); process.running = true; }
    }
    function refresh() {
        if (locked) return;
        const requested = query;
        call("list", {query:requested}, value => { if (!locked && requested === query) chats = value; });
    }
    function save(chat, callback) {
        const summary = {id:chat.id, title:chat.title, createdAt:chat.createdAt, updatedAt:chat.updatedAt, mode:chat.mode, model:chat.model};
        call("save", chat, (value, error) => {
            if (error) { if (callback) callback(false, error); return; }
            if (!locked) {
                if (query) refresh();
                else chats = chats.filter(c => c.id !== summary.id).concat([summary]).sort((a, b) => b.updatedAt - a.updatedAt);
            }
            if (callback) callback(true, "");
        });
    }
    function remove(uid) { call("delete", {id:uid}, () => refresh()); }
    function rename(uid, title) { call("rename", {id:uid, title}, () => refresh()); }
    onQueryChanged: searchDelay.restart()
    Timer { id: searchDelay; interval: 200; onTriggered: root.refresh() }
    Process {
        id: process
        command: ["python3", Quickshell.shellPath("scripts/chat-store.py"), Directories.aiChats]
        stdinEnabled: true
        onStarted: {
            root.started = true;
            for (const line of root.outbox) process.write(line);
            root.outbox = [];
        }
        stdout: SplitParser {
            onRead: line => {
                let reply;
                try { reply = JSON.parse(line); } catch (_) { return; }
                const callback = root.pending[reply.id];
                delete root.pending[reply.id];
                if (!reply.ok) { root.problem = Translation.tr("Could not save or open the chat") + ": " + reply.error; if (callback) callback(null, root.problem); return; }
                root.problem = "";
                if (callback) callback(reply.result);
            }
        }
        onExited: (code, status) => {
            const waiting = root.pending;
            root.started = false; root.outbox = []; root.pending = ({});
            if (code !== 0 || Object.keys(waiting).length) root.problem = Translation.tr("Chat storage stopped. Try again.");
            for (const callback of Object.values(waiting)) if (callback) callback(null, root.problem || Translation.tr("Chat storage stopped. Try again."));
        }
    }
}
