#!/usr/bin/env python3
"""Compare real capture pipelines inside the regression guest; CPU includes grim children."""
import argparse
import asyncio
import ctypes
import json
from pathlib import Path
import os
import shutil
import struct
import sys
import tempfile
import statistics
import subprocess
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from preview_broker import PreviewBroker


def clients():
    return json.loads(subprocess.check_output(['hyprctl', '-j', 'clients']))


def cpu(pid):
    # utime, stime, cutime and cstime, including completed grim children.
    fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    return sum(int(n) for n in fields[11:15]) / os.sysconf('SC_CLK_TCK')


def png_writes(fd):
    count = 0
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            return count
        offset = 0
        while offset < len(data):
            _, mask, _, length = struct.unpack_from('iIII', data, offset)
            offset += 16
            name = data[offset:offset + length].rstrip(b'\0')
            if mask & 0x4000:  # IN_Q_OVERFLOW
                raise RuntimeError('Lost preview publication events')
            if name.endswith(b'.png'):
                count += 1
            offset += length


async def measure(path, targets):
    events = []
    specs = [{'id': c['stableId'], 'width': 280, 'height': 180, 'live': True} for c in targets]
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        log = root / 'times'
        log.touch()
        # Both workers use the same instrumented grim and the guest compositor.
        grim = root / 'grim'
        grim.write_text('#!/bin/bash\nstart=$EPOCHREALTIME\n"$BENCH_GRIM" "$@"\nstatus=$?\n'
                        'printf "%s %s\\n" "$start" "$EPOCHREALTIME" >> "$BENCH_TIMES"\nexit "$status"\n')
        grim.chmod(0o755)
        env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", LC_NUMERIC='C',
                   BENCH_TIMES=str(log), BENCH_GRIM=shutil.which('grim'))
        command = [sys.executable, str(path)] if path.suffix == '.py' else [str(path), 'window-previews']
        broker = PreviewBroker(command, events.append, env)
        libc = ctypes.CDLL(None, use_errno=True)
        fd = libc.inotify_init1(os.O_CLOEXEC | os.O_NONBLOCK)
        if fd < 0:
            raise OSError(ctypes.get_errno(), 'inotify_init1')
        try:
            await broker.set_windows(specs)
            await asyncio.sleep(.6)
            if not broker.frames:
                raise RuntimeError(f'No calibration frame from {path}: {events}')
            frame_dir = next(iter(broker.frames)).parent
            if libc.inotify_add_watch(fd, os.fsencode(frame_dir), 0x80) < 0:  # IN_MOVED_TO
                raise OSError(ctypes.get_errno(), 'inotify_add_watch')
            events.clear()
            start, used = time.monotonic(), cpu(broker.process.pid)
            wall_start = time.time()
            await asyncio.sleep(4)
            elapsed, used = time.monotonic() - start, cpu(broker.process.pid) - used
            wall_end = time.time()
            writes = png_writes(fd)
            files = len(list(frame_dir.glob('*.png')))
            durations = []
            for line in log.read_text().splitlines():
                first, last = map(float, line.split())
                if wall_start <= first <= last <= wall_end:
                    durations.append((last - first) * 1000)
            errors = [e for e in events if e['event'] == 'error']
            assert not errors, errors
            frames = sum(e['event'] == 'frame' for e in events)
        finally:
            os.close(fd)
            await broker.close()
        assert not frame_dir.exists(), 'temporary frames leaked'
    return {'seconds': round(elapsed, 3), 'capture_calls': len(durations), 'published_frames': frames,
            'png_writes': writes, 'cpu_seconds': round(used, 4),
            'cpu_percent_of_one_core': round(used / elapsed * 100, 2), 'files': files,
            'grim_ms_median': round(statistics.median(durations), 2) if durations else None,
            'grim_ms_p95': round(sorted(durations)[int(len(durations) * .95)], 2) if durations else None}


async def main(args):
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
            for name, path in (('before', args.before), ('after', args.after)):
                result['cases'][label][name] = await measure(path.resolve(), targets)
        finally:
            for process in processes:
                process.terminate()
                process.wait(timeout=5)
        await asyncio.sleep(.3)
    path=Path.home()/'evidence/preview-performance.json'
    path.write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))

if __name__ == '__main__':
    if not Path('/var/lib/velora-qemu-ready').exists():
        raise SystemExit('Only run inside QEMU, through in-session.py')
    parser = argparse.ArgumentParser()
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    asyncio.run(main(parser.parse_args()))
