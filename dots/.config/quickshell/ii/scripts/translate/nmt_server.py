#!/usr/bin/env python3
"""Offline English <-> Russian translator for the sidebar Translator tab.

Reads one JSON request per line on stdin:   {"id": 1, "text": "...", "src": "en", "tgt": "ru"}
Writes one JSON reply per line on stdout:   {"id": 1, "text": "..."}  or  {"id": 1, "error": "..."}

Each direction's model is loaded on first use. The process exits when stdin closes;
the shell stops it after a short idle period, so it only uses memory while you translate.
"""
import json
import os
import re
import sys

MODELS_DIR = os.path.join(
    os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "folis", "translate", "models"
)
THREADS = 2  # Short, cool bursts instead of waking every core
SENTENCE_END = re.compile(r"(?<=[.!?…])\s+")

_models = {}


def load(pair):
    if pair not in _models:
        import ctranslate2
        import sentencepiece

        path = os.path.join(MODELS_DIR, pair)
        if not os.path.isdir(path):
            raise RuntimeError(f"No model for {pair}")
        translator = ctranslate2.Translator(
            os.path.join(path, "model"), device="cpu", compute_type="int8", inter_threads=1, intra_threads=THREADS
        )
        tokenizer = sentencepiece.SentencePieceProcessor(model_file=os.path.join(path, "sentencepiece.model"))
        _models[pair] = (translator, tokenizer)
    return _models[pair]


def translate(text, src, tgt):
    translator, tokenizer = load(f"{src}_{tgt}")
    # Translate sentence by sentence (the models are trained on sentences), keep line breaks
    lines = text.split("\n")
    sentences_per_line = [SENTENCE_END.split(line.strip()) if line.strip() else [] for line in lines]
    sentences = [s for line in sentences_per_line for s in line]
    if not sentences:
        return ""
    results = translator.translate_batch(
        [tokenizer.encode(s, out_type=str) for s in sentences],
        beam_size=2,
        max_batch_size=16,
        replace_unknowns=True,
    )
    translated = iter(tokenizer.decode(r.hypotheses[0]) for r in results)
    return "\n".join(" ".join(next(translated) for _ in line) for line in sentences_per_line)


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        request_id = None
        try:
            request = json.loads(line)
            request_id = request.get("id")
            reply = {"id": request_id, "text": translate(request["text"], request["src"], request["tgt"])}
        except Exception as e:  # Report and keep serving
            reply = {"id": request_id, "error": str(e)}
        sys.stdout.write(json.dumps(reply, ensure_ascii=False) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
