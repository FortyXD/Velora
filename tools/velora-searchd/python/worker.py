"""Offline Lens inference and bounded extraction. Protocol data stays on pipes."""
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import resource
import subprocess
import sys

# Limits also cover the decoder/OCR subprocesses. No untrusted executable is run.
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
resource.setrlimit(resource.RLIMIT_FSIZE, (32 * 1024 * 1024,) * 2)
resource.setrlimit(resource.RLIMIT_NOFILE, (128, 128))
CPU_THREADS = len(os.sched_getaffinity(0))
THREADS = max(1, min(CPU_THREADS, int(os.environ.get("VELORA_LENS_THREADS", "2"))))
os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", OMP_NUM_THREADS=str(THREADS))


def command(args, data=None, timeout=25):
    result = subprocess.run(args, input=data, capture_output=True, timeout=timeout, check=True)
    if len(result.stdout) > 16 * 1024 * 1024:
        raise ValueError("Decoder output limit")
    return result.stdout


def picture(raw):
    from PIL import Image, ImageOps, ImageStat
    Image.MAX_IMAGE_PIXELS = 40_000_000
    im = ImageOps.exif_transpose(Image.open(io.BytesIO(raw))).convert("RGB")
    im.thumbnail((1280, 1280))
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    png = buf.getvalue()
    try:
        text = command(["tesseract", "stdin", "stdout", "-l", "rus+eng"], png).decode("utf-8", "replace")[:16000]
    except (subprocess.SubprocessError, OSError):
        text = ""
    im.thumbnail((224, 224))
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    # Average hash is only a duplicate filter, never the search representation.
    values = list(im.resize((8, 8)).convert("L").getdata())
    avg = sum(values) / len(values)
    fingerprint = sum((v >= avg) << i for i, v in enumerate(values))
    return {"text": text, "image": base64.b64encode(buf.getvalue()).decode(), "hash": fingerprint,
            "color": ImageStat.Stat(im.resize((8, 8))).mean}


