"""Settings setup changes only a temporary home and uses stand-in system tools."""
import fcntl
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("lens_setup", ROOT / "tools/velora-searchd/python/setup.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)
spec = importlib.util.spec_from_file_location("lens_install", ROOT / "tools/velora-searchd/python/install.py")
install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install)


class LensSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lens-setup-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        environment = dict(HOME=str(self.root), XDG_STATE_HOME=str(self.root / "state"),
                           XDG_CONFIG_HOME=str(self.root / "config"), XDG_CACHE_HOME=str(self.root / "cache"),
                           XDG_DATA_HOME=str(self.root / "data"))
        self.environment = patch.dict(os.environ, environment)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        # run_job installs signal handlers only in its own production process.
        self.signals = patch.object(setup.signal, "signal")
        self.signals.start()
        self.addCleanup(self.signals.stop)

    def test_absent_service_is_not_a_locked_keyring(self):
        with patch.object(setup, "binary", return_value=None):
            state = setup.status()
        self.assertFalse(state["installed"])
        self.assertFalse(state["running"])
        self.assertFalse(state["models"])

    def test_service_build_registration_and_completion(self):
        commands = []

        def command(args, **kwargs):
            args = list(map(str, args))
            commands.append(args)
            if args[0] == "/usr/bin/pacman":
                return subprocess.CompletedProcess(args, 0, "", "")
            if args[0] == "cargo":
                output = Path(kwargs["env"]["CARGO_TARGET_DIR"]) / "release/velora-searchd"
                output.parent.mkdir(parents=True)
                output.write_text("test executable")
            return subprocess.CompletedProcess(args, 0)

        with patch.object(setup.subprocess, "run", side_effect=command):
            setup.run_job(False)
        state = setup.status()
        self.assertEqual(state["stage"], "done")
        self.assertFalse(state["running"])
        self.assertTrue(state["installed"])
        self.assertEqual(state["steps_done"], state["steps_total"])
        self.assertEqual(state["steps_total"], 2)
        unit = (self.root / "config/systemd/user/velora-searchd.service").read_text()
        self.assertIn(str(self.root / ".local/bin/velora-searchd"), unit)
        self.assertIn("RestrictAddressFamilies=AF_UNIX AF_NETLINK", unit)
        self.assertIn(["systemctl", "--user", "daemon-reload"], commands)
        self.assertIn(["systemctl", "--user", "start", "velora-searchd.service"], commands)

    def test_failure_is_visible_and_does_not_claim_success(self):
        with patch.object(setup.subprocess, "run", side_effect=OSError("fixture failure")):
            setup.run_job(False)
        self.assertEqual(setup.status()["stage"], "failed")
        self.assertFalse(setup.status()["running"])
        self.assertLess(setup.status()["steps_done"], setup.status()["steps_total"])

    def test_progress_survives_reopening_settings_and_resets_on_next_phase(self):
        phase = setup.Progress(True)
        phase("models", unit="bytes", done=123, total=456, model="e5")
        state = setup.status()
        self.assertTrue(state["running"])
        self.assertEqual((state["step"], state["steps_done"], state["steps_total"]), (4, 3, 5))
        self.assertEqual(state["progress"]["done"], 123)
        self.assertGreaterEqual(state["elapsed_seconds"], 0)
        phase("verifying")
        self.assertEqual(setup.status()["progress"], {})
        phase("done")
        phase.state.update(running=False, finished_at=time.time())
        setup.save_state(phase.state)
        with patch.object(setup.time, "time", return_value=time.time() + 3600):
            state = setup.status()
        self.assertEqual(state["steps_done"], 5)
        self.assertLess(state["elapsed_seconds"], 5, "finished timer must not keep counting")

    def test_legacy_live_job_gets_stage_counts_without_restart(self):
        setup.save_state(dict(running=True, stage="models", pid=os.getpid(), identity=setup.identity(os.getpid())))
        state = setup.status()
        self.assertTrue(state["running"])
        self.assertEqual((state["step"], state["steps_done"]), (4, 3))
        self.assertGreaterEqual(state["elapsed_seconds"], 0)
        self.assertNotIn("progress", state, "do not invent bytes for older installers")

    def test_cancel_does_not_interrupt_a_package_transaction(self):
        setup.save_state(dict(running=True, stage="dependencies", pid=os.getpid(), identity=setup.identity(os.getpid())))
        with patch.object(setup.os, "killpg") as kill:
            setup.cancel()
            kill.assert_not_called()
        self.assertTrue((setup.state_dir() / "cancel").exists())

    def test_stale_pid_is_never_cancelled(self):
        setup.save_state(dict(running=True, stage="models", pid=os.getpid(), identity="old-process"))
        with patch.object(setup.os, "killpg") as kill:
            self.assertEqual(setup.status()["stage"], "interrupted")
            setup.cancel()
            kill.assert_not_called()

    def test_only_one_setup_job_can_start(self):
        with (setup.state_dir() / "setup.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch.object(setup.subprocess, "Popen") as process:
                setup.start(True)
                process.assert_not_called()

    def test_unwritable_setup_location_returns_a_visible_error(self):
        invalid = self.root / "not-a-directory"
        invalid.write_text("fixture")
        result = subprocess.run(["/usr/bin/python3", str(ROOT / "tools/velora-searchd/python/setup.py"), "status"],
                                env={**os.environ, "XDG_STATE_HOME": str(invalid)}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["stage"], "failed")
        self.assertTrue(json.loads(result.stdout)["detail"])


class LensInstallProgressTests(unittest.TestCase):
    def test_pip_unknown_total_next_file_and_export_events(self):
        events = []
        lines = ['Downloading first.whl', 'Progress 30 of 100', 'Progress 100 of 100',
                 'Downloading second.whl', 'Progress 12 of 0', 'Installing collected packages: fixture',
                 'LENS_PROGRESS {"task":"model-export","unit":"parts","done":1,"total":3}']
        script = 'import sys\nfor line in ' + repr(lines) + ':\n print(line, flush=True)\n'
        with contextlib.redirect_stdout(io.StringIO()):
            install.run_progress(['/usr/bin/python3', '-c', script], 'models', lambda stage, **details: events.append((stage, details)))
        self.assertEqual(events[2][1], dict(task="component-download", unit="bytes", done=30, total=100))
        self.assertEqual(events[4][1], dict(task="component-download"), "new file clears the old denominator")
        self.assertIsNone(events[5][1]["total"])
        self.assertEqual(events[-1][1], dict(task="model-export", unit="parts", done=1, total=3))

    def test_download_failure_is_not_success_even_with_complete_byte_count(self):
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(subprocess.CalledProcessError):
            install.run_progress(['/usr/bin/python3', '-c', 'print("Progress 100 of 100"); raise SystemExit(1)'],
                                 'runtime', lambda *_args, **_details: None)
