#!/usr/bin/env python3
"""Isolated foreign-toplevel capture. JSON lines in/out; never capture a monitor.

set: {op, windows: [{id, width, height, live, cursor, refresh}]}
frame: {event, id, path, width, height, revision}; errors retain the last frame.
EOF cancels all children and removes the private runtime directory.
"""
import asyncio
import hashlib
import io
import json
import os
from pathlib import Path
import re
import signal
import sys
import tempfile
import time

from PIL import Image

Image.MAX_IMAGE_PIXELS = 32_000_000
MAX_OUTPUT = 128 * 1024 * 1024


def emit(message):
    print(json.dumps(message, separators=(",", ":")), flush=True)


def normalize(windows):
    result = {}
    for item in windows[:64]:
        identifier = str(item.get("id", "")).lower()
        if not re.fullmatch(r"[0-9a-f]{1,16}", identifier):
            continue
        result[identifier] = {
            "id": identifier,
            "width": max(32, min(1024, int(item.get("width", 280)))),
            "height": max(32, min(768, int(item.get("height", 180)))),
            "live": bool(item.get("live", True)),
            "cursor": bool(item.get("cursor", False)),
            "refresh": int(item.get("refresh", 0)),
        }
    return result


async def capture(spec, destination, state=None):
    state = {} if state is None else state
    if state.get('spec') is not spec:
        state['spec'] = spec
        state.pop('digest', None)
    source = state.get('source')
    # Calibrate once; request thumbnail-sized output instead of decoding a half-size
    # desktop window on every frame. Two spare pixels avoid rounding oscillations.
    scale = min(1., (spec['width'] + 2) / source[0], (spec['height'] + 2) / source[1]) if source else .5
    scale = max(.001, scale)
    command = ["grim", "-T", spec["id"], "-s", f"{scale:.8f}", "-l", "0"]
    if spec["cursor"]:
        command.append("-c")
    command.append("-")
    process = await asyncio.create_subprocess_exec(*command, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    try:
        async with asyncio.timeout(3):
            # Bound stdout without communicate() collecting an unbounded allocation.
            chunks = []
            length = 0
            while chunk := await process.stdout.read(65536):
                length += len(chunk)
                if length > MAX_OUTPUT:
                    raise ValueError("capture exceeds the image size limit")
                chunks.append(chunk)
            code = await process.wait()
            if code:
                raise RuntimeError(f"grim exited with status {code}")
        with Image.open(io.BytesIO(b"".join(chunks))) as picture:
            if source is None or any(abs(actual - expected * scale) > 2
                                     for actual, expected in zip(picture.size, source)):
                source = tuple(value / scale for value in picture.size)
                state['source'] = source
            ratio = min(1., spec['width'] / source[0], spec['height'] / source[1])
            size = tuple(max(1, round(value * ratio)) for value in source)
            thumbnail = picture.resize(size, Image.Resampling.LANCZOS) if picture.size != size else picture
            # Repeated static frames need neither PNG encoding, a file write nor a Qt upload.
            digest = hashlib.sha256(str((size, thumbnail.mode)).encode() + thumbnail.tobytes()).hexdigest()
            if state.get('digest') != digest:
                temporary = destination.with_suffix(".tmp")
                thumbnail.save(temporary, format="PNG", compress_level=1)
                os.replace(temporary, destination)
                state['digest'] = digest
            return *size, digest
    finally:
        if process.returncode is None:
            process.kill()
        await process.wait()


class Capture:
    def __init__(self):
        self.states = {}

    async def __call__(self, spec, destination):
        return await capture(spec, destination, self.states.setdefault(spec['id'], {}))

    def retain(self, identifiers):
        self.states = {key: value for key, value in self.states.items() if key in identifiers}


class Broker:
    def __init__(self, directory, capture_fn=None):
        self.directory = Path(directory)
        self.capture_fn = capture_fn or Capture()
        self.slots = asyncio.Semaphore(2)
        self.start_lock = asyncio.Lock()
        self.last_started = 0.
        self.specs = {}
        self.tasks = {}
        self.revision = 0

    async def set_windows(self, windows):
        wanted = normalize(windows)
        stopped = []
        for identifier, spec in list(wanted.items()):
            if self.specs.get(identifier) == spec:
                wanted[identifier] = self.specs[identifier]
        for identifier in list(self.tasks):
            if wanted.get(identifier) != self.specs.get(identifier):
                task = self.tasks.pop(identifier)
                task.cancel()
                stopped.append(task)
        self.specs = wanted
        await asyncio.gather(*stopped, return_exceptions=True)
        if isinstance(self.capture_fn, Capture):
            self.capture_fn.retain(wanted)
        # A changed stream gets a unique filename, so a late decode cannot display
        # a recycled window's frame. Two bounded files per active stream suffice.
        for identifier, spec in wanted.items():
            if identifier not in self.tasks:
                self.revision += 1
                self.tasks[identifier] = asyncio.create_task(self.stream(spec, self.revision))

    async def stream(self, spec, generation):
        revision = 0
        failures = 0
        last_digest = None
        unchanged = 0
        files = [self.directory / f"{spec['id']}-{generation}-{slot}.png" for slot in range(2)]
        try:
            while self.specs.get(spec["id"]) is spec:
                started = time.monotonic()
                destination = files[revision % 2]
                try:
                    async with self.slots:
                        # Many visible overview cards share one budget; two requests
                        # may overlap, but together they start at most 16 captures/s.
                        async with self.start_lock:
                            await asyncio.sleep(max(0., self.last_started + 1 / 16 - time.monotonic()))
                            self.last_started = time.monotonic()
                        started = time.monotonic()
                        result = await self.capture_fn(spec, destination)
                        width, height = result[:2]
                    if self.specs.get(spec["id"]) is not spec:
                        return
                    digest = result[2] if len(result) > 2 else hashlib.sha256(destination.read_bytes()).hexdigest()
                    if digest != last_digest:
                        revision += 1
                        emit({"event": "frame", "id": spec["id"], "path": str(destination),
                              "width": width, "height": height, "revision": f"{generation}-{revision}"})
                        last_digest = digest
                        unchanged = 0
                    else:
                        unchanged = min(3, unchanged + 1)
                    failures = 0
                    if not spec["live"]:
                        await asyncio.Event().wait()
                        return
                except (OSError, ValueError, RuntimeError, TimeoutError, Image.DecompressionBombError) as error:
                    failures += 1
                    if failures == 1:
                        emit({"event": "error", "id": spec["id"], "message": str(error)})
                # Static windows settle at 2 polls/s. A changed frame restores 8/s.
                period = min(5, failures) if failures else .125 * (1 + unchanged)
                await asyncio.sleep(max(.001, period - (time.monotonic() - started)))
        except asyncio.CancelledError:
            pass
        finally:
            # Keep a still frame until its subscription ends, even after the task exits.
            if self.specs.get(spec["id"]) is not spec:
                for path in files:
                    path.unlink(missing_ok=True)
                    path.with_suffix(".tmp").unlink(missing_ok=True)

    async def close(self):
        self.specs = {}
        tasks = list(self.tasks.values())
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)


async def serve(directory):
    task = asyncio.current_task()
    asyncio.get_running_loop().add_signal_handler(signal.SIGTERM, task.cancel)
    broker = Broker(directory)
    reader = asyncio.StreamReader(limit=65536)
    protocol = asyncio.StreamReaderProtocol(reader)
    await asyncio.get_running_loop().connect_read_pipe(lambda: protocol, sys.stdin)
    emit({"event": "ready"})
    try:
        while line := await reader.readline():
            try:
                message = json.loads(line)
                if message.get("op") == "set" and isinstance(message.get("windows"), list):
                    await broker.set_windows(message["windows"])
            except (ValueError, TypeError, AttributeError) as error:
                emit({"event": "error", "message": str(error)})
    finally:
        await broker.close()


def main():
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    info = runtime.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError("A private XDG_RUNTIME_DIR is required")
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="velora-previews-", dir=runtime) as directory:
        try:
            asyncio.run(serve(directory))
        except asyncio.CancelledError:
            pass


if __name__ == "__main__":
    main()
