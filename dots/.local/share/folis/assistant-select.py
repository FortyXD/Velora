#!/usr/bin/env python3
"""Pass an explicit Dolphin selection to the running shell without shell interpolation."""
import json
from pathlib import Path
import subprocess
import sys

paths = [str(Path(p).absolute()) for p in sys.argv[1:101]]
subprocess.run(['qs', '-c', 'ii', 'ipc', 'call', 'assistant', 'select', json.dumps(paths)], check=True)
