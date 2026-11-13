"""Install the publisher's pinned ONNX reranker into an existing Lens bundle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import urllib.request

SOURCE = {"repo": "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1",
          "revision": "1427fd652930e4ba29e8149678df786c240d8825", "license": "Apache-2.0"}
FILES = {
    "reranker.onnx": ("onnx/model.onnx", "3e9a03ed1e966f7c5288dd4230e3d6a9bf5e3a170a06f1f4241c5bca12c6487c", 470883696),
    "reranker-tokenizer.json": ("tokenizer.json", "62c24cdc13d4c9952d63718d6c9fa4c287974249e16b7ade6d5a85e7bbb75626", 17082660),
}


def install(output):
    output = Path(output)
    previous = (output / "manifest.json").read_bytes()
    manifest = json.loads(previous)
    # Adding a query-time model does not change existing document embeddings.
    manifest.setdefault("embedding_revision", hashlib.sha256(previous).hexdigest())
    total = sum(item[2] for item in FILES.values())
    done = 0
    with tempfile.TemporaryDirectory(prefix=".reranker-", dir=output.parent) as temporary:
        stage = Path(temporary)
        for name, (remote, expected, size) in FILES.items():
            target = output / name
            if target.is_file():
                with target.open("rb") as stream:
                    if hashlib.file_digest(stream, "sha256").hexdigest() == expected:
                        done += size
                        continue
            url = f"https://huggingface.co/{SOURCE['repo']}/resolve/{SOURCE['revision']}/{remote}"
            digest = hashlib.sha256()
            received = 0
            with urllib.request.urlopen(url, timeout=60) as response, (stage / name).open("wb") as stream:
                while block := response.read(4 * 1024 * 1024):
                    received += len(block)
                    if received > size:
                        raise ValueError("Reranker size mismatch")
                    stream.write(block)
                    digest.update(block)
                    print("LENS_PROGRESS " + json.dumps(dict(task="model-download", model="reranker",
                          unit="bytes", done=done + received, total=total)), flush=True)
            if received != size or digest.hexdigest() != expected:
                raise ValueError("Reranker checksum mismatch")
            done += received
        # Publish the manifest last. An interrupted download leaves the old bundle usable.
        for file in stage.iterdir():
            os.replace(file, output / file.name)
        manifest.setdefault("sources", {})["reranker"] = SOURCE
        manifest["files"].update({name: item[1] for name, item in FILES.items()})
        manifest["tokenizers"]["reranker"] = {"pad_id": 1, "pad_token": "<pad>"}
        pending = stage / "manifest.json"
        pending.write_text(json.dumps(manifest, indent=2) + "\n")
        os.replace(pending, output / "manifest.json")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    install(parser.parse_args().output)
