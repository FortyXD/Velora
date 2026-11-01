"""Writable user configuration for an immutable system package."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile


def fingerprint(path):
    if path.is_symlink():
        return "link:" + os.readlink(path)
    if path.is_file():
        return hashlib.sha256(path.read_bytes()).hexdigest()
    return None


def runtime_target(destination, relative):
    """Reject paths whose parent redirects a runtime write or deletion outside it."""
    relative = Path(relative)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Invalid path in the runtime template manifest")
    target = destination / relative
    if not target.parent.resolve().is_relative_to(destination.resolve()):
        raise ValueError(f"A local directory symlink points outside the runtime: {target.parent}")
    return target


def sync_runtime(source, destination):
    """Refresh unchanged templates and keep local edits with incoming conflict copies."""
    manifest_path = destination / ".velora-runtime.json"
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    current = {}
    conflicts = []
    for name in ("dots", "home"):
        for path in sorted((source / name).rglob("*")):
            if path.is_dir() and not path.is_symlink():
                continue
            relative = path.relative_to(source)
            target = runtime_target(destination, relative)
            key = relative.as_posix()
            incoming_hash = fingerprint(path)
            local_hash = fingerprint(target)
            baseline = previous.get(key)
            if local_hash is not None and local_hash not in (baseline, incoming_hash):
                if incoming_hash != baseline:
                    incoming = runtime_target(destination, Path(".incoming") / relative)
                    incoming.parent.mkdir(parents=True, exist_ok=True)
                    if incoming.is_symlink():
                        incoming.unlink()
                    shutil.copy2(path, incoming, follow_symlinks=False)
                    conflicts.append(key)
                current[key] = baseline
                continue
            if target.is_dir() and not target.is_symlink():
                raise ValueError(f"A directory blocks a runtime file: {target}")
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.is_symlink():
                target.unlink()
            shutil.copy2(path, target, follow_symlinks=False)
            current[key] = incoming_hash
    # Remove only obsolete templates that the user has not edited.
    for key, baseline in previous.items():
        if key not in current:
            target = runtime_target(destination, key)
            if fingerprint(target) == baseline and (target.is_file() or target.is_symlink()):
                target.unlink()
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", prefix=".velora-runtime-", dir=destination,
                                     delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(json.dumps(current, indent=2) + "\n")
            output.close()
            os.replace(temporary, manifest_path)
        finally:
            temporary.unlink(missing_ok=True)
    return conflicts
