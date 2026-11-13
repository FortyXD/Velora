"""Export pinned public models to self-contained, verified ONNX artifacts.

Run in an export environment with export-requirements.txt installed. This is the
only networked part of Lens; the daemon and inference worker never download data.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import threading
import time

os.environ.update(HF_HUB_DISABLE_IMPLICIT_TOKEN="1", HF_HUB_DISABLE_TELEMETRY="1", DO_NOT_TRACK="1")

SOURCES = {
    "e5": {"repo": "intfloat/multilingual-e5-small", "revision": "614241f622f53c4eeff9890bdc4f31cfecc418b3", "license": "MIT"},
    "siglip": {"repo": "google/siglip2-base-patch16-224", "revision": "75de2d55ec2d0b4efc50b3e9ad70dba96a7b2fa2", "license": "Apache-2.0"},
}


def report(**value):
    print("LENS_PROGRESS " + json.dumps(value), flush=True)


def download_model(source, name, number, cache):
    """Use actual byte callbacks, not the allocated size of partially downloaded files."""
    from huggingface_hub import hf_hub_download, snapshot_download
    from tqdm import tqdm
    patterns = ["*.json", "*.safetensors", "*.model", "tokenizer.*", "vocab.txt", "merges.txt"]
    options = dict(repo_id=source["repo"], revision=source["revision"], cache_dir=cache, token=False)
    common = dict(model=name, model_number=number, models_total=len(SOURCES), task="model-download")
    report(**common)
    files = snapshot_download(**options, allow_patterns=patterns, ignore_patterns=["*/*"], dry_run=True)
    total = sum(file.file_size for file in files) if all(file.file_size is not None for file in files) else None
    completed = 0
    transferred = 0
    current_bytes = 0
    current_transfer = 0
    last_emit = 0.0
    lock = threading.RLock()

    class ProgressBar(tqdm):
        def display(self, msg=None, pos=None):
            nonlocal last_emit, current_bytes, current_transfer
            if getattr(self, "unit", None) != "B":
                return
            with lock:
                if "downloading bytes" in self.desc.lower():
                    current_transfer = int(self.n)
                else:
                    current_bytes = int(self.n)
                    if "reconstructing file" not in self.desc.lower():
                        # Plain HTTP bytes are received directly; exclude a resumed prefix.
                        current_transfer = max(0, int(self.n) - int(self.initial))
                now = time.monotonic()
                if now - last_emit < 0.5:
                    return
                last_emit = now
                # Xet network bytes may be compressed/deduplicated: only reconstruction
                # bytes share the known file-size denominator.
                done = completed + current_bytes
                report(**common, unit="bytes", done=min(total, done) if total is not None else done,
                       total=total, transferred=transferred + current_transfer)

    for file in files:
        current_bytes = current_transfer = 0
        path = hf_hub_download(**options, filename=file.filename, tqdm_class=ProgressBar)
        completed += Path(path).stat().st_size
        transferred += current_transfer
        report(**common, unit="bytes", done=completed, total=total, transferred=transferred)
    return snapshot_download(**options, allow_patterns=patterns, ignore_patterns=["*/*"], local_files_only=True)


def export_models(output, cache=None):
    import numpy as np
    import onnxruntime as ort
    import torch
    from transformers import AutoModel, AutoTokenizer
    torch.set_num_threads(2)

    class Text(torch.nn.Module):
        def __init__(self, model, mean_pool):
            super().__init__()
            self.model = model
            self.mean_pool = mean_pool

        def forward(self, input_ids, attention_mask):
            # SigLIP is trained with fixed-length padding and no padding attention mask.
            result = self.model(input_ids=input_ids, attention_mask=attention_mask if self.mean_pool else None, return_dict=True)
            if self.mean_pool:
                hidden = result.last_hidden_state * attention_mask.unsqueeze(-1)
                values = hidden.sum(1) / attention_mask.sum(1, keepdim=True).clamp(min=1)
            else:
                values = result.pooler_output
            return torch.nn.functional.normalize(values, dim=-1)

    class Image(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model

        def forward(self, pixel_values):
            return torch.nn.functional.normalize(self.model(pixel_values=pixel_values, return_dict=True).pooler_output, dim=-1)

    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".lens-export-", dir=output.parent) as temporary:
        stage = Path(temporary)
        manifest = {"format": 1, "sources": SOURCES, "precision": "fp32", "files": {}, "tokenizers": {}}
        verified = 0
        def save(module, inputs, names, name, sequence=False):
            nonlocal verified
            module.eval()
            axes = {n: {0: "batch"} for n in names}
            if sequence:
                axes = {n: {0: "batch", 1: "sequence"} for n in names}
            axes["embedding"] = {0: "batch"}
            path = stage / (name + ".onnx")
            with torch.inference_mode():
                expected = module(*inputs).numpy()
                torch.onnx.export(module, inputs, str(path), input_names=names, output_names=["embedding"],
                                  dynamic_axes=axes, opset_version=17, dynamo=False, external_data=False)
            options = ort.SessionOptions()
            options.intra_op_num_threads = 2
            session = ort.InferenceSession(str(path), options, providers=["CPUExecutionProvider"])
            supplied = dict(zip(names, [x.numpy() for x in inputs]))
            actual = session.run(None, {x.name: supplied[x.name] for x in session.get_inputs()})[0]
            np.testing.assert_allclose(actual, expected, rtol=2e-3, atol=2e-4)
            verified += 1
            report(task="model-export", model=name.split("-")[0], model_number=number, models_total=len(SOURCES), unit="parts", done=verified, total=3)
            print(f"Verified {name}", flush=True)

        for number, (name, source) in enumerate(SOURCES.items(), 1):
            print(f"Preparing {source['repo']} at {source['revision']}", flush=True)
            local = download_model(source, name, number, cache)
            report(task="model-export", model=name, model_number=number, models_total=len(SOURCES), unit="parts", done=verified, total=3)
            options = dict(local_files_only=True, trust_remote_code=False)
            tokenizer = AutoTokenizer.from_pretrained(local, **options)
            tokenizer.backend_tokenizer.save(str(stage / f"{name}-tokenizer.json"))
            manifest["tokenizers"][name] = {"pad_id": tokenizer.pad_token_id, "pad_token": tokenizer.pad_token}
            model = AutoModel.from_pretrained(local, attn_implementation="eager", use_safetensors=True, **options).eval()
            sample = tokenizer(["query: глубокое обучение", "query: deep learning"] if name == "e5" else ["собака на снегу", "a dog in the snow"],
                               return_tensors="pt", padding="max_length" if name == "siglip" else True,
                               truncation=True, max_length=64 if name == "siglip" else 512)
            text_model = model if name == "e5" else model.text_model
            save(Text(text_model, name == "e5"), (sample["input_ids"], sample.get("attention_mask", torch.ones_like(sample["input_ids"]))),
                 ["input_ids", "attention_mask"], name + "-text", sequence=name == "e5")
            if name == "siglip":
                torch.manual_seed(42)
                save(Image(model.vision_model), (torch.randn(1, 3, 224, 224),), ["pixel_values"], "siglip-image")
            del model, text_model
        report(task="model-package", unit="parts", done=verified, total=3)
        for path in stage.iterdir():
            with path.open("rb") as stream:
                manifest["files"][path.name] = hashlib.file_digest(stream, "sha256").hexdigest()
        (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        # Keep the previously working bundle if download/export/validation fails.
        backup = output.with_name(output.name + ".previous")
        if backup.exists():
            shutil.rmtree(backup)
        if output.exists():
            output.rename(backup)
        try:
            stage.rename(output)
        except BaseException:
            if backup.exists():
                backup.rename(output)
            raise
        if backup.exists():
            shutil.rmtree(backup)
    print(f"Model bundle ready: {output}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "velora-lens/models")
    parser.add_argument("--cache", type=Path)
    args = parser.parse_args()
    export_models(args.output, args.cache)
