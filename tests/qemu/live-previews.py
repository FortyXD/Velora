#!/usr/bin/env python3
"""Guest compositor integration: real grim frames, no capture mocks."""
import asyncio
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

if not Path('/var/lib/velora-qemu-ready').exists():
    raise SystemExit('Only run inside the QEMU guest')
root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('previews', root / 'dots/.config/quickshell/ii/scripts/window-previews.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


async def main():
    version = json.loads(subprocess.check_output(['hyprctl', '-j', 'version']))
    assert version['version'] == '0.57.0', version
    clients = json.loads(subprocess.check_output(['hyprctl', '-j', 'clients']))
    target = next(client for client in clients if 'Quick Look' in client['title'])
    targets = clients[:2]
    assert target in targets
    events = []
    hashes = set()
    evidence = Path.home() / 'evidence'
    def receive(event):
        events.append(event)
        if event['event'] == 'frame' and event['id'] == target['stableId']:
            path = Path(event['path'])
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest not in hashes and len(hashes) < 3:
                shutil.copy2(path, evidence / f'live-window-frame-{len(hashes)}.png')
            hashes.add(digest)
    module.emit = receive
    with tempfile.TemporaryDirectory() as directory:
        broker = module.Broker(directory)
        await broker.set_windows([{'id': client['stableId'], 'live': True, 'width': 480, 'height': 320} for client in targets])
        await asyncio.sleep(2.5)
        await broker.set_windows([])
        count = len(events)
        await asyncio.sleep(.3)
        assert len(events) == count, 'late frame emitted after unsubscribe'
        assert not list(Path(directory).iterdir()), 'frame files leaked'
        await broker.close()
    result = {'version': version, 'frames': sum(e['event'] == 'frame' for e in events),
              'distinct_frames': len(hashes), 'windows': len(targets),
              'errors': [e for e in events if e['event'] == 'error']}
    (evidence / 'live-previews.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result))
    assert len(hashes) >= 2, 'expected changing pixels from the animated GIF'


asyncio.run(main())
