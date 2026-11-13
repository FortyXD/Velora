pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.services.ai

Singleton {
    id: root
    readonly property string mode: Assistant.enabled ? "assistant" : "chat"
    readonly property bool busy: active || Ai.generating || Ai.requestAfterKeyring || Assistant.busy || Assistant.preparingSubmission || Assistant.queued !== null || LocalAiRuntime.unloading
    readonly property bool compatible: conversationMode === mode
    readonly property string modelName: mode === "assistant" ? (Assistant.useStrong ? Assistant.profile.strong_model : Assistant.profile.model) : (Ai.getModel()?.name ?? Translation.tr("Choose a model"))
    readonly property bool localModel: mode === "assistant" ? Assistant.profile.provider === "ollama" : Ai.currentModelIsLocal
    readonly property int attachmentLimit: mode === "assistant" ? 100 : Ai.getModel()?.api_format === "gemini" ? 1 : 0
    readonly property bool actionsAvailable: mode === "assistant" || Ai.effectiveTool === "functions"
    readonly property bool canSend: !busy && compatible && !GlobalStates.screenLocked && draft.trim().length > 0 && Config.options.policies.ai !== 0
    property string conversationId: ""
    property string conversationMode: "chat"
    property string conversationModel: ""
    property string title: ""
    property double createdAt: 0
    property string draft: ""
    property var attachments: []
    property var messages: []
    property string problem: ""
    property bool active: false
    property bool loading: false
    property bool initialized: false
    property var currentReply: null
    property bool restoreNeeded: false
    property int epoch: 0
    property double requestStartedAt: 0
    property int elapsedSeconds: 0
    property string rollbackRequest: ""
    readonly property string statusText: {
        if (!busy) return "";
        if (LocalAiRuntime.unloading) return Translation.tr("Releasing model memory…");
        if (Assistant.preparingSubmission) return Translation.tr("Saving the task…");
        if (rollbackRequest) return Translation.tr("Restoring the checkpoint…");
        if (mode === "chat" && !currentReply?.submissionId) return Ai.status || (Ai.requestAfterKeyring ? Translation.tr("Unlocking the API key…") : Translation.tr("Waiting for the model…"));
        if (Assistant.approval) return Translation.tr("Waiting for your confirmation");
        if (Assistant.queued) return Translation.tr("Starting the assistant…");
        return Assistant.currentAction || (currentReply?.text ? Translation.tr("Generating response…") : Translation.tr("Waiting for the model…"));
    }
    signal submitted()
    signal inputRequested()
    function releaseMemory() {
        if (busy || !localModel) return;
        save();
        requestStartedAt = Date.now(); elapsedSeconds = 0;
        LocalAiRuntime.unloadModel(mode === "assistant" ? (Assistant.useStrong ? Assistant.profile.strong_model : Assistant.profile.model) : Ai.getModel()?.model,
            mode === "assistant" ? Assistant.profile.endpoint : Ai.getModel()?.endpoint);
    }

    Component { id: entryComponent; SidebarMessage {} }
    function uid() { return Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 12); }
    function append(value) {
        const entry = entryComponent.createObject(root, Object.assign({uid:uid()}, value));
        messages = messages.concat([entry]);
        return entry;
    }
    function serialized() {
        return messages.map(m => ({uid:m.uid, role:m.role, text:m.text, model:m.model, status:m.status,
            hasActions:m.hasActions, contextExcluded:m.contextExcluded, truncated:m.truncated, attachments:m.attachments, steps:m.steps, error:m.error,
            submissionId:m.submissionId, transactionId:m.transactionId, transactionState:m.transactionState,
            rollbackAvailable:m.rollbackAvailable, conflicts:m.conflicts, changes:m.changes}));
    }
    function contextEntries() {
        return serialized().filter(message => !message.contextExcluded).map(message => {
            if (message.role !== "assistant" || !message.submissionId) return message;
            const details = message.steps.map(step => step.label + (step.path ? ": " + step.path : ""));
            details.push("Task status: " + (message.transactionState || message.status));
            if (message.error) details.push(message.error);
            return Object.assign({}, message, {text:message.text + "\n" + details.join("\n")});
        });
    }
    function changed() { if (!loading && initialized && !autosave.running) autosave.start(); }
    function save(callback) {
        autosave.stop();
        if (loading) { if (callback) callback(false, Translation.tr("The conversation is still loading")); return; }
        if (!conversationId || (!messages.length && !draft.trim())) { if (callback) callback(true, ""); return; }
        ChatStore.save({id:conversationId, title:title || Translation.tr("New conversation"), createdAt,
            updatedAt:Date.now(), mode:conversationMode, model:conversationModel, draft, messages:serialized()}, callback);
    }
    function clearView() {
        const previous = messages;
        currentReply = null; messages = [];
        // Let ListView release its delegates before destroying their data.
        previous.forEach(m => m.destroy(1000));
    }
    function fresh() {
        loading = true; epoch++;
        clearView(); conversationId = uid(); conversationMode = mode; title = ""; createdAt = Date.now();
        conversationModel = (mode === "assistant" ? Assistant.profile.model : Ai.currentModelId) ?? "";
        draft = ""; attachments = []; problem = ""; restoreNeeded = false;
        loading = false;
    }
    function newConversation() {
        if (busy) return;
        save(); fresh();
        if (mode === "assistant") Assistant.reset(); else Ai.clearMessages();
    }
    function openConversation(id) {
        if (busy || GlobalStates.screenLocked) return;
        save();
        const generation = ++epoch;
        ChatStore.call("load", {id}, (chat, error) => {
            if (generation !== epoch || busy || GlobalStates.screenLocked) return;
            if (!chat) { problem = error || Translation.tr("Could not open the chat"); return; }
            loading = true; clearView();
            conversationId = chat.id; title = chat.title; createdAt = chat.createdAt; conversationMode = chat.mode;
            conversationModel = chat.model;
            draft = chat.draft; attachments = []; problem = "";
            chat.messages.forEach(m => append(m));
            if (compatible) restoreBackend();
            loading = false;
            if (messages.some(m => m.transactionId)) Assistant.refreshTransactions();
        });
    }
    function restoreBackend() {
        if (mode === "assistant") { Assistant.restoreConversation(contextEntries()); restoreNeeded = false; }
        else {
            const savedModel = Ai.models[conversationModel] ? conversationModel : Ai.modelList.find(id => Ai.models[id].name === conversationModel);
            if (savedModel) Ai.setModel(savedModel, false);
            Ai.restoreConversation(contextEntries());
            restoreNeeded = false;
        }
    }
    function userMessage(text, files) {
        if (!title) title = text.replace(/\s+/g, " ").trim().slice(0, 64);
        append({role:"user", text, attachments:files});
        active = true;
        requestStartedAt = Date.now(); elapsedSeconds = 0;
        changed(); submitted();
    }
    function prepareAssistantSubmission(request, done) {
        if (loading || GlobalStates.screenLocked || (active && !request.tool) || Ai.nativeGenerating || Ai.requestAfterKeyring) {
            done(null, Translation.tr("Finish the current response before starting another task")); return;
        }
        const preparation = Assistant.submissionGeneration;
        const valid = () => preparation === Assistant.submissionGeneration && !GlobalStates.screenLocked;
        const begin = () => {
            if (!valid()) return;
            if (request.surface === "launcher" && !request.continuation) {
                fresh(); conversationMode = "assistant";
                conversationModel = Assistant.useStrong ? Assistant.profile.strong_model : Assistant.profile.model;
            }
            const history = contextEntries();
            const previousDraft = draft;
            const files = request.paths.slice();
            userMessage(request.displayText, files);
            messages[messages.length - 1].submissionId = request.submissionId;
            currentReply = append({model:Assistant.useStrong ? Assistant.profile.strong_model : Assistant.profile.model,
                status:"preparing", submissionId:request.submissionId, transactionId:request.submissionId});
            const reply = currentReply;
            if ((request.surface === "sidebar" || request.continuation) && !request.tool && draft.trim() === request.text) draft = "";
            const id = conversationId;
            save((ok, error) => {
                if (!valid() || id !== conversationId) return;
                if (!ok) {
                    reply.status = "error"; reply.error = error; active = false;
                    if (!draft) draft = previousDraft;
                    problem = error;
                    done(null, error); return;
                }
                reply.status = "waiting";
                if (!request.tool) attachments = [];
                problem = "";
                done({conversationId:id, history}, "");
            });
        };
        if (request.surface === "launcher" && !request.continuation) save((ok, error) => {
            if (!valid()) return;
            if (ok) begin(); else done(null, error);
        });
        else begin();
    }
    function updateTransaction(value) {
        const id = value.transaction_id;
        let updated = false;
        for (const message of messages) {
            if (message.transactionId !== id || message.role !== "assistant") continue;
            message.transactionState = value.state ?? message.transactionState;
            message.rollbackAvailable = value.rollback_available === true;
            message.conflicts = value.conflicts ?? [];
            if (value.diff) message.changes = value.diff;
            if (message.transactionState === "rolled_back") message.status = "rolled_back";
            if (message.transactionState === "rollback_conflict") message.status = "rollback_conflict";
            updated = true;
        }
        if (updated) { if (conversationMode === "chat") restoreNeeded = true; save(); }
    }
    function rollback(entry) {
        if (busy || !entry?.transactionId || !entry.rollbackAvailable) return false;
        rollbackRequest = entry.transactionId;
        if (!Assistant.rollback(entry.transactionId)) { rollbackRequest = ""; return false; }
        return true;
    }
    function deleteCheckpoint(entry) {
        if (busy || !entry?.transactionId) return false;
        return Assistant.deleteCheckpoint(entry.transactionId);
    }
    function send() {
        if (!canSend) return false;
        const text = draft.trim();
        conversationModel = mode === "assistant" ? (Assistant.useStrong ? Assistant.profile.strong_model : Assistant.profile.model) : Ai.currentModelId;
        if (mode === "assistant") {
            if (restoreNeeded || !Assistant.ready) Assistant.restoreConversation(contextEntries());
            restoreNeeded = false;
            Assistant.selectedPaths = attachments.slice();
            if (!Assistant.submit(text, text, "sidebar")) return false;
            return true;
        } else {
            if (!Ai.getModel()) { problem = Translation.tr("Choose a model first"); return false; }
            if (Ai.getModel().requires_key && Ai.apiKeysLoaded && !Ai.currentModelHasApiKey) {
                problem = Translation.tr("Add an API key in the chat menu"); return false;
            }
            if (restoreNeeded || currentReply?.submissionId) { Ai.restoreConversation(contextEntries()); restoreNeeded = false; }
            currentReply = null;
            userMessage(text, attachments.slice());
            Ai.attachFile(attachments[0] ?? "");
            Ai.sendUserMessage(text);
            // Pair the optimistic user row with the provider's stable object.
            const nativeUser = Ai.messageIDs.map(id => Ai.messageByID[id]).filter(m => m.role === "user").slice(-1)[0];
            if (nativeUser) nativeUser.uid = messages.filter(m => m.role === "user").slice(-1)[0].uid;
            syncAi();
        }
        draft = ""; attachments = []; problem = ""; save();
        return true;
    }
    function syncAi() {
        if (mode !== "chat" || !active || loading || currentReply?.submissionId) return;
        const native = Ai.messageIDs.map(id => Ai.messageByID[id]).filter(m => m && m.visibleToUser && (m.role === "user" || m.role === "assistant"));
        for (const source of native) {
            if (!source.uid) source.uid = uid();
            let entry = messages.find(m => m.uid === source.uid);
            if (!entry) entry = append({uid:source.uid, role:source.role, model:source.model, source});
            entry.source = source;
            entry.contextExcluded = entry.contextExcluded || source.functionCall?.name === "remote_context";
            if (entry.role === "assistant" && entry.submissionId) continue;
            const text = source.rawContent || source.content || "";
            if (entry.text !== text) { entry.text = text; changed(); }
            entry.hasActions = entry.hasActions || !!source.functionCall || source.functionPending;
            entry.status = source.functionPending ? "approval" : source.done ? "done" : text ? "streaming" : "waiting";
        }
        if (!Ai.generating && !Ai.requestAfterKeyring && !native.some(m => m.functionPending)) {
            if (Ai.problem) {
                let last = messages[messages.length - 1];
                if (!last || last.role !== "assistant") last = append({role:"assistant"});
                last.error = Ai.problem; last.status = "error";
            }
            finish();
        }
    }
    function finish() {
        if (!active) return;
        if (currentReply && ["preparing", "waiting", "streaming", "approval"].includes(currentReply.status)) currentReply.status = currentReply.error ? "error" : "done";
        active = false; save();
    }
    function stop() {
        if (LocalAiRuntime.unloading) { LocalAiRuntime.cancel(); return; }
        if (conversationMode === "chat") syncAi();
        messages.filter(m => ["preparing", "waiting", "streaming", "approval"].includes(m.status)).forEach(m => m.status = "interrupted");
        if (conversationMode === "assistant" || currentReply?.submissionId || Assistant.preparingSubmission || rollbackRequest) { restoreNeeded = true; Assistant.cancel(); rollbackRequest = ""; }
        else {
            Ai.requestAfterKeyring = false;
            for (const m of messages) if (m.source?.functionPending) Ai.rejectCommand(m.source);
            Ai.stopGeneration();
        }
        active = false; save();
    }
    function branch(index) {
        if (busy || !compatible || index < 0 || messages[index]?.role !== "user") return;
        const previous = serialized(); const text = previous[index].text;
        save(); fresh(); loading = true;
        previous.slice(0, index).forEach(m => append(Object.assign({}, m, {uid:uid()})));
        title = text.replace(/\s+/g, " ").slice(0, 64);
        draft = text; restoreBackend(); loading = false; save();
        inputRequested();
    }
    function retry(index) {
        if (busy || mode !== "chat" || !compatible) return;
        let userIndex = index - 1;
        while (userIndex >= 0 && messages[userIndex].role !== "user") userIndex--;
        if (userIndex < 0 || messages.slice(userIndex, index + 1).some(m => m.hasActions || m.attachments.length)) return;
        branch(userIndex); send();
    }
    function attach(urls) {
        if (!attachmentLimit) { problem = Translation.tr("This model does not support file attachments"); return; }
        const paths = [];
        for (const url of urls) {
            const value = String(url);
            if (!value.startsWith("file:///") && !value.startsWith("/")) { problem = Translation.tr("Choose an existing local file"); return; }
            let path;
            try { path = value.startsWith("file://") ? decodeURIComponent(value.slice(7)) : value; }
            catch (_) { problem = Translation.tr("Choose an existing local file"); return; }
            if (!attachments.includes(path) && !paths.includes(path)) paths.push(path);
        }
        if (attachments.length + paths.length > attachmentLimit) { problem = Translation.tr("This mode accepts up to %1 files").arg(attachmentLimit); return; }
        const generation = epoch;
        ChatStore.call("files", {paths}, values => {
            if (generation !== epoch || GlobalStates.screenLocked || !values) return;
            const merged = [...new Set(attachments.concat(values))];
            if (merged.length > attachmentLimit) { problem = Translation.tr("This mode accepts up to %1 files").arg(attachmentLimit); return; }
            attachments = merged; problem = "";
        });
    }
    function rename(id, name) {
        if (!name.trim()) return;
        if (id === conversationId) { title = name.trim(); save(); }
        else ChatStore.rename(id, name);
    }
    function remove(id) {
        if (busy) return;
        if (id === conversationId) { autosave.stop(); fresh(); if (mode === "assistant") Assistant.reset(); else Ai.clearMessages(); }
        ChatStore.remove(id);
    }
    onDraftChanged: changed()
    onModeChanged: if (initialized) {
        if (active) stop(); save();
        if (messages.length && conversationMode === mode) { restoreBackend(); return; }
        fresh();
        if (mode === "assistant") Assistant.reset(); else if (!Ai.generating) Ai.clearMessages();
    }
    onAttachmentLimitChanged: if (attachments.length > attachmentLimit) { attachments = []; problem = Translation.tr("Attachments cleared after changing the model"); }
    Component.onCompleted: {
        fresh(); initialized = true; ChatStore.refresh();
        if (mode === "assistant" && Assistant.messages.length) {
            Assistant.messages.forEach(m => append({role:m.role, text:m.text}));
            title = messages.find(m => m.role === "user")?.text.slice(0, 64) ?? "";
            if (Assistant.busy || Assistant.queued) { active = true; currentReply = append({text:Assistant.streaming, status:"streaming"}); }
        }
    }
    Timer { id: autosave; interval: 500; onTriggered: root.save() }
    Timer { interval: 50; repeat: true; running: root.active && root.mode === "chat" && !root.currentReply?.submissionId; onTriggered: root.syncAi() }
    Timer { interval: 1000; repeat: true; running: root.busy; onTriggered: root.elapsedSeconds = Math.max(0, Math.floor((Date.now() - root.requestStartedAt) / 1000)) }
    Connections {
        target: Assistant
        function onSubmitted(text, surface) {
            if (root.currentReply?.submissionId === Assistant.submissionId && Assistant.submissionId) return;
            if (root.mode !== "assistant") return;
            if (!root.compatible) root.newConversation();
            root.userMessage(text, Assistant.selectedPaths.slice());
            root.currentReply = root.append({model:root.modelName, status:"waiting"});
        }
        function onToken(text) { if (root.currentReply && root.active) { root.currentReply.text += text; root.currentReply.status = "streaming"; root.changed(); } }
        function onAnswer(text) { if (root.currentReply && root.active) { root.currentReply.text = text; root.changed(); } }
        function onTaskEvent(event) {
            if (!root.active || !root.currentReply) return;
            if (event.type === "step") {
                root.currentReply.hasActions = true;
                if (event.state === "done") root.currentReply.steps = root.currentReply.steps.concat([{label:Assistant.actionLabel(event.tool), path:event.result?.path ?? ""}]);
            } else if (event.type === "approval") {
                root.currentReply.status = "approval";
                if (event.details?.diff) root.currentReply.changes = event.details.diff;
            }
            else if (event.type === "answer") root.currentReply.truncated = event.truncated === true;
            else if (event.type === "error") { root.currentReply.error = event.message; root.currentReply.status = "error"; }
            else if (event.type === "cancelled") root.currentReply.status = "interrupted";
            root.changed();
        }
        function onTaskFinished() {
            if (root.rollbackRequest) { root.rollbackRequest = ""; if (Assistant.problem) root.problem = Assistant.problem; }
            if (!root.active || (root.mode !== "assistant" && !root.currentReply?.submissionId)) return;
            if (root.currentReply && Assistant.problem && !root.currentReply.error) root.currentReply.error = Assistant.problem;
            root.finish();
        }
        function onTransactionChanged(value) { root.updateTransaction(value); }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked) return;
            if (root.active) root.stop();
            root.save(); root.fresh();
            Ai.requestAfterKeyring = false; Ai.clearMessages();
            LocalAiRuntime.stop();
            ChatStore.chats = []; ChatStore.query = "";
        }
    }
}
