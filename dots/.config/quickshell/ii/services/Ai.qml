pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs
import qs.services.ai
import "ai/PromptDefaults.js" as PromptDefaults

/**
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 * Supports Gemini and OpenAI models.
 * Limitations:
 * - For now functions only work with Gemini API format
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()

    // Built when a request is sent: as a binding it was recomputed on every clock tick and window focus change
    function buildSystemPrompt() {
        let prompt = Config.options?.ai?.systemPrompt ?? PromptDefaults.text;
        if (Qt.md5(prompt) === PromptDefaults.legacyHash) prompt = PromptDefaults.text;
        const substitutions = root.promptSubstitutions();
        for (let key in substitutions) {
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(substitutions[key]);
        }
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    function promptSubstitutions() {
        return {
            "{DISTRO}": SystemInfo.distroName,
            "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
            "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
            "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})`
        };
    }

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    // Local models get no tools unless enabled: many of them error out or ramble when tools are sent
    readonly property bool currentModelIsLocal: models[currentModelId]?.local ?? false
    property string currentTool: (root.currentModelIsLocal ? Config?.options.ai.localTool : Config?.options.ai.tool) ?? "none"
    property string toolOverride: "" // Set for one response by switch_to_search_mode
    readonly property string effectiveTool: root.toolOverride.length > 0 ? root.toolOverride : root.currentTool
    readonly property bool nativeGenerating: requester.running || LocalAiRuntime.preparing
    readonly property bool generating: nativeGenerating || Assistant.busy || Assistant.preparingSubmission
    property bool stopping: false
    property string status: ""
    property string problem: ""
    property string remoteConsent: ""
    property string remoteSystemPrompt: ""
    readonly property int accessPolicy: Config.options.policies.ai
    onAccessPolicyChanged: {
        if (!Config.ready) return;
        stopGeneration();
        for (const id of messageIDs) {
            const message = messageByID[id];
            if (message) message.functionPending = false;
        }
        responseFinished();
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked) return;
            root.stopGeneration();
            for (const id of root.messageIDs) {
                const message = root.messageByID[id];
                if (message) message.functionPending = false;
            }
        }
    }
    function contextMessages() {
        return root.messageIDs.map(id => root.messageByID[id]).filter(message => message
            && message.role !== Ai.interfaceRole && message.functionCall?.name !== "remote_context");
    }
    function contextFingerprint() {
        return Qt.md5(JSON.stringify({model:currentModelId, modelId:getModel()?.model, endpoint:getModel()?.endpoint,
            apiFormat:getModel()?.api_format, extraParams:getModel()?.extraParams, tool:effectiveTool, temperature,
            systemPrompt:remoteSystemPrompt,
            prompt:Config.options?.ai?.systemPrompt ?? PromptDefaults.text, file:pendingFilePath,
            messages:contextMessages().map(m => ({role:m.role, text:m.rawContent || m.content,
                call:m.functionCall, output:m.functionResponse, file:m.fileUri}))}));
    }
    function needsRemoteConsent(model) {
        return !model.local || !/^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?(?:\/|$)/i.test(model.endpoint)
            || /(?:^|[:/\-])cloud(?:$|[:/\-])/i.test(model.model ?? "") || root.effectiveTool === "search";
    }
    function requestRemoteConsent(model) {
        // Freeze dynamic desktop/date context while its transmission is reviewed.
        if (!remoteSystemPrompt) remoteSystemPrompt = buildSystemPrompt();
        const fingerprint = contextFingerprint();
        if (remoteConsent === fingerprint) return false;
        const existing = root.messageIDs.map(id => root.messageByID[id]).find(m => m?.functionPending
            && m.functionCall?.name === "remote_context" && m.functionCall.args.fingerprint === fingerprint);
        if (!existing) {
            const content = Translation.tr("Allow sending this conversation and its attachments to %1?").arg(model.name);
            const message = aiMessageComponent.createObject(root, {role:"assistant", content, rawContent:content,
                model:currentModelId, thinking:false, done:true, functionPending:true, functionName:"remote_context",
                functionCall:{name:"remote_context", args:{fingerprint, endpoint:model.endpoint,
                    messageCount:contextMessages().length, attachment:pendingFilePath || ""}}});
            const id = idForMessage(message);
            root.messageByID[id] = message;
            root.messageIDs = root.messageIDs.concat([id]);
        }
        status = Translation.tr("Waiting for your confirmation");
        root.responseFinished();
        return true;
    }
    readonly property bool waitingForFirstToken: requester.running && (requester.message?.thinking ?? false)
    readonly property var commandTool: ({
        name: "run_shell_command",
        description: "Propose a command in an isolated folder. The person must select its scope, approve running it, and separately approve applying its file changes. No network or irreversible effects are allowed.",
        parameters: {type:"object", additionalProperties:false,
            properties:{command:{type:"string"}}, required:["command"]}
    })
    readonly property var tools: ({
        gemini: {functions:[{functionDeclarations:[
            {name:"switch_to_search_mode",description:"Search the web"}, root.commandTool
        ]}], search:[{google_search:{}}], none:[]},
        openai: {functions:[{type:"function",function:root.commandTool}], search:[], none:[]},
        mistral: {functions:[{type:"function",function:root.commandTool}], search:[], none:[]}
    })
    property list<var> availableTools: models[currentModelId]?.connectionId && models[currentModelId]?.api_format !== "gemini" ? ["none"] : Object.keys(root.tools[models[currentModelId]?.api_format] ?? {})
    property var toolDescriptions: {
        "functions": Translation.tr("Reviewed commands with rollback, and search"),
        "search": Translation.tr("Gives the model search capabilities (immediately)"),
        "none": Translation.tr("Disable tools")
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - requires_key: Whether the model requires an API key
    // - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
    // - key_get_link: Link to get an API key
    // - key_get_description: Description of pricing and how to get an API key
    // - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
    property var models: Config.options.policies.ai === 2 ? {} : {
        "gemini-2.5-flash": aiModelComponent.createObject(root, {
            "name": "Gemini 2.5 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nNewer model that's slower than its predecessor but should deliver higher quality answers"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent",
            "model": "gemini-2.5-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "gemini-3-flash": aiModelComponent.createObject(root, {
            "name": "Gemini 3 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nPro-level intelligence at the speed and pricing of Flash."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent",
            "model": "gemini-3-flash-preview",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "mistral-medium-3": aiModelComponent.createObject(root, {
            "name": "Mistral Medium 3",
            "icon": "mistral-symbolic",
            "description": Translation.tr("Online | %1's model | Delivers fast, responsive and well-formatted answers. Disadvantages: not very eager to do stuff; might make up unknown function calls").arg("Mistral"),
            "homepage": "https://mistral.ai/news/mistral-medium-3",
            "endpoint": "https://api.mistral.ai/v1/chat/completions",
            "model": "mistral-medium-2505",
            "requires_key": true,
            "key_id": "mistral",
            "key_get_link": "https://console.mistral.ai/api-keys",
            "key_get_description": Translation.tr("**Instructions**: Log into Mistral account, go to Keys on the sidebar, click Create new key"),
            "api_format": "mistral",
        }),
    }
    readonly property var modelList: Object.keys(root.models)
    property bool localModelsLoaded: false
    property var installedModelIds: []
    readonly property string defaultLocalModelId: installedModelIds
        .filter(id => root.models[id]?.local)
        .slice().sort((a, b) => root.models[a].size - root.models[b].size || a.localeCompare(b))[0] ?? ""
    // Saved choice if it still exists, otherwise the smallest local model (cheapest to run)
    property string selectedModelId: ""
    property var currentModelId: {
        if (root.selectedModelId && root.modelAllowed(root.models[root.selectedModelId])) return root.selectedModelId;
        const saved = Persistent.states?.ai?.model;
        if (saved && root.modelAllowed(root.models[saved])) return saved;
        if (!root.localModelsLoaded) return undefined;
        return root.defaultLocalModelId || undefined;
    }

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(root),
        "gemini": geminiApiStrategy.createObject(root),
        "mistral": mistralApiStrategy.createObject(root),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    property var userModelIds: []
    function addUserModels() {
        const next = Object.assign({}, root.models);
        for (const id of userModelIds) delete next[id];
        const ids = [];
        (Config?.options.ai?.extraModels ?? []).forEach(model => {
            if (!model.model) return;
            const id = model.connectionId || root.safeModelName(model.model);
            next[id] = aiModelComponent.createObject(root, model);
            ids.push(id);
        });
        root.models = next; root.userModelIds = ids;
    }
    Connections {
        target: Config.options.ai
        function onExtraModelsChanged() { root.addUserModels(); }
        function onCredentialsRevisionChanged() { if (KeyringStorage.loaded) KeyringStorage.fetchKeyringData(); }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.addUserModels()
        }
    }

    property string pendingFilePath: ""

    Component.onCompleted: {
        setModel(currentModelId, false, false); // Do necessary setup for model
        root.addUserModels() // Config onReadyChanged above might not fire if config is loaded before this service
        root.refreshLocalModels()
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    function addModel(modelName, data) {
        root.models = Object.assign({}, root.models, {
            [modelName]: aiModelComponent.createObject(root, data)
        });
    }

    // Read only model metadata; this never starts Ollama or loads model weights.
    function refreshLocalModels() { getOllamaModels.running = true; }

    function installLocalModels(entries) {
        if (!Array.isArray(entries)) return;
        const next = Object.assign({}, root.models);
        for (const id of root.installedModelIds) delete next[id];
        const ids = [];
        for (const entry of entries) {
            const model = entry.name ?? entry;
            if (typeof model !== "string" || !model) continue;
            const id = root.safeModelName(model);
            next[id] = aiModelComponent.createObject(root, {
                name: guessModelName(model), icon: guessModelLogo(model),
                description: Translation.tr("Local Ollama model | %1").arg(model),
                homepage: `https://ollama.com/library/${model}`,
                endpoint: "http://localhost:11434/v1/chat/completions", model,
                requires_key: false, local: true, size: entry.size ?? 0
            });
            ids.push(id);
        }
        root.models = next;
        root.installedModelIds = ids;
        root.localModelsLoaded = true;
    }

    // Prompts and history are refreshed only when the AI tab is opened.
    function refreshLists() {
        refreshLocalModels();
        getDefaultPrompts.running = true;
        getUserPrompts.running = true;
        getSavedChats.running = true;
    }

    Process {
        id: getOllamaModels
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    root.installLocalModels(JSON.parse(data));
                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    Process {
        id: getDefaultPrompts
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
        });
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    function addApiKeyAdvice(model) {
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"), 
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId];
    }
    function modelAllowed(model) {
        return !!model && Config.options.policies.ai !== 0 && (Config.options.policies.ai === 1
            || (model.local && /^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?(?:\/|$)/i.test(model.endpoint)
                && !/(?:^|[:/\-])cloud(?:$|[:/\-])/i.test(model.model ?? "")));
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()
        if (modelList.indexOf(modelId) !== -1) {
            const model = models[modelId]
            // See if policy prevents online models
            if (!root.modelAllowed(model)) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            if (setPersistentState) { root.selectedModelId = modelId; Persistent.states.ai.model = modelId; }
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
            if (model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported: \n```\n") + modelList.join("\n```\n```\n") + "\n```", Ai.interfaceRole)
        }
    }

    function setTool(tool) {
        if (!root.tools[models[currentModelId]?.api_format] || !(tool in root.tools[models[currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        if (root.currentModelIsLocal) Config.options.ai.localTool = tool;
        else Config.options.ai.tool = tool;
        return true;
    }
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (isNaN(value) || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                root.addMessage(Translation.tr("API key is set (ends with `%1`)").arg(key.slice(-4)), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        remoteConsent = "";
        remoteSystemPrompt = "";
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
    }

    function restoreConversation(entries) {
        if (generating) return false;
        clearMessages();
        for (const entry of entries) {
            if (entry.role !== "user" && entry.role !== "assistant") continue;
            const message = aiMessageComponent.createObject(root, {
                uid:entry.uid ?? "", role:entry.role, content:entry.text, rawContent:entry.text,
                model:entry.model ?? "", thinking:false, done:true
            });
            const id = idForMessage(message);
            messageByID[id] = message;
            messageIDs = messageIDs.concat([id]);
        }
        return true;
    }

    Process {
        id: requester
        command: ["bash", "-s"]
        property string pendingScript: ""
        property AiMessageData message
        property ApiStrategy currentStrategy

        // The request contains private chat data. Pass it directly to bash rather
        // than writing an executable script at a shared, predictable /tmp path.
        onStarted: {
            requester.write(requester.pendingScript);
            requester.pendingScript = "";
            requester.stdinEnabled = false;
        }

        function markDone() {
            requester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null; // Reset hook after use
            }
            root.responseFinished()
        }

        function makeRequest(localReady = false) {
            if (GlobalStates.screenLocked || Config.options.policies.ai === 0 || root.stopping) return;
            const model = models[currentModelId];
            if (!model) { root.problem = Translation.tr("Choose a model first"); root.responseFinished(); return; }
            if (!root.modelAllowed(model)) { root.problem = Translation.tr("Allow cloud AI in the AI settings to use this connection"); root.responseFinished(); return; }
            if (root.needsRemoteConsent(model) && root.requestRemoteConsent(model)) return;
            root.problem = "";
            if (model.local && !localReady) {
                root.status = Translation.tr("Starting Ollama…");
                LocalAiRuntime.prepare(ok => {
                    if (root.stopping) return;
                    if (ok) makeRequest(true);
                    else { root.problem = LocalAiRuntime.problem || Translation.tr("Ollama did not become ready. Check the local service and try again."); root.status = ""; root.responseFinished(); }
                });
                return;
            }
            root.status = model.local ? Translation.tr("Loading model…") : Translation.tr("Connecting to the model…");

            // Fetch API keys first if needed; the request continues once they're loaded
            if (model?.requires_key && !KeyringStorage.loaded) {
                root.requestAfterKeyring = true;
                KeyringStorage.fetchKeyringData();
                return;
            }
            
            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Put API key in environment variable */
            requester.environment[`${root.apiKeyEnvVarName}`] = model.requires_key && root.apiKeys
                ? (root.apiKeys[model.key_id] ?? "") : "";

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const filteredMessageArray = root.contextMessages();
            const enabledTools = root.availableTools.includes(root.effectiveTool) ? (root.tools[model.api_format]?.[root.effectiveTool] ?? []) : [];
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray,
                root.needsRemoteConsent(model) ? root.remoteSystemPrompt : root.buildSystemPrompt(), root.temperature, enabledTools, root.pendingFilePath);
            root.remoteConsent = "";
            root.remoteSystemPrompt = "";
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            
            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\nset -e\numask 077\n"
                + 'case "${API_KEY:-}" in *$\'\\r\'*|*$\'\\n\'*) echo "Invalid API key" >&2; exit 1;; esac\n';

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            let scriptRequestContent = ""
            scriptRequestContent += `exec curl --no-buffer --fail-with-body --connect-timeout 10 --max-time 600 '${CF.StringUtils.shellSingleQuoteEscape(endpoint)}'`
                + (model.local ? " --noproxy '*'" : "")
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data-binary @<(printf '%s' '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}')`
                + "\n"
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            requester.pendingScript = scriptContent;
            requester.stdinEnabled = true;
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;
                // console.log("[Ai] Raw response line: ", data);

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);
                    if (result.phase) root.status = result.phase;
                    if (result.error) root.problem = result.error;
                    if (!result.phase && requester.message.content.length) root.status = Translation.tr("Generating response…");
                    // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));

                    if (result.functionCall) {
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        stderr: StdioCollector { id: requestErrors }

        onExited: (exitCode, exitStatus) => {
            root.status = "";
            LocalAiRuntime.release();
            if (exitCode !== 0 && !root.stopping && !root.problem) root.problem = Translation.tr("The model request failed") + (requestErrors.text.trim() ? ": " + requestErrors.text.trim().slice(-400) : "");
            if (!requester.message || !requester.currentStrategy) { root.responseFinished(); return; }
            const result = requester.currentStrategy.onRequestFinished(requester.message);
            
            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }
        }
    }

    property bool requestAfterKeyring: false
    Connections {
        target: KeyringStorage
        function onLoadedChanged() {
            if (!KeyringStorage.loaded || !root.requestAfterKeyring) return;
            root.requestAfterKeyring = false;
            requester.makeRequest();
        }
    }

    property bool harnessConversation: false
    Connections {
        target: Assistant
        function onAnswer(text) { if (root.harnessConversation) root.addMessage(text, "assistant"); }
        function onTaskFinished() { root.harnessConversation = false; root.responseFinished(); }
    }

    function stopGeneration() {
        stopping = true;
        remoteConsent = "";
        remoteSystemPrompt = "";
        status = "";
        LocalAiRuntime.cancel();
        requestAfterKeyring = false;
        if (Assistant.busy) Assistant.cancel();
        if (requester.running) requester.running = false; // onExited marks the message done
    }

    function sendUserMessage(message) {
        if (message.length === 0 || GlobalStates.screenLocked || Config.options.policies.ai === 0) return;
        stopping = false;
        problem = "";
        root.addMessage(message, "user");
        if (Assistant.enabled) {
            root.harnessConversation = true;
            if (root.pendingFilePath) { Assistant.selectedPaths = [root.pendingFilePath]; root.pendingFilePath = ""; }
            Assistant.submit(message); return;
        }
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function regenerate(messageIndex) {
        if (GlobalStates.screenLocked || Config.options.policies.ai === 0) return;
        stopping = false;
        if (Assistant.enabled) { root.addMessage(Translation.tr("Send a follow-up request to continue; actions are not repeated automatically."), root.interfaceRole); return; }
        if (messageIndex < 0 || messageIndex >= messageIDs.length) return;
        const id = root.messageIDs[messageIndex];
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        requester.makeRequest();
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "rawContent": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "functionName": name,
            "functionResponse": output,
            "thinking": false,
            "done": true,
            // "visibleToUser": false,
        });
    }

    function addFunctionOutputMessage(name, output) {
        const aiMessage = createFunctionOutputMessage(name, output);
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        if (message.functionCall?.name === "remote_context") {
            remoteConsent = ""; remoteSystemPrompt = ""; status = "";
            message.rawContent = Translation.tr("Sending this context was cancelled.");
            message.content = message.rawContent;
            root.responseFinished();
            return;
        }
        addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"))
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending || GlobalStates.screenLocked || Config.options.policies.ai === 0) return;
        if (message.functionCall?.name === "remote_context") {
            const requested = message.functionCall.args;
            if (requested.fingerprint !== contextFingerprint()) {
                message.functionPending = false;
                remoteConsent = ""; remoteSystemPrompt = "";
                root.problem = Translation.tr("The conversation changed. Send again to review the new context.");
                root.responseFinished();
                return;
            }
            message.functionPending = false;
            remoteConsent = requested.fingerprint;
            requester.makeRequest();
            return;
        }
        if (message.functionCall?.name !== "run_shell_command") return;
        const command = message.functionCall.args.command;
        if (!Assistant.submitTool("terminal_run", {command, network:false}, command, "sidebar")) return;
        message.functionPending = false;
        addFunctionOutputMessage(message.functionName, Translation.tr("The command was sent for isolated execution and review."));
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        if (name === "switch_to_search_mode") {
            if (Config.options.policies.ai !== 1) {
                addFunctionOutputMessage(name, Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"));
                return;
            }
            const modelId = root.currentModelId;
            root.toolOverride = "search"
            root.postResponseHook = () => { root.toolOverride = "" }
            addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "get_shell_config" || name === "set_shell_config") {
            addFunctionOutputMessage(name, Translation.tr("Select a configuration file in a desktop task. Direct configuration access is disabled."));
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            const contentToAppend = `\n\n**Command execution request**\n\n\`\`\`command\n${args.command}\n\`\`\``;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            message.functionPending = true; // Use thinking to indicate the command is waiting for approval
        }
        else root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
            })
        })
    }

    FileView {
        id: chatSaveFile
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true // Prevent race conditions
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
    }

    /**
     * Loads chat from a JSON list of message objects.
     * @param chatName name of the chat
     */
    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            // console.log(saveContent)
            const saveData = JSON.parse(saveContent)
            root.clearMessages()
            root.messageIDs = saveData.map((_, i) => {
                return i
            })
            // console.log(JSON.stringify(messageIDs))
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                root.messageByID[i] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                });
            }
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            getSavedChats.running = true;
        }
    }
}
