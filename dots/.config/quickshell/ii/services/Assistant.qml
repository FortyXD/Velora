pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import "IntentRouter.js" as IntentRouter

Singleton {
    id: root
    property bool mainShell: false
    readonly property bool enabled: Config.ready && (Config.options.assistant?.enabled ?? false) && Config.options.policies.ai !== 0
    property bool actionSession: false
    readonly property bool available: Config.ready && (enabled || actionSession) && Config.options.policies.ai !== 0
    property bool preparingSubmission: false
    property int submissionGeneration: 0
    property string submissionId: ""
    property string conversationId: ""
    property string requestIntent: "chat"
    property var transactions: ({})
    property bool transactionRefreshPending: false
    readonly property int aiPolicy: Config.options.policies.ai
    onAiPolicyChanged: {
        if (busy || queued !== null || preparingSubmission) cancel();
        if (ready) configure();
    }
    property bool ready: false
    property bool busy: false
    property bool cancelling: false
    property bool panelOpen: false
    property bool extended: false
    property bool useStrong: false
    property int task: 0
    property int nextId: 1
    property var queued: null
    readonly property bool thinking: available && (busy || preparingSubmission || queued !== null) && approval === null && !GlobalStates.screenLocked
    property var messages: []
    property var completedSteps: []
    property var choices: []
    property string streaming: ""
    property string problem: ""
    property string currentAction: ""
    property var approval: null
    readonly property bool approvalReviewComplete: !Array.isArray(approval?.details?.diff)
        || !boundedApprovalText(approvalInventory(approval.details.diff), 30000).truncated
    property var download: ({})
    property var selectedPaths: []
    property var pending: ({})
    property string lastAppliedPreset: ""
    property bool updatingCapability: false
    property string surfaceToken: ""
    property string origin: "launcher"
    property var pendingHistory: null
    property bool restoring: false
    property bool sessionValid: false
    property int contextGeneration: 0
    signal answer(string text)
    signal token(string text)
    signal taskFinished()
    signal submitted(string text, string surface)
    signal taskEvent(var event)
    signal transactionChanged(var transaction)

    readonly property var profile: ({
        provider: Config.options.assistant?.provider ?? "ollama",
        endpoint: Config.options.assistant?.endpoint ?? "http://127.0.0.1:11434",
        model: Config.options.assistant?.model ?? "",
        strong_model: Config.options.assistant?.strongModel ?? "",
        key: KeyringStorage.keyringData?.apiKeys?.[Config.options.assistant?.keyId ?? "veloraAssistant"] ?? "",
        vision: Config.options.assistant?.vision ?? false,
        gpu: Config.options.assistant?.gpu ?? false,
        context_tokens: Config.options.assistant?.contextTokens ?? 4096
    })
    onProfileChanged: {
        if (updatingCapability) return;
        if (busy || queued !== null || preparingSubmission) cancel();
        if (ready) configure();
        Qt.callLater(root.chooseInstalledDefault);
    }
    onEnabledChanged: if (!enabled) {
        cancel(); process.running = false; panelOpen = false; messages = []; completedSteps = []; choices = []; selectedPaths = [];
    }
    onBusyChanged: if (mainShell) Lens.assistantBusy = busy

    function chooseInstalledDefault() {
        if (!Config.ready || !Ai.localModelsLoaded || busy || queued !== null) return;
        const options = Config.options.assistant;
        if (!options || (options.model ?? "").trim() || (options.provider ?? "ollama") !== "ollama") return;
        const endpoint = (options.endpoint ?? "http://127.0.0.1:11434").replace(/\/+$/, "");
        if (!["http://127.0.0.1:11434", "http://localhost:11434"].includes(endpoint)) return;
        const model = Ai.models[Ai.defaultLocalModelId];
        if (model) { options.model = model.model; options.vision = false; }
    }
    Component.onCompleted: Qt.callLater(root.chooseInstalledDefault)
    Connections {
        target: Config
        function onReadyChanged() { root.chooseInstalledDefault(); }
    }
    Connections {
        target: Ai
        function onLocalModelsLoadedChanged() { root.chooseInstalledDefault(); }
        function onInstalledModelIdsChanged() { root.chooseInstalledDefault(); }
    }

    function call(method, params, callback) {
        if (!ready) return 0;
        const id = nextId++;
        pending[id] = {callback, generation:contextGeneration};
        process.write(JSON.stringify({id, method, params: params ?? {}}) + "\n");
        return id;
    }
    function configure(callback) {
        call("configure", {
            locked: GlobalStates.screenLocked, on_battery: PowerSaving.onBattery, shell_ui: true,
            policy: Config.options.policies.ai, profile: root.profile,
            rollback_budget_bytes: Config.options.assistant?.rollbackBudgetBytes ?? 2147483648,
            apps: AppSearch.list.map(a => ({id:a.id, name:a.name, class:a.startupClass ?? ""})),
            presets: Presets.presets.map(p => ({id:p.id, name:p.name})), selection: selectedPaths
        }, callback);
    }
    function start(method, params) {
        if (!available || GlobalStates.screenLocked || busy || queued !== null || preparingSubmission) return;
        LocalAiRuntime.memoryStatus = "";
        problem = ""; streaming = ""; approval = null; download = ({}); completedSteps = []; choices = []; panelOpen = method === "submit" || panelOpen;
        queued = {method, params};
        if (ready) configure(ok => { if (ok) flush(); else { queued = null; taskFinished(); } });
        else process.running = true;
    }
    function flush() {
        if (!queued || busy || !ready || restoring) return;
        if (pendingHistory !== null) {
            restoring = true;
            const generation = contextGeneration;
            call("restore", {messages:pendingHistory}, ok => {
                if (generation !== contextGeneration) return;
                restoring = false;
                if (!ok) { queued = null; taskFinished(); return; }
                pendingHistory = null;
                sessionValid = true;
                call("selection", {paths:selectedPaths}, selected => {
                    if (generation !== contextGeneration) return;
                    if (selected) flush(); else { queued = null; taskFinished(); }
                });
            });
            return;
        }
        const request = queued; queued = null;
        busy = true;
        task = call(request.method, request.params, ok => {
            if (!ok) { busy = false; taskFinished(); }
            else if (request.method === "rollback" || request.method === "delete_checkpoint") {
                updateTransaction(ok); busy = false; currentAction = ""; taskFinished();
            }
        });
    }
    function submit(text, displayText, surface, intent, continuation) {
        if (!enabled) return false;
        const kind = IntentRouter.classify(text, intent).kind;
        return prepareSubmission(text, displayText, surface, null, kind === "action" ? "action" : "chat", continuation === true);
    }
    function submitFollowUp(text, displayText, surface) {
        return submit(text, displayText, surface ?? origin, undefined, true);
    }
    function submitChoice(value, label, surface) {
        return submit(value, label, surface ?? origin, requestIntent, true);
    }
    function submitTool(name, args, displayText, surface) {
        if (name !== "terminal_run" || !Config.ready || Config.options.policies.ai === 0) {
            problem = Translation.tr("This action is not allowed"); return false;
        }
        actionSession = true;
        return prepareSubmission(displayText || args.command || name, displayText, surface, {name, arguments:args}, "action");
    }
    function prepareSubmission(text, displayText, surface, tool, intent, continuation) {
        if (!text.trim() || busy || queued || preparingSubmission || !available || GlobalStates.screenLocked) return false;
        preparingSubmission = true;
        const generation = ++submissionGeneration;
        submissionId = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 14);
        origin = surface ?? "launcher";
        const request = {text, displayText:displayText ?? text, surface:origin, submissionId, tool,
            continuation:continuation === true, paths:selectedPaths.slice()};
        requestIntent = intent === "action" ? "action" : "chat";
        SidebarChat.prepareAssistantSubmission(request, (prepared, error) => {
            if (generation !== submissionGeneration || GlobalStates.screenLocked) return;
            preparingSubmission = false;
            if (!prepared) { problem = error || Translation.tr("Save the conversation before starting the task"); taskFinished(); reveal(); return; }
            // A live conversation carries clarification references and tool results.
            // Restore inert history only after switching chats or reconnecting.
            if (conversationId !== prepared.conversationId || pendingHistory !== null || !sessionValid)
                restoreConversation(prepared.history);
            conversationId = prepared.conversationId;
            // Restoring history deliberately clears permissions and selections. The
            // files explicitly supplied with this new request remain selected.
            selectedPaths = request.paths;
            messages = messages.concat([{role:"user", text:request.displayText}]).slice(-60);
            submitted(request.displayText, request.surface);
            const params = {text, extended, strong:useStrong, submission_id:request.submissionId, conversation_id:conversationId};
            if (tool) params.tool = tool;
            if (intent) params.intent = intent;
            start("submit", params);
        });
        return true;
    }
    function updateTransaction(value) {
        const id = value?.transaction_id;
        if (!id) return;
        transactions = Object.assign({}, transactions, {[id]:value});
        transactionChanged(value);
    }
    function refreshTransactions() {
        if (GlobalStates.screenLocked) return;
        actionSession = true;
        if (!available) return;
        if (!ready) { transactionRefreshPending = true; process.running = true; return; }
        transactionRefreshPending = false;
        call("transactions", {}, value => {
            if (!value || GlobalStates.screenLocked) return;
            const entries = Array.isArray(value) ? value : value.transactions ?? [];
            entries.forEach(updateTransaction);
        });
    }
    function rollback(transactionId) {
        if (!transactionId || busy || queued || preparingSubmission || GlobalStates.screenLocked) return false;
        actionSession = true; origin = "sidebar";
        if (!available) return false;
        start("rollback", {transaction_id:transactionId});
        return true;
    }
    function deleteCheckpoint(transactionId) {
        if (!transactionId || busy || queued || preparingSubmission || GlobalStates.screenLocked) return false;
        actionSession = true;
        if (!available) return false;
        start("delete_checkpoint", {transaction_id:transactionId, confirmed:true});
        return true;
    }
    function restoreConversation(entries) {
        if (busy || queued || GlobalStates.screenLocked) return false;
        contextGeneration++;
        sessionValid = false;
        messages = entries.filter(m => m.role === "user" || m.role === "assistant").map(m => ({role:m.role, text:m.text}));
        // Bound the protocol payload as well as the model's own context budget.
        let bytes = 0;
        pendingHistory = messages.slice(-60).reverse().filter(m => { bytes += m.text.length * 4; return bytes < 480000; }).reverse().map(m => ({role:m.role, content:m.text}));
        selectedPaths = []; choices = []; approval = null; streaming = ""; completedSteps = [];
        return true;
    }
    function checkModel() { start("probe", {strong:useStrong}); }
    function downloadModel() { start("pull", {strong:useStrong}); }
    function retainStreaming() {
        if (streaming && !GlobalStates.screenLocked)
            messages = messages.concat([{role:"assistant",text:streaming}]).slice(-60);
        streaming = "";
    }
    function cancel() {
        const recovering = busy && ready && task !== 0;
        if (busy || queued || preparingSubmission) taskEvent({type:"cancelled", submission_id:submissionId, conversation_id:conversationId});
        submissionGeneration++; preparingSubmission = false;
        surfaceDelay.stop(); surfaceToken = ""; choices = [];
        contextGeneration++; restoring = false;
        sessionValid = false;
        queued = null;
        if (ready) call("cancel", {});
        approval = null; retainStreaming();
        if (recovering) { cancelling = true; currentAction = Translation.tr("Stopping the task and restoring changes…"); return; }
        cancelling = false; busy = false; task = 0; currentAction = ""; taskFinished();
    }
    function reset() {
        cancel(); messages = []; completedSteps = []; choices = []; selectedPaths = []; problem = "";
        pendingHistory = null; submissionId = ""; conversationId = "";
        if (ready) { call("reset", {}); configure(); }
    }
    function decide(allow) {
        if (!approval || !ready || !available || GlobalStates.screenLocked || (allow && !approvalReviewComplete)) return;
        call("approve", {task, approval:approval.approval, allow}); approval = null;
    }
    function select(paths, surface) {
        if (!enabled) { problem = Translation.tr("Enable the assistant in AI settings first"); return; }
        if (busy) return;
        selectedPaths = paths;
        origin = surface ?? "launcher";
        panelOpen = true;
        if (origin === "sidebar") GlobalStates.sidebarLeftOpen = true;
        else if (Config.options.panelFamily === "waffle") GlobalStates.searchOpen = true;
        else GlobalStates.overviewOpen = true;
        if (ready) call("selection", {paths});
    }
    function reveal() {
        if (!mainShell || GlobalStates.screenLocked) return;
        panelOpen = true;
        if (origin === "sidebar") GlobalStates.sidebarLeftOpen = true;
        else if (Config.options.panelFamily === "waffle") GlobalStates.searchOpen = true;
        else GlobalStates.overviewOpen = true;
    }
    function actionLabel(tool) {
        if (tool === "terminal_apply") return Translation.tr("Apply command changes");
        if (tool === "files_trash") return Translation.tr("Delete with a recovery checkpoint");
        const labels = {search:"Searching files",files_choose:"Choose files",files_read:"Reading a file",files_open:"Opening a file",files_zip:"Creating an archive",files_mkdir:"Creating a folder",files_copy:"Copying files",files_move:"Moving files",files_trash:"Moving to trash",apps_list:"Checking applications",app_open:"Opening an application",workspace_focus:"Switching workspace",window_move:"Moving a window",preset_apply:"Applying a preset",terminal_run:"Run a terminal command",ui_inspect:"Inspecting the application",ui_action:"Activate an application control",ui_screenshot:"Reading the screen",ui_click:"Click in the application",ui_type:"Type in the application",ui_key:"Send a key to the application",ui_scroll:"Scroll the application",remote_context:"Use the remote model"};
        return Translation.tr(labels[tool] ?? "Working");
    }
    function boundedApprovalText(text, limit) {
        let bytes = 0;
        let end = 0;
        for (const character of String(text)) {
            const code = character.codePointAt(0);
            const size = code < 128 ? 1 : code < 2048 ? 2 : code < 65536 ? 3 : 4;
            if (bytes + size > limit) return {text:String(text).slice(0, end), truncated:true};
            bytes += size; end += character.length;
        }
        return {text:String(text), truncated:false};
    }
    function approvalInventory(changes) {
        return changes.map(change => {
            let text = String(change.path ?? "") + " · " + String(change.change ?? "");
            if (change.before_bytes !== undefined || change.after_bytes !== undefined)
                text += "\n" + Translation.tr("Bytes: %1 → %2").arg(change.before_bytes ?? 0).arg(change.after_bytes ?? 0);
            return text;
        }).join("\n\n");
    }
    function approvalDescription() {
        const a = approval;
        if (!a) return "";
        const d = a.details ?? {};
        if (a.tool === "remote_context") return Translation.tr("This task will send the conversation and necessary file excerpts or screenshots to %1.").arg(d.endpoint);
        if (a.tool === "terminal_run") return d.command + "\n" + Translation.tr("Folder: %1 · Network: %2").arg(d.cwd).arg(d.network ? Translation.tr("On") : Translation.tr("Off"));
        if (Array.isArray(d.diff)) {
            const title = a.tool === "files_trash"
                ? Translation.tr("Delete these paths and retain a checkpoint for recovery?")
                : Translation.tr("Review these file changes:");
            const inventory = boundedApprovalText(approvalInventory(d.diff), 30000);
            if (inventory.truncated) return title + "\n" + Translation.tr("Too many paths to review safely. Split this task into smaller changes.") + "\n" + inventory.text;
            const previews = d.diff.filter(change => change.diff || change.preview || change.truncated).map(change => {
                let text = String(change.path ?? "") + "\n" + (change.diff || change.preview || "");
                if (change.truncated) text += "\n" + Translation.tr("Text preview truncated");
                return text;
            }).join("\n\n");
            const content = title + "\n" + Translation.tr("Paths: %1").arg(d.diff.length) + "\n\n" + inventory.text + (previews ? "\n\n" + previews : "");
            const bounded = boundedApprovalText(content, 32500);
            return bounded.text + (bounded.truncated ? "\n" + Translation.tr("Text preview truncated; all affected paths are listed above.") : "");
        }
        if (a.tool === "ui_type") return d.text;
        if (a.tool === "ui_key") return d.key;
        if (a.tool === "ui_click") return (d.window_title ?? "") + "\n" + Translation.tr("Position: %1, %2").arg(d.x).arg(d.y);
        if (a.tool === "ui_action") return (d.window_title ?? "") + "\n" + (d.control?.name ?? d.node);
        const visible = Object.assign({}, d); delete visible.preview; return JSON.stringify(visible);
    }
    function handle(line) {
        let m; try { m = JSON.parse(line); } catch (_) { return; }
        if (m.type === "hello") {
            if (m.protocol !== 3) { ready = false; queued = null; problem = Translation.tr("Update the assistant and shell together"); process.running = false; taskFinished(); return; }
            ready = true; configure(ok => { if (ok) { flush(); if (transactionRefreshPending) refreshTransactions(); } else { queued = null; taskFinished(); } }); return;
        }
        if (m.type === "unavailable") { problem = Translation.tr("Install Velora native tools to enable the assistant"); return; }
        if (m.type === "response") {
            const request = pending[m.id]; delete pending[m.id];
            if (!request || request.generation !== contextGeneration) return;
            if (!m.ok) problem = m.error ?? Translation.tr("Assistant request failed");
            if (request.callback) request.callback(m.ok ? m.result : null);
            return;
        }
        if (GlobalStates.screenLocked) return;
        if (m.type === "transaction") { updateTransaction(m); return; }
        if (m.task !== task || (m.submission_id && m.submission_id !== submissionId) || (m.conversation_id && m.conversation_id !== conversationId)) return;
        if (cancelling && !["finished", "cancelled", "error"].includes(m.type)) return;
        taskEvent(m);
        if (m.type === "prepare_ui") {
            panelOpen = false; GlobalStates.overviewOpen = false; GlobalStates.searchOpen = false;
            GlobalStates.sidebarLeftOpen = false;
            surfaceToken = m.token; surfaceDelay.restart();
        }
        else if (m.type === "phase") {
            const labels = {starting:"Starting the assistant…", loading:"Loading the model…", generating:"Generating response…"};
            if (labels[m.phase]) currentAction = Translation.tr(labels[m.phase]);
        }
        else if (m.type === "delta") { streaming += m.text; token(m.text); }
        else if (m.type === "answer") {
            messages = messages.concat([{role:"assistant",text:m.text}]).slice(-60); streaming = ""; answer(m.text);
        } else if (m.type === "approval") { approval = m; reveal(); }
        else if (m.type === "clarification") { choices = m.choices ?? []; reveal(); }
        else if (m.type === "step") {
            currentAction = actionLabel(m.tool);
            if (m.state === "done") completedSteps = completedSteps.concat([{label:currentAction, result:m.result}]).slice(-20);
            if (m.state === "running" && (m.tool.startsWith("ui_") || m.tool === "files_choose")) {
                panelOpen = false; GlobalStates.overviewOpen = false; GlobalStates.searchOpen = false;
            }
        } else if (m.type === "download") download = m;
        else if (m.type === "capabilities") { updatingCapability = true; Config.options.assistant.vision = m.result.vision === true; updatingCapability = false; problem = Translation.tr("Model is ready"); }
        else if (m.type === "error") {
            retainStreaming(); problem = m.message; reveal();
        }
        else if (m.type === "finished" || m.type === "cancelled") {
            const selectionCancelled = m.type === "cancelled" && m.reason === "selection_cancelled";
            if (selectionCancelled) {
                const text = (streaming ? streaming + "\n\n" : "") + Translation.tr("File selection cancelled.");
                messages = messages.concat([{role:"assistant",text}]).slice(-60);
                streaming = ""; answer(text);
            }
            cancelling = false; busy = false; task = 0; approval = null; currentAction = ""; taskFinished();
            if (origin === "sidebar" || selectionCancelled) reveal();
        }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) { cancel(); messages = []; completedSteps = []; choices = []; selectedPaths = []; pendingHistory = null; transactions = ({}); transactionRefreshPending = false; panelOpen = false; process.running = false; }
        }
    }
    Connections {
        target: PowerSaving
        function onOnBatteryChanged() {
            if (PowerSaving.onBattery && busy && profile.gpu) cancel();
            if (ready) call("context", {locked:GlobalStates.screenLocked,on_battery:PowerSaving.onBattery});
        }
    }
    Connections {
        target: Presets
        function onApplied(id) { root.lastAppliedPreset = id; }
    }
    IpcHandler {
        id: assistantIpc
        target: "assistant"
        function stop(): void { root.cancel(); }
        function select(paths: string): void { try { const values = JSON.parse(paths); if (Array.isArray(values)) root.select(values.filter(p => typeof p === "string")); } catch (_) {} }
        function applyPreset(id: string): string {
            // Preset writes lack a transactional adapter. Legacy IPC cannot bypass policy.
            return "rejected";
        }
        function presetStatus(id: string): string { return root.lastAppliedPreset === id ? "applied" : "pending"; }
    }
    Timer {
        id: surfaceDelay
        interval: 200
        onTriggered: {
            if (root.busy && root.ready && root.surfaceToken && !GlobalStates.screenLocked)
                root.call("surface_ready", {task:root.task, token:root.surfaceToken});
            root.surfaceToken = "";
        }
    }
    Process {
        id: process
        stdinEnabled: true
        command: [Quickshell.shellPath("scripts/agent-service")]
        stdout: SplitParser { onRead: line => root.handle(line) }
        onExited: (code, status) => {
            const interrupted = root.busy || root.queued !== null;
            root.retainStreaming();
            surfaceDelay.stop(); root.surfaceToken = ""; root.choices = [];
            root.ready = false; root.busy = false; root.cancelling = false; root.pending = ({}); root.approval = null;
            root.restoring = false; root.sessionValid = false;
            root.queued = null; root.task = 0; root.currentAction = "";
            if ((code !== 0 || interrupted) && root.available && !GlobalStates.screenLocked && !root.problem) root.problem = Translation.tr("The assistant stopped. Send your request again to reconnect.");
            root.taskFinished();
        }
    }
}
