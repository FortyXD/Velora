"""Locate the helper built from this checkout for desktop integration tests."""
import os
from pathlib import Path
import subprocess
from functools import lru_cache

ROOT = Path(__file__).resolve().parents[1]

@lru_cache(maxsize=1)
def binary():
    if explicit := os.environ.get("VELORA_TEST_HELPER"):
        return explicit
    target = Path(os.environ.get("CARGO_TARGET_DIR", ROOT / "tools/target"))
    path = target / "debug/velora-helper"
    if not path.exists() or not path.with_name("velora-desktop-state").exists():
        subprocess.run(["cargo", "build", "--locked", "--manifest-path", str(ROOT / "tools/Cargo.toml"),
                        "-p", "velora-helper"], check=True)
    return str(path.resolve())
