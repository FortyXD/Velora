import QtQuick
import qs.services
import qs.modules.common

ApiStrategy {
    property bool isReasoning: false
    
    function buildEndpoint(model: AiModel): string {
        // console.log("[AI] Endpoint: " + model.endpoint);
        return model.local ? model.endpoint.replace(/\/v1\/chat\/completions\/?$/, "/api/chat") : model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: systemPrompt},
                ...messages.map(message => {
                    return {
                        "role": message.role,
                        "content": message.rawContent,
                    }
                }),
            ],
            "stream": true,
            "temperature": temperature,
        };
        if (tools && tools.length > 0) baseData.tools = tools; // An empty list makes some servers reject the request
        if (model.local) {
            baseData.keep_alive = PowerSaving.onBattery ? "60s" : "5m";
            baseData.options = {temperature, num_ctx:8192, num_predict:4096, num_gpu:(Config.options.ai.localGpu ?? true) && !PowerSaving.onBattery ? -1 : 0};
            delete baseData.temperature;
        }
        const data = model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
        if (data.temperature === null) delete data.temperature;
        return data;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H @<(printf 'Authorization: Bearer %s\\n' "\$\{${apiKeyEnvVarName}\}")`;
    }

    function parseResponseLine(line, message) {
        // Remove 'data: ' prefix if present and trim whitespace
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }

        // console.log("[AI] OpenAI: Data:", cleanData);
        
        // Handle special cases
        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
            return { finished: true };
        }
        
        // Real stuff
        try {
            const dataJson = JSON.parse(cleanData);

            // Error response handling
            if (dataJson.error) {
                const errorMsg = `**Error**: ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true, error:errorMsg };
            }

            let newContent = "";

            const responseContent = dataJson.choices?.[0]?.delta?.content || dataJson.message?.content;
            const responseReasoning = dataJson.choices?.[0]?.delta?.reasoning || dataJson.choices?.[0]?.delta?.reasoning_content || dataJson.message?.thinking;

            if (responseContent && responseContent.length > 0) {
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n</think>\n\n";
                    message.content += endBlock;
                    message.rawContent += endBlock;
                }
                newContent = responseContent;
            } else if (responseReasoning && responseReasoning.length > 0) {
                if (!isReasoning) {
                    isReasoning = true;
                    const startBlock = "\n\n<think>\n\n";
                    message.rawContent += startBlock;
                    message.content += startBlock;
                }
                newContent = responseReasoning;
            }

            message.content += newContent;
            message.rawContent += newContent;

            // Usage metadata
            if (dataJson.usage) {
                return {
                    tokenUsage: {
                        input: dataJson.usage.prompt_tokens ?? -1,
                        output: dataJson.usage.completion_tokens ?? -1,
                        total: dataJson.usage.total_tokens ?? -1
                    }
                };
            }

            if (dataJson.done) {
                if (isReasoning) {
                    isReasoning = false;
                    message.content += "\n</think>\n";
                    message.rawContent += "\n</think>\n";
                }
                return { finished: true, error:dataJson.done_reason === "length" ? Translation.tr("The model reached its output limit. Ask it to continue.") : "" };
            }
            return {phase:responseReasoning ? Translation.tr("Thinking…") : responseContent ? Translation.tr("Generating response…") : ""};
            
        } catch (e) {
            console.log("[AI] OpenAI: Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }
        
        return {};
    }
    
    function onRequestFinished(message) {
        // OpenAI format doesn't need special finish handling
        return {};
    }
    
    function reset() {
        isReasoning = false;
    }

}
