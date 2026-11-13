#!/usr/bin/env bash
# Lists installed Ollama models by reading their manifests from disk, so it works
# (and costs nothing) while the Ollama server is stopped. `ollama list` would start it.
# Output: one JSON array, e.g. [{"name":"qwen3.5:latest","size":6594474236}]

# Match local-ollama.py and velora-agentd: one server reads one model store.
# Combining stores advertises models that the launched server cannot load.
if [[ -n "${OLLAMA_MODELS:-}" ]]; then
    dirs=("$OLLAMA_MODELS/manifests")
else
    dirs=()
    for folder in "$HOME/.ollama/models" /var/lib/ollama /usr/share/ollama/.ollama/models; do
        if [[ -d "$folder/manifests" ]]; then
            dirs=("$folder/manifests")
            break
        fi
    done
fi

for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    # <dir>/<registry>/<namespace>/<model>/<tag>
    find "$dir" -mindepth 4 -maxdepth 4 -type f -printf '%P\n' 2>/dev/null | while IFS=/ read -r registry namespace model tag; do
        name="$model:$tag"
        [[ "$registry" == "registry.ollama.ai" && "$namespace" == "library" ]] || name="$registry/$namespace/$name"
        [[ "$registry" == "registry.ollama.ai" && "$namespace" != "library" ]] && name="$namespace/$model:$tag"
        size=$(jq '[.layers[]?.size] | add // 0' "$dir/$registry/$namespace/$model/$tag" 2>/dev/null || echo 0)
        printf '{"name":"%s","size":%s}\n' "$name" "${size:-0}"
    done
done | jq -s -c 'unique_by(.name)'
