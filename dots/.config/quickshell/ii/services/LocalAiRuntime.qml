pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root
    property var completion: null
    property bool useGpu: false
    property bool requestedServer: false
    property int attempts: 0
    property string problem: ""
    property string memoryStatus: ""
    readonly property bool unloading: unloadRequest.running
    signal unloaded(bool success)
    readonly property bool preparing: completion !== null
    function prepare(callback) {
        idle.stop(); attempts = 0; requestedServer = false; problem = ""; memoryStatus = "";
        useGpu = (Config.options.ai.localGpu ?? true) && !PowerSaving.onBattery;
        completion = callback; probe.running = true;
    }
    function finish(ok) {
        retry.stop();
        const callback = completion; completion = null;
        if (callback) callback(ok);
        if (!ok) idle.restart();
    }
    function cancel() { completion = null; retry.stop(); probe.running = false; unloadRequest.running = false; idle.restart(); }
    function release() { idle.restart(); }
    function stop() { cancel(); server.running = false; idle.stop(); }
    function unloadModel(model, endpoint) {
        if (!model || preparing || unloading || Ai.generating || Assistant.queued) return false;
        const base = (endpoint || "http://127.0.0.1:11434").replace(/\/(?:v1\/chat\/completions|api\/(?:chat|generate))\/?$/, "").replace(/\/$/, "");
        if (!/^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?$/i.test(base)) {
            memoryStatus = Translation.tr("Memory release is available for a local Ollama server");
            return false;
        }
        memoryStatus = Translation.tr("Releasing model memory…");
        unloadRequest.command = ["curl", "--noproxy", "*", "--silent", "--show-error", "--fail-with-body", "--connect-timeout", "2", "--max-time", "30", "-H", "Content-Type: application/json", "--data-binary", JSON.stringify({model, keep_alive:0, stream:false}), base + "/api/generate"];
        unloadRequest.running = true;
        return true;
    }
    Process {
        id: unloadRequest
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (code, status) => {
            const success = code === 0 || code === 7;
            root.memoryStatus = success ? Translation.tr("Model unloaded. Memory is free; your conversation is saved.") : Translation.tr("Could not unload the model. Try again.");
            root.unloaded(success);
        }
    }
    Timer { id: retry; interval: 400; onTriggered: probe.running = true }
    Timer { id: idle; interval: PowerSaving.onBattery ? 60000 : 300000; onTriggered: server.running = false }
    Process {
        id: probe
        command: ["curl", "--noproxy", "*", "--silent", "--fail", "--connect-timeout", "1", "--max-time", "1", "http://127.0.0.1:11434/api/version"]
        stdout: SplitParser { onRead: _ => {} }
        stderr: SplitParser { onRead: _ => {} }
        onExited: (code, status) => {
            if (!root.completion) return;
            if (code === 0) { root.finish(true); return; }
            if (++root.attempts > 100) { root.problem = Translation.tr("Ollama did not become ready. Check the local service and try again."); root.finish(false); return; }
            if (!server.running && !root.requestedServer) { root.requestedServer = true; server.running = true; }
            retry.restart();
        }
    }
    Process {
        id: server
        command: ["python3", Quickshell.shellPath("scripts/ai/local-ollama.py"), root.useGpu ? "gpu" : "cpu"]
        onExited: (code, status) => {
            if (root.completion && code === 127) { root.problem = Translation.tr("Ollama is not installed or is not in PATH"); root.finish(false); }
            // Another server can win the port while ours starts. Keep probing it.
        }
    }
}
