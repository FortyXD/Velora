#!/usr/bin/env python3
"""Real Hyprland regression: duplicate titles, workspace changes and capture teardown."""
import asyncio
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

if not Path('/var/lib/velora-qemu-ready').exists():
    raise SystemExit('Only run inside QEMU, through in-session.py')
root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('previews', root / 'dots/.config/quickshell/ii/scripts/window-previews.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


async def main():
    processes = []
    events = []
    hashes = {}
    workspace = json.loads(subprocess.check_output(['hyprctl', '-j', 'activeworkspace']))['id']
    def receive(event):
        events.append(event)
        if event['event'] == 'frame':
            hashes.setdefault(event['id'], set()).add(hashlib.sha256(Path(event['path']).read_bytes()).hexdigest())
    module.emit = receive
    with tempfile.TemporaryDirectory(dir=Path('/run/user') / str(__import__('os').getuid())) as directory:
        broker = module.Broker(directory)
        try:
            for color in (41, 44):
                processes.append(subprocess.Popen(['foot', '--app-id=velora-capture-test', '--title=Duplicate title',
                    'sh', '-c', f"i=0; while :; do printf '\033[{color}m\033[2J\033[HFrame %s' \"$i\"; i=$((i+1)); sleep .15; done"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            targets = []
            for _ in range(50):
                targets = [c for c in json.loads(subprocess.check_output(['hyprctl', '-j', 'clients'])) if c['class'] == 'velora-capture-test']
                if len(targets) == 2: break
                await asyncio.sleep(.1)
            assert len(targets) == 2
            assert targets[0]['title'] == targets[1]['title']
            assert targets[0]['stableId'] != targets[1]['stableId']
            specs = [{'id': c['stableId'], 'live': True} for c in targets]
            await broker.set_windows(specs)
            await asyncio.sleep(1.2)
            assert all(len(hashes.get(s['id'], [])) >= 2 for s in specs)
            assert hashes[specs[0]['id']].isdisjoint(hashes[specs[1]['id']])
            subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.focus({workspace="9"})'], check=True, stdout=subprocess.DEVNULL)
            await asyncio.sleep(.3)
            subprocess.run(['hyprctl', 'dispatch', f'hl.dsp.focus({{workspace="{workspace}"}})'], check=True, stdout=subprocess.DEVNULL)
            # Close a real source while a request can be in flight, then unsubscribe it.
            processes[0].terminate()
            await asyncio.sleep(.02)
            survivor = next(s for s, c in zip(specs, targets) if c['pid'] != processes[0].pid)
            await broker.set_windows([survivor])
            closed = next(s['id'] for s in specs if s is not survivor)
            count = sum(e.get('id') == closed for e in events)
            await asyncio.sleep(.3)
            assert sum(e.get('id') == closed for e in events) == count
            await broker.set_windows([])
            assert not list(Path(directory).iterdir())
            # A new hover in energy-saving mode produces exactly one real frame.
            start = len(events)
            await broker.set_windows([{**survivor, 'live': False}])
            await asyncio.sleep(.8)
            assert sum(e['event'] == 'frame' for e in events[start:]) == 1
            await broker.set_windows([])
            assert not list(Path(directory).iterdir())
            result = {'duplicate_titles': True, 'separate_stable_ids': [s['id'] for s in specs],
                      'workspace_switch': True, 'close_during_capture': True, 'still_frame_count': 1,
                      'cleanup': True, 'frames': sum(e['event'] == 'frame' for e in events)}
            (Path.home() / 'evidence/preview-lifecycle.json').write_text(json.dumps(result, indent=2))
            print(json.dumps(result))
        finally:
            await broker.close()
            for process in processes:
                if process.poll() is None: process.terminate()
                process.wait(timeout=5)
            subprocess.run(['hyprctl', 'dispatch', f'hl.dsp.focus({{workspace="{workspace}"}})'], stdout=subprocess.DEVNULL)


asyncio.run(main())
