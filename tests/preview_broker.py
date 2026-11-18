"""Drive the installed JSON-lines preview protocol using a real native subprocess."""
import asyncio
import json
import os
from pathlib import Path


class PreviewBroker:
    def __init__(self, executable, receive, env=None):
        self.command = list(executable) if isinstance(executable, (list, tuple)) else [str(executable), 'window-previews']
        self.receive = receive
        self.env = os.environ if env is None else env
        self.process = None
        self.reader = None
        self.frames = set()

    async def start(self):
        self.process = await asyncio.create_subprocess_exec(
            *self.command, env=self.env,
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE)
        ready = await asyncio.wait_for(self.process.stdout.readline(), 5)
        if not ready or json.loads(ready).get('event') != 'ready':
            raise RuntimeError('Preview broker failed to start')
        self.reader = asyncio.create_task(self.read_events())

    async def read_events(self):
        async for line in self.process.stdout:
            event = json.loads(line)
            if event['event'] == 'frame':
                self.frames.add(Path(event['path']))
            self.receive(event)

    async def set_windows(self, specs):
        if self.process is None:
            await self.start()
        self.process.stdin.write(json.dumps({'op':'set', 'windows':specs}).encode() + b'\n')
        await self.process.stdin.drain()
        if not specs:
            for _ in range(100):
                if not any(p.exists() for p in self.frames):
                    break
                await asyncio.sleep(.01)

    async def close(self):
        if self.process is None:
            return
        self.process.stdin.close()
        await asyncio.wait_for(self.process.wait(), 5)
        await self.reader
        if self.process.returncode != 0:
            raise RuntimeError(f'Preview process exited with {self.process.returncode}')
