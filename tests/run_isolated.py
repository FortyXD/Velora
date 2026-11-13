#!/usr/bin/env python3
"""Run desktop tests with private processes, sockets, network, and device tree.
Build test binaries first; only tools/target and cache are writable.
Example: python3 tests/run_isolated.py -m unittest discover -s tests -p test_agent_pages.py -v
"""
import os
from pathlib import Path
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
gpu = sys.argv[1:2] == ['--gpu']
if gpu:
    del sys.argv[1]
for name in ['tools/target','cache']:(root/name).mkdir(parents=True,exist_ok=True)
command=['bwrap','--unshare-all','--die-with-parent','--new-session','--ro-bind','/','/',
         '--tmpfs','/run','--tmpfs','/tmp','--proc','/proc','--dev','/dev','--clearenv',
         '--setenv','PATH','/usr/bin:/bin','--setenv','HOME','/tmp/velora-test-home',
         '--dir','/tmp/velora-test-runtime','--setenv','XDG_RUNTIME_DIR','/tmp/velora-test-runtime','--setenv','LANG','C.UTF-8','--setenv','VELORA_TEST_PREBUILT','1',
         '--chdir',str(root)]
for name in ['tools/target','cache']:command+=['--bind',str(root/name),str(root/name)]
if gpu:
    # Explicit opt-in for inference tests; no display/input devices or host sockets.
    for device in Path('/dev').glob('nvidia*'):
        if device.is_char_device():
            command += ['--dev-bind', str(device), str(device)]
for name in ['VELORA_QML_SOURCE','OLLAMA_MODELS','VELORA_LIVE_MODEL','XDG_CONFIG_HOME']:
    if os.environ.get(name):command+=['--setenv',name,os.environ[name]]
command+=['--',*sys.argv[2:]] if sys.argv[1:2]==['--exec'] else ['--','/usr/bin/python3',*sys.argv[1:]]
sys.exit(subprocess.call(command))
