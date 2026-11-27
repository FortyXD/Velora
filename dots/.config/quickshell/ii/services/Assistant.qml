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
    readonly property bool allowFiles: Config.options.assistant?.allowFileAccess ?? true
    readonly property bool autoLocalSearch: Config.options.assistant?.autoLocalSearch ?? true
    onAutoLocalSearchChanged: if (!autoLocalSearch && (busy || queued || preparingSubmission)) cancel();
    readonly property bool allowCommands: Config.options.assistant?.allowCommands ?? true
    onAllowFilesChanged: if (!allowFiles) {
        if (busy || queued || preparingSubmission) cancel();
        selectedPaths = []; fileMode = false;
    }
    onAllowCommandsChanged: if (!allowCommands && (busy || queued || preparingSubmission)) cancel()
    property bool actionSession: false
    property bool fileMode: false
    readonly property var fileModel: Ai.currentModelIsLocal ? Ai.getModel() : Ai.models[Ai.defaultLocalModelId]
    readonly property bool available: Config.ready && (enabled || actionSession || fileMode || maintenance) && Config.options.policies.ai !== 0
    property bool maintenance: false
    property string downloadName: ""
    function rememberDownload(state) {
        if (!downloadName) return;
        const attempts = Object.assign({}, Config.options.assistant.downloadAttempts ?? {});
        if (state) attempts["model:" + downloadName] = state;
        else delete attempts["model:" + downloadName];
        Config.options.assistant.downloadAttempts = attempts;
    }
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
    property string runningProgram: ""
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
    onTaskFinished: { maintenance = false; downloadName = ""; }
    signal submitted(string text, string surface)
    signal taskEvent(var event)
    signal transactionChanged(var transaction)

    readonly property var profile: fileMode ? {
        provider: "ollama", endpoint: LocalAiRuntime.endpointFor(fileModel?.endpoint ?? "http://127.0.0.1:11434", Config.options.ai?.localGpu ?? true).replace(/\/(?:v1\/chat\/completions|api\/chat)\/?$/, ""),
        model: fileModel?.model ?? "", strong_model: "", key: "", vision: false,
        gpu: (Config.options.ai?.localGpu ?? true) && LocalAiRuntime.allowGpu, context_tokens: LocalAiRuntime.contextTokens
    } : ({
        provider: Config.options.assistant?.provider ?? "ollama",
        endpoint: (Config.options.assistant?.provider ?? "ollama") === "ollama" ? LocalAiRuntime.endpointFor(Config.options.assistant?.endpoint ?? "http://127.0.0.1:11434", Config.options.assistant?.gpu ?? false) : Config.options.assistant.endpoint,
        model: Config.options.assistant?.model ?? "",
        strong_model: Config.options.assistant?.strongModel ?? "",
        key: KeyringStorage.keyringData?.apiKeys?.[Config.options.assistant?.keyId ?? "veloraAssistant"] ?? "",
        vision: Config.options.assistant?.vision ?? false,
        gpu: (Config.options.assistant?.gpu ?? false) && LocalAiRuntime.allowGpu,
        context_tokens: LocalAiRuntime.contextTokens
    })
    onProfileChanged: {
        if (updatingCapability) return;
        if (busy || queued !== null || preparingSubmission) cancel();
        if (ready) configure();
        Qt.callLater(root.chooseInstalledDefault);
    }
    onEnabledChanged: {
        fileMode = false;
        if (!enabled) {
            cancel(); process.running = false; panelOpen = false; messages = []; completedSteps = []; choices = []; selectedPaths = [];
        }
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
            policy: Config.options.policies.ai,
            profile: (Config.options.ai?.modelIdleSeconds ?? -1) < 0 ? root.profile
                : Object.assign({}, root.profile, {idle_seconds: Math.min(86400, Config.options.ai.modelIdleSeconds)}),
            rollback_budget_bytes: Config.options.assistant?.rollbackBudgetBytes ?? 2147483648,
            apps: AppSearch.list.map(a => ({id:a.id, name:a.name, class:a.startupClass ?? ""})),
            presets: Presets.presets.map(p => ({id:p.id, name:p.name})), selection: selectedPaths,
            auto_local_search: autoLocalSearch,
            trusted_read_folders: Config.options.assistant?.trustedReadFolders ?? []
        }, callback);
    }
    function start(method, params) {
        if (!available || GlobalStates.screenLocked || busy || queued !== null || preparingSubmission) return;
        LocalAiRuntime.memoryStatus = "";
        problem = ""; streaming = ""; approval = null; runningProgram = ""; download = ({}); completedSteps = []; choices = []; if (method === "submit") panelOpen = origin === "launcher";
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
        if (!enabled && !fileMode) return false;
        if (fileMode && enabled && surface === "launcher" && intent && !continuation) {
            if (busy || queued || preparingSubmission) return false;
            fileMode = false;
            selectedPaths = [];
        }
        const kind = fileMode ? "chat" : IntentRouter.classify(text, intent).kind;
        const agent = enabled && !fileMode && (!intent || intent === "auto" || intent === "action");
        return prepareSubmission(text, displayText, surface, null, agent ? "agent" : kind === "action" ? "action" : "chat", continuation === true, agent && kind === "action");
    }
    function submitFollowUp(text, displayText, surface) {
        return submit(text, displayText, surface ?? origin, undefined, true);
    }
    function submitChoice(value, label, surface) {
        return submit(value, label, surface ?? origin, requestIntent, true);
    }
    function submitTool(name, args, displayText, surface) {
        if (name !== "terminal_run" || !allowCommands || (!allowFiles && (args.script_path || args.file || args.cwd)) || !Config.ready || Config.options.policies.ai === 0) {
            problem = Translation.tr("This action is not allowed"); return false;
        }
        actionSession = true;
        return prepareSubmission(displayText || args.command || name, displayText, surface, {name, arguments:args}, "action");
    }
    function prepareSubmission(text, displayText, surface, tool, intent, continuation, requireAction = false) {
        if (!text.trim() || busy || queued || preparingSubmission || !available || GlobalStates.screenLocked) return false;
        preparingSubmission = true;
        const generation = ++submissionGeneration;
        submissionId = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 14);
        origin = surface ?? "launcher";
        const request = {text, displayText:displayText ?? text, surface:origin, submissionId, tool,
            continuation:continuation === true, paths:selectedPaths.slice()};
        requestIntent = intent === "action" || intent === "agent" ? "action" : "chat";
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
            const params = {text, extended, strong:useStrong, submission_id:request.submissionId, conversation_id:conversationId,
                allow_files:allowFiles, allow_commands:allowCommands};
            if (fileMode && !tool) params.file_context = true;
            if (tool) params.tool = tool;
            if (intent) params.intent = intent === "agent" ? "action" : intent;
            if (intent === "agent") {
                params.desktop_agent = true;
                params.require_action = requireAction;
                params.terminal_command = Config.options.apps?.terminal ?? "";
            }
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
        const history = entries.filter(m => m.role === "user" || m.role === "assistant");
        messages = history.map(m => ({role:m.role, text:m.displayText ?? m.text}));
        // Bound the protocol payload as well as the model's own context budget.
        let bytes = 0;
        pendingHistory = history.slice(-60).reverse().filter(m => { bytes += m.text.length * 4; return bytes < 480000; }).reverse().map(m => ({role:m.role, content:m.text}));
        selectedPaths = []; choices = []; approval = null; streaming = ""; completedSteps = [];
        return true;
    }
    function checkModel() { start("probe", {strong:useStrong}); }
    function downloadModel() {
        if (busy || queued || GlobalStates.screenLocked || Config.options.policies.ai === 0) return;
        maintenance = true;
        downloadName = useStrong && profile.strong_model ? profile.strong_model : profile.model;
        rememberDownload("partial");
        start("pull", {strong:useStrong});
    }
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
        approval = null; runningProgram = ""; retainStreaming();
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
        if (allow && approval.tool === "terminal_run") runningProgram = approvalDescription();
        call("approve", {task, approval:approval.approval, allow}); approval = null;
    }
    function select(paths, surface) {
        if (GlobalStates.screenLocked || !paths.length) return;
        if (!allowFiles) { problem = Translation.tr("File access is disabled in Chat options"); origin = surface ?? "sidebar"; reveal(); return; }
        if (!Config.ready || Config.options.policies.ai === 0) {
            Quickshell.execDetached(["env", "QS_SETTINGS_PAGE=ai", "qs", "-p", Quickshell.shellPath("settings.qml")]);
            return;
        }
        if (SidebarChat.busy) { reveal(); return; }
        if (!enabled) { useStrong = false; fileMode = true; }
        selectedPaths = paths.slice(0, 100);
        origin = surface ?? "launcher";
        if (origin === "sidebar") SidebarChat.attachments = selectedPaths.slice();
        if (fileMode && !fileModel) problem = Translation.tr("Choose a local model in AI settings.");
        reveal();
    }
    function reveal() {
        if (!mainShell || GlobalStates.screenLocked) return;
        panelOpen = origin === "launcher";
        if (origin === "sidebar") GlobalStates.sidebarLeftOpen = true;
        else if (Config.options.panelFamily === "waffle") GlobalStates.searchOpen = true;
        else GlobalStates.overviewOpen = true;
    }
    function stepLabel(event) {
        const item = event.target ?? {};
        const target = item.name || item.app_id || item.path || item.query || item.topic || item.setting || item.language || item.ref || "";
        const workspace = item.workspace ?? item.number ?? event.result?.workspace;
        const parts = [actionLabel(event.tool), target];
        if (workspace != null) parts.push(Translation.tr("Workspace %1").arg(workspace));
        const found = event.result;
        if (found?.total_matching_apps != null) {
            if (found.total_matching_apps === 1 && found.apps?.length === 1) parts.push(found.apps[0].name);
            else if (found.total_matching_apps === 0) parts.push(Translation.tr("No matching applications"));
            else parts.push(Translation.tr("Applications found (%1)").arg(found.total_matching_apps));
            if (found.windows?.length) parts.push(Translation.tr("Matching windows (%1)").arg(found.windows.length));
        } else if (event.tool === "search" && found?.results) {
            parts.push(found.results.length === 1 ? found.results[0].path
                : found.results.length ? Translation.tr("Files found (%1)").arg(found.results.length) : Translation.tr("No matching files"));
        }
        if (event.result?.exit_code != null) parts.push(Translation.tr("Exit code %1").arg(event.result.exit_code));
        return parts.filter((part, index) => part && parts.indexOf(part) === index).join(" · ");
    }
    function stepOutcome(event) {
        if (event.state === "retry") return "retry";
        const result = event.result;
        if (result?.exit_code != null && result.exit_code !== 0) return "failed";
        if ((result?.total_matching_apps === 0 && !result.windows?.length) || (event.tool === "search" && result?.results?.length === 0)) return "empty";
        return "done";
    }
    function actionLabel(tool) {
        const workflow = {task_plan:"Task plan", tools_enable:"Choosing tools", files_list:"Listing folder contents", files_write:"Saving a text file", ui_set_text:"Edit the selected field"};
        if (workflow[tool]) return Translation.tr(workflow[tool]);
        if (tool === "retry") return Translation.tr("Correcting a tool call");
        if (tool === "files_usage") return Translation.tr("Measuring folder size");
        if (tool === "system_status") return Translation.tr("Inspect system status");
        if (tool === "desktop_adjust") return Translation.tr("Adjust desktop setting");
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
        if (a.tool === "search") return Translation.tr("Search indexed documents or look for names in your personal folders: %1").arg(d.query);
        if (a.tool === "files_read" || a.tool === "files_usage" || a.tool === "files_list") return d.path ?? "";
        if (a.tool === "system_status") return Translation.tr("Read system information: %1").arg(Translation.tr(d.topic));
        if (a.tool === "desktop_adjust") return Translation.tr("%1 on %2: %3% → %4%").arg(Translation.tr(d.setting)).arg(d.target).arg(d.before).arg(d.after);
        if (a.tool === "app_open" || a.tool === "window_move" || a.tool === "workspace_focus") {
            const target = [d.name, d.app_id, d.window?.title, d.workspace ? Translation.tr("Workspace %1").arg(d.workspace) : ""].filter(Boolean);
            return target.join(" · ") + "\n" + Translation.tr("This action takes effect on your desktop.");
        }
        if (a.tool === "remote_context") return Translation.tr("This task will send the conversation and necessary file excerpts or screenshots to %1.").arg(d.endpoint);
        if (a.tool === "terminal_run") {
            const folder = d.temporary ? Translation.tr("Temporary folder") + " (" + (d.cwd ?? "/work") + ")" : d.cwd;
            const context = Translation.tr("Folder: %1 · Network: %2").arg(folder).arg(d.network ? Translation.tr("On") : Translation.tr("Off"));
            const interpreter = Array.isArray(d.argv) ? d.argv.join(" ") : d.interpreter ?? "/bin/bash";
            const inputs = (d.inputs ?? []).map(file => file.path + " → " + file.mount);
            return [context, ...inputs, d.file, interpreter, "", d.code ?? d.command].filter(line => line !== undefined && line !== null).join("\n");
        }
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
        if (a.tool === "ui_action" || a.tool === "ui_set_text")
            return [d.window_title, [d.control?.role, d.control?.name || d.control?.id].filter(Boolean).join(" · "),
                a.tool === "ui_action" ? d.action : d.text].join("\n");
        const visible = Object.assign({}, d); delete visible.preview; return JSON.stringify(visible);
    }
    function handle(line) {
        let m; try { m = JSON.parse(line); } catch (_) { return; }
        if (m.type === "hello") {
            if (m.protocol !== 6) { ready = false; queued = null; problem = Translation.tr("Update the assistant and shell together"); process.running = false; taskFinished(); return; }
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
            currentAction = stepLabel(m);
            if (m.state === "done" || m.state === "retry") {
                completedSteps = completedSteps.concat([{label:currentAction, outcome:stepOutcome(m), result:m.result}]).slice(-20);
                if (m.tool === "terminal_run") runningProgram = "";
            }
            if (m.state === "running" && (m.tool.startsWith("ui_") || m.tool === "files_choose")) {
                panelOpen = false; GlobalStates.overviewOpen = false; GlobalStates.searchOpen = false;
            }
        } else if (m.type === "download") download = m;
        else if (m.type === "capabilities") { rememberDownload(""); updatingCapability = true; Config.options.assistant.vision = m.result.vision === true; updatingCapability = false; problem = Translation.tr("Model is ready"); }
        else if (m.type === "error") {
            rememberDownload("failed");
            runningProgram = ""; retainStreaming(); problem = m.message; reveal();
        }
        else if (m.type === "finished" || m.type === "cancelled") {
            const selectionCancelled = m.type === "cancelled" && m.reason === "selection_cancelled";
            if (selectionCancelled) {
                const text = (streaming ? streaming + "\n\n" : "") + Translation.tr("File selection cancelled.");
                messages = messages.concat([{role:"assistant",text}]).slice(-60);
                streaming = ""; answer(text);
            }
            cancelling = false; busy = false; task = 0; approval = null; runningProgram = ""; currentAction = ""; taskFinished();
            if (selectionCancelled) reveal();
        }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) { cancel(); messages = []; completedSteps = []; choices = []; selectedPaths = []; pendingHistory = null; transactions = ({}); transactionRefreshPending = false; panelOpen = false; fileMode = false; process.running = false; }
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
