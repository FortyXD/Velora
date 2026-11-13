"""The worker's CPU budget reaches ONNX and OCR without loading model weights."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

WORKER = Path(__file__).resolve().parents[1] / 'tools/velora-searchd/python/worker.py'


class LensWorkerTests(unittest.TestCase):
    def test_thread_budget_reaches_model_and_child_process_environment(self):
        # Run separately because the real worker sets process resource limits.
        script = r'''
import hashlib, os, pathlib, runpy, sys, tempfile, types
os.sched_getaffinity = lambda pid: set(range(24))
worker = runpy.run_path(sys.argv[1])
expected = int(sys.argv[2])
assert worker['THREADS'] == expected
assert os.environ['OMP_NUM_THREADS'] == str(expected)
seen = []
def session(path, options, providers):
    seen.append(options)
    assert options.intra_op_num_threads == expected
    assert options.inter_op_num_threads == 1
    assert providers == ['CPUExecutionProvider']
    return object()
sys.modules['onnxruntime'] = types.SimpleNamespace(
    disable_telemetry_events=lambda: None,
    SessionOptions=types.SimpleNamespace,
    InferenceSession=session)
with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    (root / 'e5-text.onnx').write_bytes(b'fixture')
    models = worker['Models'].__new__(worker['Models'])
    models.sessions = {}
    models.root = root
    models.manifest = {'files': {'e5-text.onnx': hashlib.sha256(b'fixture').hexdigest()}}
    assert models.session('e5-text') is models.session('e5-text')
    assert len(seen) == 1
'''
        for supplied, expected in [(None, 2), ('8', 8), ('24', 24), ('99', 24), ('0', 1)]:
            with self.subTest(threads=supplied):
                environment = {k: v for k, v in os.environ.items() if k != 'VELORA_LENS_THREADS'}
                if supplied is not None:
                    environment['VELORA_LENS_THREADS'] = supplied
                result = subprocess.run([sys.executable, '-I', '-c', script, str(WORKER), str(expected)],
                                        env=environment, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
