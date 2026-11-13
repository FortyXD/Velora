.pragma library

// Official API endpoints; model IDs remain user-selectable rather than a stale catalogue.
const providers = [
    {id:"openai", name:"OpenAI", endpoint:"https://api.openai.com/v1/chat/completions", keyUrl:"https://platform.openai.com/api-keys", modelsUrl:"https://developers.openai.com/api/docs/models", icon:"openai-symbolic"},
    {id:"anthropic", name:"Claude · Anthropic", endpoint:"https://api.anthropic.com/v1/chat/completions", keyUrl:"https://console.anthropic.com/settings/keys", modelsUrl:"https://platform.claude.com/docs/en/about-claude/models/overview", icon:"spark-symbolic"},
    {id:"gemini", name:"Google Gemini", endpoint:"https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent", keyUrl:"https://aistudio.google.com/app/apikey", modelsUrl:"https://ai.google.dev/gemini-api/docs/models", icon:"google-gemini-symbolic", format:"gemini"},
    {id:"deepseek", name:"DeepSeek", endpoint:"https://api.deepseek.com/chat/completions", keyUrl:"https://platform.deepseek.com/api_keys", modelsUrl:"https://api-docs.deepseek.com/", icon:"deepseek-symbolic"},
    {id:"openrouter", name:"OpenRouter", endpoint:"https://openrouter.ai/api/v1/chat/completions", keyUrl:"https://openrouter.ai/settings/keys", modelsUrl:"https://openrouter.ai/models", icon:"spark-symbolic"},
    {id:"groq", name:"Groq", endpoint:"https://api.groq.com/openai/v1/chat/completions", keyUrl:"https://console.groq.com/keys", modelsUrl:"https://console.groq.com/docs/models", icon:"spark-symbolic"},
    {id:"mistral", name:"Mistral", endpoint:"https://api.mistral.ai/v1/chat/completions", keyUrl:"https://console.mistral.ai/api-keys", modelsUrl:"https://docs.mistral.ai/models", icon:"mistral-symbolic"},
    {id:"xai", name:"Grok · xAI", endpoint:"https://api.x.ai/v1/chat/completions", keyUrl:"https://console.x.ai", modelsUrl:"https://docs.x.ai/developers/models", icon:"spark-symbolic"},
    {id:"custom", name:"OpenAI-compatible API", endpoint:"", keyUrl:"", modelsUrl:"", icon:"spark-symbolic"}
];

function provider(id) { return providers.find(item => item.id === id) ?? providers[providers.length - 1]; }
function validEndpoint(value) {
    // No embedded credentials, query-string secrets or shell expansions.
    return /^https?:\/\/(?:[a-zA-Z0-9.-]+|\[::1\])(?::\d+)?(?:\/[a-zA-Z0-9._~%/:+-]*)?$/.test(value);
}
function endpointFor(id, model, custom) {
    return id === "custom" ? custom.trim() : provider(id).endpoint.replace("{model}", encodeURIComponent(model.replace(/^models\//, "")));
}
