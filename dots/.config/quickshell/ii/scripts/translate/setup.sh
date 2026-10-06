#!/usr/bin/env bash
# Installs the offline English <-> Russian translator used by the sidebar Translator tab.
# - Python venv with ctranslate2 + sentencepiece (no torch)
# - Argos Translate 1.9 models, only the CTranslate2 model and SentencePiece files are kept
#
# Prints machine-readable lines for the UI:
#   PROGRESS <percent> <message>
#   DONE
#   ERROR <message>
# Safe to run again: finished steps are skipped.
set -uo pipefail

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/folis/translate"
VENV_DIR="$DATA_DIR/venv"
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

# 1. Python environment
if ! "$VENV_DIR/bin/python" -c 'import ctranslate2, sentencepiece' &>/dev/null; then
    progress 2 "Creating Python environment"
    rm -rf "$VENV_DIR"
    if command -v uv &>/dev/null; then
        uv venv --quiet --python /usr/bin/python3 "$VENV_DIR" &>/dev/null || die "Could not create the Python environment"
        progress 5 "Installing ctranslate2 and sentencepiece"
        uv pip install --quiet --python "$VENV_DIR/bin/python" ctranslate2 sentencepiece &>/dev/null \
            || die "Could not install ctranslate2/sentencepiece from PyPI"
    else
        /usr/bin/python3 -m venv "$VENV_DIR" || die "Could not create the Python environment"
        progress 5 "Installing ctranslate2 and sentencepiece"
        "$VENV_DIR/bin/pip" install --quiet ctranslate2 sentencepiece &>/dev/null \
            || die "Could not install ctranslate2/sentencepiece from PyPI"
    fi
fi
progress 10 "Python environment ready"

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
    local tmp
    tmp=$(mktemp -d "$DATA_DIR/extract.XXXXXX")
    if ! /usr/bin/python3 - "$archive" "$tmp" <<'EOF'
import os, sys, zipfile
archive, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive) as z:
    for name in z.namelist():
        parts = name.split("/", 1)
        if len(parts) < 2 or not parts[1]:
            continue
        rel = parts[1]
        if rel.startswith("model/") or rel in ("sentencepiece.model", "metadata.json"):
            if ".." in rel.split("/"):
                continue
            target = f"{out}/{rel}"
            if name.endswith("/"):
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(name) as src, open(target, "wb") as dst:
                dst.write(src.read())
EOF
    then
        rm -rf "$tmp"
        die "Could not unpack the $pair model"
    fi
    [[ -f "$tmp/model/model.bin" && -f "$tmp/sentencepiece.model" ]] || { rm -rf "$tmp"; die "Unexpected $pair model layout"; }
    rm -rf "$target"
    mv "$tmp" "$target"
    rm -f "$archive"
}

download_model en_ru 10 55
download_model ru_en 55 98

progress 100 "Offline translator installed"
echo "DONE"
