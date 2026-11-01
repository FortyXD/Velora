#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <image_path> [model] [prompt]"
    echo "Tip: set GEMINI_WALLPAPER_MODEL and/or GEMINI_WALLPAPER_PROMPT to provide defaults."
    exit 1
fi

# Variables
SOURCE_IMG_PATH="$1"
MODEL="${2:-${GEMINI_WALLPAPER_MODEL:-gemini-2.5-flash}}" # We use the flash variant so it's fast
WALLPAPER_NAME="$(basename "$SOURCE_IMG_PATH")"
PROMPT="${3:-${GEMINI_WALLPAPER_PROMPT:-Categorize the wallpaper. Its file name is $WALLPAPER_NAME}}"
RESIZED_IMG_PATH=$(mktemp --suffix=.jpg)
trap 'rm -f -- "$RESIZED_IMG_PATH"' EXIT

# Resize image for speed
magick "$SOURCE_IMG_PATH" -resize 200x -quality 50 "$RESIZED_IMG_PATH"

# Get API key
API_KEY=$(secret-tool lookup 'application' 'illogical-impulse' | jq -r '.apiKeys.gemini')
case "$API_KEY" in *$'\r'*|*$'\n'*) echo "Invalid API key" >&2; exit 1;; esac

# Encode image to base64
if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
    B64FLAGS="--input"
else
    B64FLAGS="-w0"
fi
B64DATA="$(base64 $B64FLAGS "$RESIZED_IMG_PATH")"
# echo $B64DATA

# Prepare request data
payload=$(jq -n --arg image "$B64DATA" --arg prompt "$PROMPT" '{
    contents: [{parts: [
        {inline_data: {mime_type: "image/jpeg", data: $image}},
        {text: $prompt}
    ]}],
    generationConfig: {
        responseMimeType: "text/x.enum",
        responseSchema: {type: "string", enum: ["abstract", "anime", "city", "minimalist", "landscape", "plants", "person", "space"]},
        temperature: 0
    }
}')
# echo "$payload" | jq

# Make the request
response=$(curl "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
-H @<(printf 'x-goog-api-key: %s\n' "$API_KEY") \
-H 'Content-Type: application/json' \
-X POST \
--data-binary @<(printf '%s' "$payload") 2> /dev/null)
# echo "$response" | jq

# Write the result
echo "$response" | jq -r '.candidates[0].content.parts[0].text'
