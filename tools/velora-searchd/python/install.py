"""Install Lens models into a private environment; never change the system Python."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import venv


def run_progress(command, stage, progress):
    """Read machine progress from pip/exporter while preserving diagnostics in the setup log."""
    progress(stage)
    with subprocess.Popen(list(map(str, command)), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, bufsize=1, env={**os.environ, "PYTHONUNBUFFERED": "1"}) as child:
        for line in child.stdout:
            print(line, end="", flush=True)
            if line.startswith("LENS_PROGRESS "):
                event = json.loads(line[len("LENS_PROGRESS "):])
                progress(stage, **event)
            elif match := re.fullmatch(r"Progress (\d+) of (\d+)\s*", line):
                done, total = map(int, match.groups())
                progress(stage, unit="bytes", done=done, total=total or None, task="component-download")
            elif line.startswith(("Downloading ", "Using cached ", "Installing collected packages:")):
                progress(stage, task="installing" if line.startswith("Installing") else "component-download")
        if child.wait() != 0:
            raise subprocess.CalledProcessError(child.returncode, command)


def install(directory, progress=lambda _phase, **_details: None):
    source = Path(__file__).resolve().parent
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    environment = directory / "venv"
    progress("runtime")
    if not (environment / "bin/python").exists():
        venv.EnvBuilder(with_pip=True).create(environment)
    python = environment / "bin/python"
    run_progress([python, "-m", "pip", "install", "--progress-bar", "raw", "--disable-pip-version-check", "-r", source / "requirements.txt"], "runtime", progress)
    # Export tooling is temporary: neither PyTorch nor Transformers stays in the runtime.
    progress("export-tools")
    with tempfile.TemporaryDirectory(prefix="lens-model-build-") as temporary:
        build = Path(temporary)
        venv.EnvBuilder(with_pip=True).create(build / "venv")
        exporter = build / "venv/bin/python"
        run_progress([exporter, "-m", "pip", "install", "--progress-bar", "raw", "--index-url", "https://download.pytorch.org/whl/cpu", "torch==2.14.1"], "export-tools", progress)
        run_progress([exporter, "-m", "pip", "install", "--progress-bar", "raw", "--disable-pip-version-check", "-r", source / "export-requirements.txt"], "export-tools", progress)
        run_progress([exporter, source / "prepare_models.py", "--output", directory / "models", "--cache", build / "cache"], "models", progress)
    run_progress([python, source / "reranker.py", "--output", directory / "models"], "models", progress)
    progress("verifying")
    binary = Path.home() / ".local/bin/velora-searchd"
    if not binary.is_file():
        binary = Path("/usr/bin/velora-searchd")
    subprocess.run([binary, "check-models"], check=True)
    print("Lens models are ready.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "velora-lens")
    args = parser.parse_args()
    install(args.directory)
