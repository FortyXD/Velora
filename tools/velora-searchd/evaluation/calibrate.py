"""Offline relevance calibration on synthetic dev projects; test projects stay held out.

Run with the installed Lens Python. No personal files or index are opened.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import numpy as np


def main(models, output):
    directory = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("lens_worker", directory.parent / "python/worker.py")
    worker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(worker)
    model = worker.Models.__new__(worker.Models)
    model.root = Path(models)
    model.manifest = json.loads((model.root / "manifest.json").read_text())
    model.sessions, model.tokenizers = {}, {}
    corpus = json.loads((directory / "corpus.json").read_text())
    texts = [c["text"] for c in corpus]
    documents = [f"File: corpus/{c['id']}/README.md\n{c['text']}" for c in corpus]
    vectors = np.array(model.text(texts))
    queries = []
    seen = set()
    for line in (directory / "queries.jsonl").read_text().splitlines():
        item = json.loads(line)
        if item["category"] != "semantic":
            continue
        query = re.sub(r"^(?:(?:найди|папка|папку|проект|folder|project|где)\s+)+", "", item["query"])
        if query not in seen:
            queries.append((query, item["expected"][0], item["split"]))
            seen.add(query)
    queries += [(q, None, "dev") for q in [
        "medieval sculpture restoration", "stellar spectroscopy", "медицинская карта пациента", "правила игры в шахматы"]]
    queries += [(q, None, "test") for q in [
        "japanese tax return 2035", "швейная выкройка пиджака", "violin bow repair", "расписание полетов на марс"]]
    records = []
    for query, expected, split in queries:
        vector = np.array(model.text([query], query=True)[0])
        cosine = vectors @ vector
        scores = model.call({"method": "rerank", "text": query, "documents": documents})["scores"]
        records.append(dict(query=query, expected=expected, split=split, cosine=cosine.tolist(), logits=scores))
    # Model scores and the dense margin over other documents, no query-specific words.
    train = [r for r in records if r["split"] == "dev"]
    def features(r):
        return [[c, l, c - max(r["cosine"][:i] + r["cosine"][i+1:])] for i, (c,l) in enumerate(zip(r["cosine"], r["logits"]))]
    x = np.array([row for r in train for row in features(r)])
    y = np.array([float(doc["id"] == r["expected"]) for r in train for doc in corpus])
    mean, scale = x.mean(0), x.std(0)
    design = np.column_stack([np.ones(len(x)), (x - mean) / scale])
    weights = np.zeros(4)
    for _ in range(6000):
        p = 1 / (1 + np.exp(-np.clip(design @ weights, -40, 40)))
        gradient = design.T @ (p - y) / len(y)
        gradient[1:] += 0.002 * weights[1:]
        weights -= 0.1 * gradient
    coefficients = weights[1:] / scale
    intercept = weights[0] - coefficients @ mean
    probabilities = 1 / (1 + np.exp(-np.clip(design @ weights, -40, 40)))
    def quality(threshold):
        positive = probabilities >= threshold
        tp, fp, fn = ((positive & (y == 1)).sum(), (positive & (y == 0)).sum(), ((~positive) & (y == 1)).sum())
        return 1.25 * tp / max(1, 1.25 * tp + fp + 0.25 * fn)
    # Prefer the more conservative boundary when dev F0.5 is tied.
    threshold = max(np.linspace(0.05, 0.95, 181), key=lambda t: (quality(t), t))
    result = dict(intercept=float(intercept), cosine=float(coefficients[0]), cross_encoder=float(coefficients[1]), margin=float(coefficients[2]),
                  threshold=float(threshold), dataset="synthetic-v1 dev; three-feature logistic regression, L2=0.002")
    metrics = {}
    for split in ["dev", "test"]:
        tp = fp = fn = top = count = rejected = absent = 0
        failures = []
        for r in (r for r in records if r["split"] == split):
            raw = intercept + np.array(features(r)) @ coefficients
            scores = 1 / (1 + np.exp(-np.clip(raw, -40, 40)))
            selected = np.flatnonzero(scores >= threshold)
            selected = sorted(selected, key=lambda i: -scores[i])
            if r["expected"] is None:
                absent += 1
                rejected += not selected
            else:
                count += 1
                top += bool(selected and corpus[selected[0]]["id"] == r["expected"])
            for i, doc in enumerate(corpus):
                expected = doc["id"] == r["expected"]
                found = i in selected
                tp += expected and found
                fp += found and not expected
                fn += expected and not found
            if (r["expected"] is None and selected) or (r["expected"] is not None and (not selected or corpus[selected[0]]["id"] != r["expected"])):
                failures.append(dict(query=r["query"], expected=r["expected"], found=[corpus[i]["id"] for i in selected]))
        metrics[split] = dict(precision=tp/max(1,tp+fp), recall=tp/max(1,tp+fn), top1=top/max(1,count),
                              no_match_rejected=rejected, no_match_queries=absent, failures=failures)
    Path(output).write_text(json.dumps(result, indent=2) + "\n")
    Path(str(output) + ".evaluation.json").write_text(json.dumps(dict(metrics=metrics, records=records), ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(dict(model=result, metrics=metrics), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    main(args.models, args.output)
