#!/usr/bin/env python3
"""Own just the Ollama server started for sidebar chat, including its children."""
import os
from pathlib import Path
import signal
import subprocess
import sys


def main():
    environment = {**os.environ, "OLLAMA_HOST":"127.0.0.1:11434", "OLLAMA_NO_CLOUD":"1",
                   "OLLAMA_NOPRUNE":"1", "OLLAMA_NUM_PARALLEL":"1", "OLLAMA_MAX_LOADED_MODELS":"1"}
    if sys.argv[1:] != ["gpu"]:
        environment.update(CUDA_VISIBLE_DEVICES="-1", ROCR_VISIBLE_DEVICES="-1", OLLAMA_VULKAN="0")
    if not environment.get("OLLAMA_MODELS"):
        for folder in [Path.home()/".ollama/models", Path("/var/lib/ollama"), Path("/usr/share/ollama/.ollama/models")]:
            if (folder/"manifests").is_dir():
                environment["OLLAMA_MODELS"] = str(folder)
                break
    process = None
    def stop(_signal, _frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        process = subprocess.Popen(["ollama", "serve"], env=environment, start_new_session=True,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return process.wait()
    except FileNotFoundError:
        return 127
    finally:
        if process and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


if __name__ == "__main__":
    sys.exit(main())
