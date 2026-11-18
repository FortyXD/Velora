#!/usr/bin/env bash
# Installs the offline English <-> Russian translator used by the sidebar Translator tab.
# - Native CPU engine with CTranslate2 and SentencePiece
# - Argos Translate 1.9 models, only the CTranslate2 model and SentencePiece files are kept
#
# Prints machine-readable lines for the UI:
#   PROGRESS <percent> <message>
#   DONE
#   ERROR <message>
# Safe to run again: finished steps are skipped.
set -uo pipefail

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/folis/translate"
ENGINE_DIR="$DATA_DIR/bin"
MODELS_DIR="$DATA_DIR/models"

# argos-net.com stalls on some networks, so the pinned HuggingFace mirror comes first.
# The files are byte-identical to the official packages (same size); hashes are pinned below.
HF_REVISION="b363969765484ed7e8d0842e49231636f603e691"
HF_BASE="https://huggingface.co/TiberiuCristianLeon/Argostranslate/resolve/$HF_REVISION"
declare -A MODEL_SHA256=(
    [en_ru]="591d743ae103752b88ffc38785c50421320f4eff93c8967e0d3d2e14d4e27811"
    [ru_en]="e9ba8bf722d10a4a4c39f74289d5938fd47eac08dbe4ed0afd22d89445a5c3ac"
)
declare -A MODEL_SIZE=(
    [en_ru]=195746693
    [ru_en]=156239112
)

progress() { echo "PROGRESS $1 $2"; }
die() { echo "ERROR $1"; exit 1; }

mkdir -p "$DATA_DIR" "$MODELS_DIR" || die "Cannot create $DATA_DIR"

# Serialize builds and model publication when two shell instances open setup.
exec 9>"$DATA_DIR/.setup.lock" || die "Cannot lock translator setup"
flock 9 || die "Cannot lock translator setup"
script="$(readlink -f -- "${BASH_SOURCE[0]}")"
manifest="$(dirname -- "$script")/../../../../../../tools/velora-translate/Cargo.toml"
mkdir -p "$ENGINE_DIR" || die "Cannot create $ENGINE_DIR"
if command -v velora-translate >/dev/null; then
    engine="$(command -v velora-translate)"
else
    [[ -f "$manifest" ]] || die "Missing translator sources"
    target="${XDG_CACHE_HOME:-$HOME/.cache}/velora/translate-build"
    progress 2 "Building the native translation engine"
    cargo build --release --locked -j 2 --manifest-path "$manifest" --target-dir "$target" >&2 || die "Could not build the translation engine"
    engine="$target/release/velora-translate"
fi
if [[ ! -x "$ENGINE_DIR/velora-translate" ]] || ! cmp -s "$engine" "$ENGINE_DIR/velora-translate"; then
    temp_engine=$(mktemp "$ENGINE_DIR/.velora-translate.XXXXXX") || die "Cannot stage the engine"
    if ! install -m 755 "$engine" "$temp_engine" || ! mv -fT "$temp_engine" "$ENGINE_DIR/velora-translate"; then
        rm -f -- "$temp_engine"
        die "Cannot install the translation engine"
    fi
fi
progress 10 "Translation engine ready"
[[ ${1:-} != --engine-only ]] || exit 0

# 2. Models
# download <pair> <start percent> <end percent>
download_model() {
    local pair=$1 from=$2 to=$3
    local target="$MODELS_DIR/$pair"
    [[ -f "$target/model/model.bin" && -f "$target/sentencepiece.model" ]] && return 0

    local archive="$DATA_DIR/$pair.argosmodel"
    local expected=${MODEL_SIZE[$pair]}
    local urls=("$HF_BASE/$pair.argosmodel" "https://argos-net.com/v1/translate-${pair}-1_9.argosmodel")
    local ok=false
    for url in "${urls[@]}"; do
        rm -f "$archive"
        curl --fail --silent --location --connect-timeout 10 --speed-limit 2048 --speed-time 15 \
            --retry 3 --retry-all-errors -o "$archive" "$url" &
        local pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            local have
            have=$(stat -c %s "$archive" 2>/dev/null || echo 0)
            progress $(( from + (to - from) * have / expected )) "Downloading $pair model ($(( have / 1048576 ))/$(( expected / 1048576 )) MB)"
            sleep 1
        done
        if wait "$pid"; then
            if [[ "$(sha256sum "$archive" | cut -d' ' -f1)" == "${MODEL_SHA256[$pair]}" ]]; then
                ok=true
                break
            fi
            echo "Checksum mismatch for $url" >&2
        fi
    done
    $ok || { rm -f "$archive"; die "Could not download the $pair model (network blocked?)"; }

    # Keep only what's needed: the CTranslate2 model and the SentencePiece model.
    # The bundled stanza/ sentence splitter (torch pickles) is never extracted.
    local staging tmp
    staging=$(mktemp -d "$MODELS_DIR/.$pair.XXXXXX") || die "Cannot stage the $pair model"
    tmp="$staging/new"
    mkdir "$tmp" || die "Cannot create the $pair extraction directory"
    if ! bsdtar -x -f "$archive" -C "$tmp" --strip-components 1 --no-same-owner --no-same-permissions \
            --include '*/model/*' --include '*/sentencepiece.model' --include '*/metadata.json'; then
        rm -rf -- "$staging"
        die "Could not unpack the $pair model"
    fi
    [[ -f "$tmp/model/model.bin" && -f "$tmp/sentencepiece.model" ]] || { rm -rf -- "$staging"; die "Unexpected $pair model layout"; }
    if [[ -e "$target" || -L "$target" ]]; then
        mv -T -- "$target" "$staging/previous" || { rm -rf -- "$staging"; die "Cannot replace the incomplete $pair model"; }
    fi
    if ! mv -T -- "$tmp" "$target"; then
        if [[ -e "$staging/previous" || -L "$staging/previous" ]]; then
            mv -T -- "$staging/previous" "$target" || die "Previous $pair model preserved at $staging/previous"
        fi
        rm -rf -- "$staging"
        die "Cannot publish the $pair model"
    fi
    rm -rf -- "$staging"
    rm -f "$archive"
}

download_model en_ru 10 55
download_model ru_en 55 98

progress 100 "Offline translator installed"
echo "DONE"
