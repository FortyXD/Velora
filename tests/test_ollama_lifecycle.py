"""Check that each private backend releases runners which detach from its process group."""
import fcntl
import os
from pathlib import Path
import subprocess
import time
import unittest

import test_agent


@unittest.skipUnless(os.environ.get("VELORA_TEST_PREBUILT"), "requires tests/run_isolated.py")
class OllamaLifecycle(unittest.TestCase):
    def setUp(self):
        self.fixture = test_agent.AgentTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.lock = self.fixture.root/"runner.lock"
        self.fixture.fake("ollama", """
import socket, subprocess
listener = socket.socket()
listener.bind(('127.0.0.1', 11435))
listener.listen()
subprocess.Popen([sys.executable, '-c', '''import fcntl, os, time
with open(os.path.join(os.environ["TEST_ROOT"], "runner.lock"), "w") as fd:
    fcntl.flock(fd, fcntl.LOCK_EX)
    fd.write("ready")
    fd.flush()
    time.sleep(60)'''], start_new_session=True)
while True:
    conn, _ = listener.accept()
    conn.close()
""")

    def wait_for_lock(self, held):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.lock.exists() and self.lock.read_text() == "ready":
                with self.lock.open() as fd:
                    try:
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        actual = False
                    except BlockingIOError:
                        actual = True
                    if actual == held:
                        return
            time.sleep(.04)
        self.fail(f"expected runner file lock held={held}")

    def test_helper_termination_releases_detached_runner(self):
        binary = Path(os.environ.get("VELORA_TEST_HELPER", test_agent.ROOT/"tools/target/debug/velora-helper"))
        with subprocess.Popen([binary, "local-ollama", "cpu"], env=self.fixture.env) as helper:
            try:
                self.wait_for_lock(True)
            finally:
                helper.terminate()
            helper.wait(timeout=5)
        self.wait_for_lock(False)

    def test_agent_shutdown_releases_detached_runner(self):
        fixture = self.fixture
        fixture.configure(profile={"provider":"ollama","model":"fixture","endpoint":"http://127.0.0.1:11435"})
        fixture.local_model(["unused"])
        task = fixture.send("probe")
        _, events = fixture.until(lambda e:e.get("task")==task and e["type"]=="finished")
        self.assertFalse(any(e["type"]=="error" for e in events), events)
        self.wait_for_lock(True)
        fixture.proc.stdin.close()
        fixture.proc.wait(timeout=5)
        self.wait_for_lock(False)
