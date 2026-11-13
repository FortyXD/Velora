#!/usr/bin/env python3
"""Compare real capture pipelines inside the regression guest; CPU includes grim children."""
import argparse
import asyncio
import importlib.util
import json
from pathlib import Path
import resource
import statistics
import subprocess
import time

if not Path('/var/lib/velora-qemu-ready').exists():
    raise SystemExit('Only run inside QEMU, through in-session.py')
parser = argparse.ArgumentParser()
parser.add_argument('before', type=Path)
parser.add_argument('after', type=Path)
args = parser.parse_args()
modules = {}
for name, path in (('before', args.before), ('after', args.after)):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    modules[name] = module

def clients():
    return json.loads(subprocess.check_output(['hyprctl', '-j', 'clients']))

def cpu():
    return sum(r.ru_utime + r.ru_stime for r in
               (resource.getrusage(resource.RUSAGE_SELF), resource.getrusage(resource.RUSAGE_CHILDREN)))

async def measure(module, targets):
    import tempfile
    capture = module.Capture() if hasattr(module, 'Capture') else module.capture
    calls, durations, events, writes = [], [], [], []
    seen = {}
    async def counted(spec, path):
        started = time.monotonic()
        result = await capture(spec, path)
        calls.append(started)
        durations.append((time.monotonic() - started) * 1000)
        if path.exists():
            stamp = path.stat().st_mtime_ns
            if seen.get(path) != stamp:
                writes.append(str(path))
            seen[path] = stamp
        return result
    module.emit = lambda event: events.append((time.monotonic(), event))
    with tempfile.TemporaryDirectory() as directory:
        broker = module.Broker(directory, counted)
        specifications = [{'id':c['stableId'], 'width':280, 'height':180, 'live':True} for c in targets]
        await broker.set_windows(specifications)
        await asyncio.sleep(.6)  # exclude initial calibration and imports
        calls.clear(); durations.clear(); events.clear(); writes.clear()
        started, used = time.monotonic(), cpu()
        await asyncio.sleep(4)
        elapsed, used = time.monotonic() - started, cpu() - used
        frames = [e for _, e in events if e['event'] == 'frame']
        errors = [e for _, e in events if e['event'] == 'error']
        maximum_files = len(list(Path(directory).glob('*.png')))
        await broker.close()
        assert not list(Path(directory).iterdir()), 'temporary frames leaked'
    assert not errors, errors
    return {'seconds':round(elapsed,3), 'capture_calls':len(calls), 'published_frames':len(frames),
            'png_writes':len(writes), 'cpu_seconds':round(used,4), 'cpu_percent_of_one_core':round(used/elapsed*100,2),
            'capture_ms_median':round(statistics.median(durations),2),
            'capture_ms_p95':round(sorted(durations)[int(len(durations)*.95)],2), 'files':maximum_files}

async def main():
    result = {'hyprland':json.loads(subprocess.check_output(['hyprctl','-j','version'])), 'cases':{}}
    for label, animated, count in (('static', False, 1), ('animated', True, 1), ('two_animated', True, 2)):
        processes = []
        try:
            for number in range(count):
                body = "printf '\033[?25l\033[44m\033[2J\033[HStatic preview'; sleep 90"
                if animated:
                    body = "i=0; printf '\033[?25l\033[44m\033[2J'; while :; do printf '\033[HFrame %08d\nVelora capture benchmark' \"$i\"; i=$((i+1)); sleep .03; done"
                processes.append(subprocess.Popen(['foot','--app-id=velora-preview-benchmark','--title=Preview benchmark',
                                                    'sh','-c',body], stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
            targets = []
            for _ in range(50):
                targets = [c for c in clients() if c['class']=='velora-preview-benchmark']
                if len(targets)==count: break
                await asyncio.sleep(.1)
            assert len(targets)==count
            if count == 1:
                subprocess.run(['hyprctl','dispatch','hl.dsp.window.fullscreen({mode="fullscreen",action="toggle",window="address:'+targets[0]['address']+'"})'], check=True,stdout=subprocess.DEVNULL)
            await asyncio.sleep(.5)
            targets=[c for c in clients() if c['class']=='velora-preview-benchmark']
            result['cases'][label]={'window_sizes':[c['size'] for c in targets]}
            for name, module in modules.items():
                result['cases'][label][name] = await measure(module, targets)
        finally:
            for process in processes:
                process.terminate()
                process.wait(timeout=5)
        await asyncio.sleep(.3)
    path=Path.home()/'evidence/preview-performance.json'
    path.write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))

asyncio.run(main())
