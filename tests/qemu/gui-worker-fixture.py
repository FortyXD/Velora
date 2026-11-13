"""Guest-only hold/prompt UI fixtures; no system packages or authorization policy are changed."""
from pathlib import Path
import sys
import shutil

assert Path('/var/lib/velora-qemu-ready').exists()
sys.path.insert(0, str(Path.home() / 'Velora/scripts'))
import update_gui

mode = sys.argv[1]
binary = Path.home() / ('gui-' + mode + '-fixture')
if mode == 'hold':
    state = update_gui.directory()
    for name in ('gui-update.log', 'gui-update.json'):
        if (state / name).exists():
            shutil.copy2(state / name, Path.home() / 'evidence' / ('real-' + name))
    binary.write_text('#!/bin/sh\nprintf "::velora-phase installing\\nBackground test running\\n"\nsleep 45\nprintf "Background test complete\\n"\n')
elif mode == 'prompt':
    # Preview the exact askpass UI and cancellation path without changing sudoers.
    binary.write_text('#!/bin/sh\nexec "$SUDO_ASKPASS" >/dev/null\n')
else:
    raise SystemExit('unknown fixture')
binary.chmod(0o700)
update_gui.start(binary)
