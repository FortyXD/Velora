pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common
import "ai/ProviderPresets.js" as Presets

Singleton {
    id: root
    readonly property var providers: Presets.providers
    readonly property var records: Config.options.ai.extraModels
    property string problem: ""
    property string notice: ""
    property var pendingRecord: null
    readonly property bool saving: pendingRecord !== null || KeyringStorage.saving
    signal saved(string id)

    function ensureKeyring() { if (!KeyringStorage.loaded && !KeyringStorage.fetching) KeyringStorage.fetchKeyringData(); }
    function keyId(provider, endpoint) { return provider === "custom" ? "custom-" + Qt.md5(endpoint).slice(0,16) : provider; }
    function saveConnection(providerId, name, model, endpoint, key, editingId) {
        if (saving) return false;
        problem = ""; notice = "";
        model = model.trim(); key = key.trim();
        if (!model || /[\r\n]/.test(model)) { problem = Translation.tr("Enter the model ID from your provider"); return false; }
        const provider = Presets.provider(providerId);
        endpoint = Presets.endpointFor(providerId, model, endpoint);
        if (!Presets.validEndpoint(endpoint)) { problem = Translation.tr("Enter an HTTP or HTTPS API URL without a key or query parameters"); return false; }
        if (/[\r\n]/.test(key)) { problem = Translation.tr("The API key must be on one line"); return false; }
        const credential = root.keyId(providerId, endpoint);
        if (!KeyringStorage.loaded) { ensureKeyring(); problem = Translation.tr("Unlock the keyring before saving a connection"); return false; }
        if (!key && !KeyringStorage.keyringData?.apiKeys?.[credential]) { problem = Translation.tr("Paste an API key for this provider"); return false; }
        const id = editingId || "api-" + Qt.md5(providerId + "|" + endpoint + "|" + model).slice(0,24);
        const record = {connectionId:id,providerId,name:name.trim() || provider.name + " · " + model,model,endpoint,
            api_format:provider.format ?? "openai",requires_key:true,key_id:credential,key_get_link:provider.keyUrl,
            homepage:provider.modelsUrl,icon:provider.icon,
            extraParams: providerId === "anthropic" ? {temperature:null,max_tokens:4096} : providerId === "openai" ? {temperature:null} : {}};
        if (key) { pendingRecord = record; KeyringStorage.setNestedField(["apiKeys",credential],key); }
        else commit(record);
        return true;
    }
    function recordId(record) { return record.connectionId || Ai.safeModelName(record.model); }
    function commit(record) {
        const others = records.filter(item => recordId(item) !== record.connectionId);
        Config.options.ai.extraModels = others.concat([record]);
        notice = Translation.tr("Connection saved"); saved(record.connectionId);
    }
    function remove(id) {
        if (saving || Ai.generating) return;
        Config.options.ai.extraModels = records.filter(item => recordId(item) !== id);
        notice = Translation.tr("Connection removed");
    }
    function removeKey(id) {
        if (!KeyringStorage.loaded || saving) return;
        KeyringStorage.setNestedField(["apiKeys", id], "");
    }
    function useForAssistant(id) {
        const model = Ai.models[id];
        if (!model || Ai.generating || Assistant.queued) return;
        if (Config.options.policies.ai !== 1 && !model.local) { problem = Translation.tr("Allow cloud AI in the AI settings to use this connection"); return; }
        Config.options.assistant.keyId = model.key_id || "veloraAssistant";
        Config.options.assistant.provider = model.local ? "ollama" : model.api_format === "gemini" ? "gemini" : "openai";
        Config.options.assistant.endpoint = model.local ? "http://127.0.0.1:11434" : model.endpoint;
        Config.options.assistant.model = model.model;
        Config.options.assistant.vision = false;
    }
    Connections {
        target: KeyringStorage
        function onSaveFinished(ok) {
            if (!root.pendingRecord) return;
            const record = root.pendingRecord; root.pendingRecord = null;
            if (ok) root.commit(record);
            else root.problem = Translation.tr("Could not save the API key. The connection was not changed.");
        }
    }
}
