"""Test the commands launched by Toolbox, including child cancellation and atomic publication."""
import concurrent.futures
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

from native_helper import binary


class ToolboxTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='velora-toolbox-')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.env = {**os.environ, 'PATH': str(self.root) + ':' + os.environ['PATH']}

    def job(self, *args):
        p = subprocess.run([binary(), 'toolbox', *args], env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(p.returncode, 0, p.stderr + p.stdout)
        return [json.loads(line) for line in p.stdout.splitlines()]

    def fake(self, name, body):
        path = self.root / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    @unittest.skipUnless(shutil.which('qrencode') and shutil.which('zbarimg'), 'needs QR codecs')
    def test_qr_round_trip_with_option_like_text(self):
        path = self.root / 'мой код.png'
        text = '--Привет 📝'
        encoded = self.job('qr-encode', '--out', path, '--', text)
        self.assertEqual(encoded[-1]['output'], str(path))
        self.assertEqual(self.job('qr-scan', path)[0]['output'], text)

    @unittest.skipUnless(shutil.which('magick'), 'needs ImageMagick')
    def test_concurrent_conversions_do_not_overwrite_each_other(self):
        img = self.root / 'Море.PPM'
        img.write_bytes(b'P6\n2 1\n255\n' + bytes.fromhex('ff11220033ff'))
        output = self.root/'outputs'
        output.mkdir()
        existing = output/'Море.png'
        existing.write_bytes(b'keep me')
        def convert(_):
            events = self.job('convert', '--to','png','--out-dir',output,'--',img)
            self.assertEqual(events[-1]['event'], 'finished')
            return Path(next(e['output'] for e in events if e['event']=='done'))
        with concurrent.futures.ThreadPoolExecutor(4) as pool:
            paths = list(pool.map(convert, range(4)))
        self.assertEqual(len(set(paths)), 4)
        self.assertTrue(all(p.read_bytes().startswith(b'\x89PNG') for p in paths))
        self.assertEqual(existing.read_bytes(), b'keep me')
        self.assertFalse(list(output.glob('.velora-*')))

    def test_terminating_a_job_stops_its_external_process(self):
        marker = self.root/'child'
        self.fake('yt-dlp', 'echo $$ > "$VELORA_TEST_PID"; exec sleep 60')
        process = subprocess.Popen([binary(), 'toolbox','download','https://example.invalid/test',
                                    '--out-dir',self.root], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env={**self.env,'VELORA_TEST_PID':str(marker)}, text=True)
        try:
            for _ in range(300):
                if marker.exists() and marker.stat().st_size: break
                time.sleep(.01)
            self.assertTrue(marker.exists())
            child = Path('/proc')/marker.read_text().strip()/'stat'
            process.terminate()
            stdout, stderr = process.communicate(timeout=4)
            self.assertEqual(process.returncode, 130, stderr)
            self.assertEqual(json.loads(stdout.splitlines()[-1])['event'], 'cancelled')
            for _ in range(70):
                if not child.exists() or child.read_text().rsplit(')',1)[-1].split()[0]=='Z': break
                time.sleep(.01)
            else: self.fail('The download continued after cancellation')
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