def extract(kind):
    resource.setrlimit(resource.RLIMIT_AS, (1536 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (110, 110))
    if kind == "pdf":
        return {"chunks": [{"text": command(["pdftotext", "-f", "1", "-l", "200", "/input", "-"]).decode("utf-8", "replace")[:128000]}]}
    if kind == "photo":
        if Path("/input").stat().st_size > 64 * 1024 * 1024:
            raise ValueError("Image too large")
        return {"chunks": [picture(Path("/input").read_bytes())]}
    probe = json.loads(command(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", "/input"]))
    duration = float(probe["format"]["duration"])
    if not 0 < duration <= 24 * 3600:
        raise ValueError("Unsupported video duration")
    # A resumable batch of at most twelve frames keeps each isolated job bounded.
    offset = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    chunks = []
    previous = None
    for timestamp in range(offset, min(int(duration) + 1, offset + 120), 10):
        raw = command(["ffmpeg", "-nostdin", "-v", "error", "-threads", "1", "-ss", str(timestamp), "-i", "/input", "-frames:v", "1", "-vf", "scale=1280:1280:force_original_aspect_ratio=decrease", "-f", "image2pipe", "-vcodec", "png", "-threads", "1", "pipe:1"])
        if not raw:
            continue
        item = picture(raw)
        signature = (item.pop("hash"), item.pop("color"), " ".join(item["text"].split()))
        # Similar grayscale shapes can have completely different colors or slide text.
        if (previous is not None and (previous[0] ^ signature[0]).bit_count() <= 3
                and max(abs(a - b) for a, b in zip(previous[1], signature[1])) <= 8
                and previous[2] == signature[2]):
            continue
        previous = signature
        item["timestamp"] = timestamp
        chunks.append(item)
    return {"chunks": chunks, "next": offset + 120 if offset + 120 < duration else None}


class Models:
    def __init__(self):
        self.sessions = {}
        self.tokenizers = {}
        self.root = Path("/models")
        manifest = json.loads((self.root / "manifest.json").read_text())
        self.manifest = manifest
        # Private, bounded in-memory path vectors; discarded with the worker on lock.
        from collections import OrderedDict
        self.metadata_cache = OrderedDict()

    def session(self, name):
        import onnxruntime as ort
        ort.disable_telemetry_events()
        if name not in self.sessions:
            relative = f"{name}.onnx"
            expected = self.manifest["files"][relative]
            path = self.root / relative
            with path.open("rb") as stream:
                actual = hashlib.file_digest(stream, "sha256").hexdigest()
            if actual != expected:
                raise ValueError("Model checksum mismatch")
            options = ort.SessionOptions()
            options.intra_op_num_threads = THREADS
            options.inter_op_num_threads = 1
            self.sessions[name] = ort.InferenceSession(str(path), options, providers=["CPUExecutionProvider"])
        return self.sessions[name]

    def tokenizer(self, name):
        from tokenizers import Tokenizer
        if name not in self.tokenizers:
            relative = f"{name}-tokenizer.json"
            raw = (self.root / relative).read_bytes()
            if hashlib.sha256(raw).hexdigest() != self.manifest["files"][relative]:
                raise ValueError("Tokenizer checksum mismatch")
            tok = Tokenizer.from_str(raw.decode())
            length = {"e5": 512, "siglip": 64, "reranker": 384}[name]
            tok.enable_truncation(max_length=length)
            tok.enable_padding(length=length if name == "siglip" else None,
                               pad_id=self.manifest["tokenizers"][name]["pad_id"],
                               pad_token=self.manifest["tokenizers"][name]["pad_token"])
            self.tokenizers[name] = tok
        return self.tokenizers[name]

    def text(self, texts, name="e5", query=False):
        import numpy as np
        if name == "e5":
            texts = [("query: " if query else "passage: ") + t for t in texts]
        elif query:
            texts = [t.lower() for t in texts]
        tokens = self.tokenizer(name).encode_batch(texts)
        data = {"input_ids": np.asarray([t.ids for t in tokens], dtype=np.int64),
                "attention_mask": np.asarray([t.attention_mask for t in tokens], dtype=np.int64)}
        session = self.session(name + "-text")
        return session.run(None, {x.name: data[x.name] for x in session.get_inputs()})[0].tolist()

    def images(self, images):
        import numpy as np
        from PIL import Image
        arrays = []
        for encoded in images:
            im = Image.open(io.BytesIO(base64.b64decode(encoded))).convert("RGB")
            im = im.resize((224, 224), resample=Image.Resampling.BICUBIC)
            arrays.append(((np.asarray(im, dtype=np.float32) / 255.0 - 0.5) / 0.5).transpose(2, 0, 1))
        return self.session("siglip-image").run(None, {"pixel_values": np.stack(arrays)})[0].tolist()

    def call(self, req):
        method = req["method"]
        if method == "metadata":
            import numpy as np
            documents = req["documents"]
            query = np.asarray(req["query_vector"], dtype=np.float32)
            if len(documents) > 32 or any(len(d) > 12000 for d in documents) or query.shape != (384,):
                raise ValueError("Metadata comparison limit exceeded")
            missing = list(dict.fromkeys(d for d in documents if d not in self.metadata_cache))
            for start in range(0, len(missing), 8):
                batch = missing[start:start + 8]
                self.metadata_cache.update(zip(batch, self.text(batch)))
            vectors = [self.metadata_cache[d] for d in documents]
            for d in documents:
                self.metadata_cache.move_to_end(d)
            while len(self.metadata_cache) > 256:
                self.metadata_cache.popitem(last=False)
            return {"scores": (np.asarray(vectors) @ query).tolist() if vectors else []}
        if method == "rerank":
            import numpy as np
            documents = req["documents"]
            if len(documents) > 32 or len(req["text"]) > 2048 or any(len(t) > 12000 for t in documents):
                raise ValueError("Reranking limit exceeded")
            if "reranker.onnx" not in self.manifest["files"]:
                return {"available": False}
            tokenizer = self.tokenizer("reranker")
            session = self.session("reranker")
            scores = []
            # Bounded batches keep interactive memory below whole-index inference.
            for start in range(0, len(documents), 4):
                tokens = tokenizer.encode_batch([(req["text"], doc) for doc in documents[start:start + 4]])
                data = {"input_ids": np.asarray([t.ids for t in tokens], dtype=np.int64),
                        "attention_mask": np.asarray([t.attention_mask for t in tokens], dtype=np.int64),
                        "token_type_ids": np.asarray([t.type_ids for t in tokens], dtype=np.int64)}
                scores.extend(session.run(None, {x.name: data[x.name] for x in session.get_inputs()})[0].reshape(-1).tolist())
            return {"available": True, "scores": scores}
        if method == "query":
            out = {}
            if req.get("textual", True):
                texts = [req["text"]]
                if req.get("application_text"):
                    texts.append(req["application_text"])
                vectors = self.text(texts, query=True)
                out["text"] = vectors[0]
                if len(vectors) > 1:
                    out["application"] = vectors[1]
            if req.get("visual", True):
                out["visual"] = self.text([req["text"]], "siglip", True)[0]
            return out
        if method == "encode":
            import numpy as np
            texts = req.get("texts", [])
            images = req.get("images", [])
            if len(texts) > 16 or len(images) > 12:
                raise ValueError("Batch limit exceeded")
            pack = lambda vectors: [base64.b64encode(np.asarray(v, dtype="<f2").tobytes()).decode() for v in vectors]
            return {"text": pack(self.text(texts)) if texts else [], "visual": pack(self.images(images)) if images else []}
        raise ValueError("Unknown method")


if __name__ == "__main__":
    if sys.argv[1] == "extract":
        try:
            print(json.dumps(extract(sys.argv[2])))
        except Exception:
            print(json.dumps({"error": "Media extraction failed"}))
            sys.exit(1)
    else:
        models = None
        for line in sys.stdin:
            try:
                if len(line) > 16 * 1024 * 1024:
                    raise ValueError("Request limit exceeded")
                if models is None:
                    models = Models()
                print(json.dumps(models.call(json.loads(line))), flush=True)
            except Exception:
                # Neither paths nor document contents are exposed through errors.
                print(json.dumps({"error": "Model unavailable or inference failed"}), flush=True)
