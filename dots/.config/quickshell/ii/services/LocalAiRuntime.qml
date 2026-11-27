pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

Singleton {
    id: root
    property var pending: []
    property var users: []
    readonly property int configuredIdle: Config.options.ai?.modelIdleSeconds ?? -1
    readonly property int idleSeconds: configuredIdle < 0 ? (PowerSaving.onBattery ? 30 : 60) * 60 : Math.min(86400, configuredIdle)
    readonly property bool cpuProfile: !Supergfxctl.modeChecked || (Supergfxctl.hasModeService &&
        (!Supergfxctl.available || !Supergfxctl.mode || Supergfxctl.integrated))
    readonly property bool allowGpu: !cpuProfile && !PowerSaving.onBattery && !PowerSaving.active
    function endpointFor(url, gpu) {
        return gpu && allowGpu ? url : url.replace(/^http:\/\/(?:localhost|127\.0\.0\.1|\[::1\]):11434(?=\/|$)/i, "http://127.0.0.1:11435");
    }
    readonly property int contextTokens: (Config.options.assistant?.contextTokens ?? 0) > 0 ? Config.options.assistant.contextTokens
        : totalMemoryKiB >= 15 * 1024 * 1024 ? 16384 : totalMemoryKiB >= 7 * 1024 * 1024 ? 8192 : 4096
    function runnerOptions(model, gpu) {
        const options = {num_ctx:contextTokens, num_gpu:gpu ? -1 : 0};
        // Smaller batches let Gemma reuse the common prefix of short CPU chats.
        if (!gpu && model === "gemma4:e4b") options.num_batch = 32;
        return options;
    }
    property int totalMemoryKiB: 0
    property var pendingEditorWarmup: null
    function waitForMemory(typing) {
        pendingEditorWarmup = typing || pendingEditorWarmup === true;
        memoryInfo.reload();
    }
    readonly property string standbyModel: Assistant.mainShell && Assistant.enabled && Assistant.profile.provider === "ollama"
        && (Config.options.assistant?.preloadOnLogin ?? true) && idleSeconds > 0 && !Assistant.profile.gpu
        && !PowerSaving.onBattery && !PowerSaving.active && !GlobalStates.screenLocked && !Assistant.fileMode
        ? Ai.installedModelIds.find(id => Ai.models[id]?.model === (Assistant.useStrong && Assistant.profile.strong_model || Assistant.profile.model)) ?? "" : ""
    onStandbyModelChanged: {
        standbyRetry.stop();
        if (standbyModel) standbyDelay.restart();
        else { standbyDelay.stop(); checkStandbyMemory = false; }
    }
    property bool checkStandbyMemory: false
    Timer {
        id: standbyDelay
        interval: 1500
        onTriggered: { root.checkStandbyMemory = true; memoryPressure.reload(); }
    }
    Timer {
        id: standbyRetry
        interval: 60000
        onTriggered: if (root.standbyModel && !root.memoryStatus && !root.preloadKey && !SidebarChat.busy)
            standbyDelay.restart()
    }
    FileView {
        id: memoryPressure
        path: "/proc/pressure/memory"
        onLoaded: {
            if (!root.checkStandbyMemory) return;
            const pressure = Number(text().match(/some avg10=([\d.]+)/)?.[1] ?? 0);
            if (pressure > 5) { root.checkStandbyMemory = false; standbyRetry.restart(); }
            else memoryInfo.reload();
        }
        onLoadFailed: if (root.checkStandbyMemory) memoryInfo.reload()
    }
    FileView {
        id: memoryInfo
        path: "/proc/meminfo"
        onLoaded: {
            root.totalMemoryKiB = Number(text().match(/MemTotal:\s+(\d+)/)?.[1] ?? 0);
            if (root.totalMemoryKiB > 0 && root.pendingEditorWarmup !== null) {
                const typing = root.pendingEditorWarmup;
                root.pendingEditorWarmup = null;
                SidebarChat.prepareForInput(typing);
            }
            if (!root.checkStandbyMemory) return;
            root.checkStandbyMemory = false;
            const model = Ai.models[root.standbyModel];
            const available = Number(text().match(/MemAvailable:\s+(\d+)/)?.[1] ?? 0) * 1024;
            if (model?.size > 0) {
                const needed = model.size + Math.max(2147483648, model.size / 4);
                if (available > needed) SidebarChat.prepareForInput();
                else if (root.totalMemoryKiB * 1024 > needed) standbyRetry.restart();
            }
        }
    }
    property bool useGpu: false
    property bool requestedServer: false
    property int attempts: 0
    property string problem: ""
    property string memoryStatus: ""
    property string unloadingModel: ""
    property string unloadEndpoint: ""
    property int checksRemaining: 0
    readonly property bool unloading: unloadingModel.length > 0
    property string preloadKey: ""
    property double preloadUntil: 0
    onAllowGpuChanged: {
        if (!allowGpu && useGpu) {
            if (Ai.nativeGenerating) Ai.stopGeneration();
            stop();
            useGpu = false;
        }
    }
    signal unloaded(bool success)
    readonly property bool preparing: pending.length > 0
    readonly property bool preparingChat: pending.some(entry => entry.owner === "chat")
    function prepare(callback, owner = "chat", gpu = Config.options.ai.localGpu ?? true) {
        const nextGpu = gpu && allowGpu;
        if (owner !== "preload" && preloadKey && nextGpu !== useGpu) cancelPreload();
        if (preparing && nextGpu !== useGpu) {
            callback(false);
            return;
        }
        idle.stop();
        pending = [...pending, {owner, callback}];
        if (pending.length > 1) return;
        attempts = 0; requestedServer = false; problem = ""; memoryStatus = "";
        if (nextGpu !== useGpu && server.running) server.running = false;
        useGpu = nextGpu;
        probe.running = true;
    }
    function finish(ok) {
        retry.stop();
        const waiting = pending;
        pending = [];
        if (ok) users = [...new Set([...users, ...waiting.map(entry => entry.owner)])];
        for (const entry of waiting) entry.callback(ok);
        if (!users.length && !preparing) idle.restart();
    }
    function release(owner = "chat") {
        users = users.filter(user => user !== owner);
        if (!users.length && !preparing) idle.restart();
    }
    function cancel(owner = "chat") {
        pending = pending.filter(entry => entry.owner !== owner);
        if (!preparing) { retry.stop(); probe.running = false; }
        if (owner === "chat") cancelUnload();
        release(owner);
    }
    // Reuse the runner and its common prompt prefix without sending the draft or history.
    function preload(model, endpoint, gpu, options, assistant = false) {
        if (!model || /(?:^|[:/\-])cloud(?:$|[:/\-])/i.test(model) || idleSeconds === 0
                || GlobalStates.screenLocked || Config.options.policies.ai === 0 || unloading) return;
        const base = endpointFor(endpoint, gpu).replace(/\/(?:v1\/chat\/completions|api\/chat)\/?$/, "").replace(/\/$/, "");
        if (!/^http:\/\/(?:localhost|127\.0\.0\.1|\[::1\]):1143[45]$/i.test(base)) return;
        const key = JSON.stringify([base, model, options, assistant]);
        if (preloadKey === key && (Date.now() < preloadUntil || pending.some(entry => entry.owner === "preload")
                || users.includes("preload"))) return;
        if (pending.some(entry => entry.owner !== "preload") || users.some(owner => owner !== "preload")) return;
        cancelPreload();
        preloadKey = key;
        preloadUntil = Date.now() + Math.min(120, idleSeconds) * 1000;
        prepare(ok => {
            if (!ok || preloadKey !== key) return;
            if (SidebarChat.busy) { preloadUntil = 0; release("preload"); return; }
            preloadRequest.key = key;
            preloadRequest.base = base;
            preloadRequest.body = {model, options, keep_alive:idleSeconds, stream:false};
            preloadModelInfo.assistant = assistant;
            // A local Ollama server can also list aliases backed by a cloud provider.
            preloadModelInfo.key = key;
            preloadModelInfo.command = ["curl", "--noproxy", "*", "--silent", "--fail", "--max-time", "3",
                "-H", "Content-Type: application/json", "--data-binary", JSON.stringify({model}), base + "/api/show"];
            preloadModelInfo.running = true;
        }, "preload", base.endsWith(":11434"));
    }
    function cancelPreload() {
        if (!preloadKey) return;
        preloadKey = "";
        preloadUntil = 0;
        preloadModelInfo.running = false;
        prefixReader.running = false;
        preloadRequest.running = false;
        cancel("preload");
    }
    Process {
        id: preloadModelInfo
        property string key: ""
        property bool assistant: false
        stdout: StdioCollector { id: preloadInfo }
        onExited: code => {
            if (key !== root.preloadKey) return;
            if (SidebarChat.busy) root.preloadUntil = 0;
            else if (code === 0 && !GlobalStates.screenLocked && Config.options.policies.ai !== 0) {
                try {
                    const info = JSON.parse(preloadInfo.text);
                    if (info.capabilities?.includes("completion") && !info.remote_model && !info.remote_host) {
                        if (assistant && info.capabilities.includes("tools")) {
                            prefixReader.key = key;
                            prefixReader.running = true;
                        } else preloadRequest.startWarmup(null);
                        return;
                    }
                } catch (_) {}
            }
            root.release("preload");
        }
    }
    Process {
        id: prefixReader
        property string key: ""
        stdinEnabled: false
        command: ["timeout", "2", Quickshell.shellPath("scripts/agent-service"), "--warmup-prefix"]
        stdout: StdioCollector { id: prefixOutput }
        onExited: code => {
            if (key !== root.preloadKey) return;
            if (GlobalStates.screenLocked || Config.options.policies.ai === 0 || SidebarChat.busy) {
                root.preloadUntil = 0; root.release("preload"); return;
            }
            let prefix = null;
            if (code === 0) {
                try {
                    const data = JSON.parse(prefixOutput.text);
                    if (Array.isArray(data.messages) && Array.isArray(data.tools)) prefix = data;
                } catch (_) {}
            }
            preloadRequest.startWarmup(prefix);
        }
    }
    Process {
        id: preloadRequest
        property string key: ""
        property string base: ""
        property var body: ({})
        function startWarmup(prefix) {
            const request = Object.assign({}, body, prefix ?? {});
            if (prefix) {
                request.think = false;
                request.options = Object.assign({}, body.options, {num_predict:1, temperature:0.1});
            }
            command = ["curl", "--noproxy", "*", "--silent", "--fail", "--max-time", "120",
                "-H", "Content-Type: application/json", "--data-binary", JSON.stringify(request), base + (prefix ? "/api/chat" : "/api/generate")];
            running = true;
        }
        onExited: code => {
            if (key !== root.preloadKey) return;
            if (code === 0) root.preloadUntil = Date.now() + root.idleSeconds * 1000;
            root.release("preload");
        }
    }
    onIdleSecondsChanged: if (idleSeconds === 0 && preloadKey) cancelPreload()
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (GlobalStates.screenLocked) root.cancelPreload(); }
    }
    Connections {
        target: Config.options.policies
        function onAiChanged() { if (Config.options.policies.ai === 0 && root.preloadKey) root.stop(); }
    }
    function stop() {
        cancelPreload();
        problem = Translation.tr("Ollama isn't running");
        finish(false);
        users = []; probe.running = false; cancelUnload(); server.running = false; idle.stop();
    }
    function unloadModel(model, endpoint) {
        cancelPreload();
        if (!model || users.length || preparing || unloading || Ai.generating || Assistant.queued) return false;
        const base = endpointFor(endpoint || "http://127.0.0.1:11434", (Assistant.enabled ? Config.options.assistant.gpu : Config.options.ai.localGpu) ?? false).replace(/\/(?:v1\/chat\/completions|api\/(?:chat|generate))\/?$/, "").replace(/\/$/, "");
        if (!/^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?$/i.test(base)) {
            memoryStatus = Translation.tr("Memory release is available for a local Ollama server");
            return false;
        }
        unloadingModel = model;
        unloadEndpoint = base;
        checksRemaining = 10;
        memoryStatus = Translation.tr("Releasing model memory…");
        unloadRequest.command = ["curl", "--noproxy", "*", "--silent", "--show-error", "--fail-with-body", "--connect-timeout", "2", "--max-time", "30", "-H", "Content-Type: application/json", "--data-binary", JSON.stringify({model, keep_alive:0, stream:false}), base + "/api/generate"];
        unloadRequest.running = true;
        return true;
    }
    function cancelUnload() {
        unloadingModel = "";
        unloadTimer.stop(); unloadRequest.running = false; loadedModels.running = false;
    }
    function finishUnload(ok, detail) {
        unloadingModel = "";
        memoryStatus = detail;
        unloaded(ok);
    }
    Process {
        id: unloadRequest
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            if (!root.unloading) return;
            if (code === 0) loadedModels.running = true;
            else if (code === 7) root.finishUnload(true, Translation.tr("Local model server is stopped. Your conversation is saved."));
            else root.finishUnload(false, Translation.tr("Could not unload the model. Try again."));
        }
    }
    Timer { id: unloadTimer; interval: 300; onTriggered: loadedModels.running = true }
    Process {
        id: loadedModels
        command: ["curl", "--noproxy", "*", "--silent", "--fail", "--max-time", "2", root.unloadEndpoint + "/api/ps"]
        stdout: StdioCollector { id: modelList }
        onExited: code => {
            if (!root.unloading) return;
            if (code === 7) { root.finishUnload(true, Translation.tr("Local model server is stopped. Your conversation is saved.")); return; }
            try {
                const models = JSON.parse(modelList.text).models;
                const canonical = name => name.split("/").pop().includes(":") ? name : name + ":latest";
                if (code === 0 && Array.isArray(models) && !models.some(m => canonical(m.name || m.model) === canonical(root.unloadingModel))) {
                    root.finishUnload(true, Translation.tr("Model unloaded. Your conversation is saved."));
                    return;
                }
            } catch (_) {}
            if (--root.checksRemaining > 0) unloadTimer.restart();
            else root.finishUnload(false, Translation.tr("Could not verify that the model was unloaded."));
        }
    }
    Timer { id: retry; interval: 400; onTriggered: probe.running = true }
    Timer {
        id: idle
        interval: Math.max(1, root.idleSeconds * 1000)
        onTriggered: if (!Assistant.busy && !Assistant.preparingSubmission && !Assistant.queued) server.running = false
    }
    Connections {
        target: Assistant
        function onTaskFinished() { if (server.running && !root.users.length && !root.preparing) idle.restart(); }
    }
    Process {
        id: probe
        command: ["curl", "--noproxy", "*", "--silent", "--fail", "--connect-timeout", "1", "--max-time", "1", (root.useGpu ? "http://127.0.0.1:11434" : "http://127.0.0.1:11435") + "/api/version"]
        stdout: SplitParser { onRead: _ => {} }
        stderr: SplitParser { onRead: _ => {} }
        onExited: (code, status) => {
            if (!root.preparing) return;
            if (code === 0) { root.finish(true); return; }
            if (++root.attempts > 100) { root.problem = Translation.tr("Ollama did not become ready. Check the local service and try again."); root.finish(false); return; }
            if (!server.running && !root.requestedServer) { root.requestedServer = true; server.running = true; }
            retry.restart();
        }
    }
    Process {
        id: server
        command: [Quickshell.shellPath("scripts/helper"), "local-ollama", root.useGpu ? "gpu" : "cpu"]
        onExited: (code, status) => {
            if (root.preparing && code === 127) { root.problem = Translation.tr("Ollama is not installed or is not in PATH"); root.finish(false); }
            // Another server can win the port while ours starts. Keep probing it.
        }
    }
}
