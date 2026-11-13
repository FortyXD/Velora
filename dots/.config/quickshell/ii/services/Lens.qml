pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common

Singleton {
    id: root
    property bool mainShell: false
    readonly property bool enabled: Config.ready && (Config.options.search.lens.enabled ?? false)
    property bool ready: false
    property var status: ({ locked: true })
    property string problem: ""
    property var results: []
    property string query: ""
    property string queryKind: ""
    property int nextId: 1
    property int queryGeneration: 0
    property var pending: ({})
    property list<int> searchIds: []
    property int failures: 0
    property bool settingsVisible: false
    property var setupInfo: ({ installed: null, models: false, running: false, stage: "" })
    property bool unlocking: false
    property string reviewingSource: ""
    readonly property bool usable: enabled && ready && !status.locked
    property int semanticRequest: 0
    readonly property bool thinking: usable && semanticRequest !== 0 && query.length > 0 && status.config?.semantic === true && !GlobalStates.screenLocked
    readonly property bool setupRunning: setupInfo.running === true

    function checkSetup() {
        if (!setupProbe.running && !setupControl.running) setupProbe.running = true;
    }

    function acceptSetup(value) {
        const completed = setupInfo.running && !value.running && value.stage === "done";
        setupInfo = value;
        if (value.installed && enabled && !ready && !bridge.running) bridge.running = true;
        if (completed) {
            problem = "";
            reconnectNow();
        }
    }

    function prepare() {
        if (setupRunning || setupControl.running) return;
        problem = "";
        setupInfo = Object.assign({}, setupInfo, { running: true, stage: "preparing", step: 1, steps_total: 5, steps_done: 0, elapsed_seconds: 0, progress: {} });
        setupControl.command = [Quickshell.shellPath("scripts/lens-service"), "setup-start", "models"];
        setupControl.running = true;
    }

    function cancelSetup() {
        if (setupControl.running) return;
        setupControl.command = [Quickshell.shellPath("scripts/lens-service"), "setup-cancel"];
        setupControl.running = true;
    }

    function reconnectNow() {
        problem = "";
        if (ready) { if (mainShell) context(); refresh(); }
        else if (enabled && !bridge.running) bridge.running = true;
        checkSetup();
    }

    function unlockIndex() {
        if (!ready || unlocking) return;
        unlocking = true;
        call("unlock", {}, value => {
            unlocking = false;
            acceptStatus(value);
        });
    }

    function setupLabel() {
        if (setupInfo.cancelling) return Translation.tr("Finishing the current step before cancelling");
        if (setupRunning && setupInfo.stage === "models") {
            const progress = setupInfo.progress ?? {};
            if (progress.task === "model-download") return progress.model === "e5" ? Translation.tr("Downloading the text model") : Translation.tr("Downloading the image model");
            if (progress.task === "model-export") return progress.model === "e5" ? Translation.tr("Preparing the text model") : Translation.tr("Preparing the image model");
            if (progress.task === "model-package") return Translation.tr("Saving local models");
        }
        const labels = {
            preparing: Translation.tr("Preparing local search"),
            dependencies: Translation.tr("Installing required components"),
            building: Translation.tr("Preparing the search service"),
            service: Translation.tr("Starting the search service"),
            runtime: Translation.tr("Preparing the model environment"),
            "export-tools": Translation.tr("Preparing model tools"),
            models: Translation.tr("Downloading and preparing models"),
            verifying: Translation.tr("Checking local models"),
            done: Translation.tr("Setup complete"),
            failed: Translation.tr("Setup could not finish"),
            cancelled: Translation.tr("Setup cancelled"),
            interrupted: Translation.tr("Setup was interrupted")
        };
        return labels[setupInfo.stage] ?? Translation.tr("Preparing local search");
    }

    onSettingsVisibleChanged: if (settingsVisible) { checkSetup(); refresh(); }
    Timer { interval: 1500; repeat: true; running: root.settingsVisible || root.setupRunning; onTriggered: root.checkSetup() }
    Process {
        id: setupProbe
        command: [Quickshell.shellPath("scripts/lens-service"), "setup-status"]
        stdout: SplitParser { onRead: line => { try { root.acceptSetup(JSON.parse(line)); } catch (_) {} } }
    }
    Process {
        id: setupControl
        stdout: SplitParser { onRead: line => { try { root.acceptSetup(Object.assign({}, root.setupInfo, JSON.parse(line))); } catch (_) {} } }
        onExited: (code, status) => {
            if (code !== 0) root.setupInfo = Object.assign({}, root.setupInfo, { running: false, stage: "failed" });
            root.checkSetup();
        }
    }

    function call(method, params, done) {
        if (!ready) { if (done) done(null); return 0; }
        const id = nextId++;
        if (done) pending[id] = done;
        bridge.write(JSON.stringify({id, method, params: params ?? {}}) + "\n");
        return id;
    }

    function acceptStatus(value) {
        if (!value) return;
        const wasLocked = status.locked;
        status = value;
        problem = value.problem ?? "";
        if (value.locked) { results = []; queryGeneration++; semanticRequest = 0; semanticDelay.stop(); }
        else if (wasLocked && !GlobalStates.screenLocked) {
            syncApps();
            if (query.trim()) search(query);
        }
    }

    function refresh() {
        call("status", {}, value => root.acceptStatus(value));
    }

    function context() {
        if (!mainShell || !ready) return;
        if (GlobalStates.screenLocked) { results = []; query = ""; queryGeneration++; semanticRequest = 0; semanticDelay.stop(); }
        call("context", {locked: GlobalStates.screenLocked, on_battery: PowerSaving.onBattery, idle: idleMonitor.isIdle, assistant_busy: assistantBusy}, value => {
            root.acceptStatus(value);
        });
    }

    function syncApps() {
        if (!mainShell || !ready || status.locked) return;
        const apps = AppSearch.list.map(app => ({id: app.id, name: app.name, comment: app.comment, genericName: app.genericName, keywords: app.keywords.join(" ")}));
        for (let i = 0; i < Math.max(1, apps.length); i += 32)
            call("apps", {items: apps.slice(i, i + 32), begin: i === 0, end: i + 32 >= apps.length});
    }

    property bool assistantBusy: false
    function cancelSearch() {
        semanticDelay.stop();
        semanticRequest = 0;
        for (const id of searchIds) delete pending[id];
        searchIds = [];
        queryGeneration++;
        query = ""; queryKind = ""; results = [];
        call("cancel", {});
    }

    function search(text) {
        semanticRequest = 0;
        for (const id of searchIds) delete pending[id];
        searchIds = [];
        query = text;
        queryKind = "";
        const generation = ++queryGeneration;
        results = [];
        semanticDelay.stop();
        if (!enabled || !ready || status.opening || !text.trim() || GlobalStates.screenLocked) { call("cancel", {}); return; }
        const id = call("search", {query: text, semantic: false}, value => {
            if (generation === queryGeneration && value && !GlobalStates.screenLocked) {
                queryKind = value.query?.kind ?? "";
                results = value.results;
                if (value.semantic_recommended === false) semanticDelay.stop();
            }
        });
        searchIds.push(id);
        if (status.config?.semantic === true) semanticDelay.restart();
    }

    function configure(changes, done) {
        const config = Object.assign({}, status.config ?? {roots: [], excludes: [], activity: true, media: false, semantic: false, paused: false, max_files: 100000}, changes);
        call("configure", config, value => { if (value) { status = value; search(query); } if (done) done(value); });
    }

    function reviewSource(path, include) {
        if (!usable || reviewingSource !== "") return;
        reviewingSource = path;
        call("review_source", {path, include}, value => {
            reviewingSource = "";
            if (value) { status = value; problem = value.problem ?? ""; search(query); }
        });
    }

    function explanation(hit) {
        const reasons = {
            name: Translation.tr("Name match"), content: Translation.tr("Text match"),
            project: Translation.tr("Matching files in this folder"), semantic: Translation.tr("Related meaning"),
            visual: Translation.tr("Matching image or video frame"), modified: Translation.tr("File modification date")
        };
        let text = reasons[hit.reason] ?? "";
        if (hit.corrections?.length) text += " · " + Translation.tr("Spelling: %1").arg(hit.corrections.map(c => c.from + " → " + c.to).join(", "));
        if (hit.partial) text += " · " + Translation.tr("Partial match; missing: %1").arg((hit.unmatched_terms ?? []).join(", "));
        if (hit.snippet && ["content", "semantic", "project"].includes(hit.reason))
            text += " · " + String(hit.snippet).replace(/\s+/g, " ").trim().slice(0, 240);
        if (hit.activity_at) text += " · " + Translation.tr("Opened %1").arg(new Date(hit.activity_at * 1000).toLocaleString());
        if (hit.timestamp !== null && hit.timestamp !== undefined) text += " · " + Math.floor(hit.timestamp / 60) + ":" + String(Math.floor(hit.timestamp % 60)).padStart(2, "0");
        return text;
    }

    function open(hit, parent) {
        if (!enabled || !ready || GlobalStates.screenLocked || !results.some(r => r.id === hit.id && r.path === hit.path)) return;
        call("resolve", {id: hit.id}, result => {
            if (!result || GlobalStates.screenLocked) return;
            if (result.kind === "app") {
                const id = result.path.replace(/^app:/, "").replace(/\.desktop$/, "");
                const entry = AppSearch.list.find(app => app.id === id || app.id === id + ".desktop");
                if (entry) entry.execute();
                return;
            }
            const path = parent ? result.path.slice(0, result.path.lastIndexOf("/")) : result.path;
            if (!parent && result.kind === "video" && hit.timestamp !== null && hit.timestamp !== undefined)
                Quickshell.execDetached(["mpv", "--start=" + Number(hit.timestamp), "--", path]);
            else
                Qt.openUrlExternally("file://" + path.split("/").map(encodeURIComponent).join("/"));
            call("record", {path: result.path, app: "launcher", source: "launcher"});
        });
    }

    function handle(line) {
        let message;
        try { message = JSON.parse(line); } catch (_) { return; }
        if (message.type === "unavailable" && message.code === "not_installed") {
            setupInfo = Object.assign({}, setupInfo, { installed: false });
            problem = "";
            return;
        }
        if (message.type === "hello") {
            if (message.protocol !== 1) { problem = Translation.tr("Lens needs an update"); bridge.running = false; return; }
            ready = true; problem = ""; failures = 0;
            if (mainShell) call("attach", {}, value => { if (value) context(); });
            refresh();
        } else if (message.type === "response") {
            const callback = pending[message.id]; delete pending[message.id];
            if (!message.ok) problem = message.error?.message ?? Translation.tr("Lens is unavailable");
            if (callback) callback(message.ok ? message.result : null);
        }
    }

    onEnabledChanged: {
        if (!enabled) { reconnect.stop(); cancelSearch(); bridge.running = false; }
        else { bridge.running = true; checkSetup(); }
    }
    Component.onCompleted: if (enabled) { bridge.running = true; checkSetup(); }
    onAssistantBusyChanged: context()
    onMainShellChanged: if (mainShell && ready) call("attach", {}, value => { if (value) context(); })

    Connections { target: GlobalStates; function onScreenLockedChanged() { root.context(); } }
    Connections { target: PowerSaving; function onOnBatteryChanged() { root.context(); } }
    Connections { target: AppSearch; function onListChanged() { root.syncApps(); } }
    IdleMonitor {
        id: idleMonitor
        enabled: root.enabled && root.mainShell
        timeout: 120
        onIsIdleChanged: root.context()
    }
    Timer {
        id: semanticDelay
        interval: 250
        onTriggered: {
            if (!root.enabled || !root.ready || !root.query.trim() || GlobalStates.screenLocked || root.status.config?.semantic !== true) return;
            const generation = root.queryGeneration;
            const id = root.call("search", {query: root.query, semantic: true}, value => {
                if (generation === root.queryGeneration) root.semanticRequest = 0;
                if (generation === root.queryGeneration && value && !GlobalStates.screenLocked) {
                    root.queryKind = value.query?.kind ?? "";
                    root.results = value.results;
                }
            });
            root.semanticRequest = id;
            root.searchIds.push(id);
        }
    }
    Timer { interval: root.status.scanning || root.status.pending > 0 ? 2000 : 5000; repeat: true; running: root.settingsVisible && root.ready; onTriggered: root.refresh() }
    Timer { interval: root.status.opening ? 1000 : 5000; repeat: true; running: root.mainShell && root.enabled && root.ready && root.status.locked && !GlobalStates.screenLocked; onTriggered: root.context() }
    Timer { id: reconnect; interval: 1000; onTriggered: if (root.enabled) bridge.running = true }
    Process {
        id: bridge
        stdinEnabled: true
        command: [Quickshell.shellPath("scripts/lens-service"), "bridge"]
        stdout: SplitParser { onRead: line => root.handle(line) }
        onExited: {
            semanticDelay.stop();
            root.semanticRequest = 0;
            root.ready = false; root.status = ({locked: true}); root.results = []; root.pending = ({}); root.queryGeneration++; root.unlocking = false; root.reviewingSource = "";
            if (root.enabled) {
                if (root.setupInfo.installed !== false) root.problem = Translation.tr("The search service is not responding");
                reconnect.interval = Math.min(30000, 1000 * Math.pow(2, root.failures++));
                reconnect.restart();
            }
        }
    }
}
