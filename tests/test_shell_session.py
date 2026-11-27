"""Exercise panel recovery on private Quickshell instances with no desktop attached."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


RUNNER = Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii/scripts/shell-session"


class ShellSessionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="velora-shell-session-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.env = {**os.environ, "XDG_RUNTIME_DIR": directory.name, "QT_QPA_PLATFORM": "offscreen",
                    "QT_QUICK_BACKEND": "software", "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + directory.name + "/no-bus"}
        for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "QS_CONFIG_PATH", "QS_CONFIG_NAME"):
            self.env.pop(name, None)
        for key in ("CONFIG", "DATA", "CACHE", "STATE"):
            self.env["XDG_" + key + "_HOME"] = str(self.root / key.lower())

    def launch(self, *command):
        process = subprocess.Popen(command, env=self.env, start_new_session=True,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        def clean():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)
        self.addCleanup(clean)
        return process

    def instances(self):
        listing = subprocess.run(["qs", "list", "--all", "-j"], env=self.env, capture_output=True, text=True)
        return {item["config_path"]: item["pid"] for item in json.loads(listing.stdout)} if listing.stdout.lstrip().startswith("[") else {}

    def wait_for_panel(self, path, previous=None):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            pid = self.instances().get(str(path))
            if pid is not None and pid != previous:
                return pid
            time.sleep(.05)
        self.fail("The replacement panel did not start.")

    @unittest.skipUnless(shutil.which("qs"), "requires Quickshell")
    def test_crash_manual_restart_and_clean_stop(self):
        panel = self.root / "config/quickshell/panel/shell.qml"
        panel.parent.mkdir(parents=True)
        settings = panel.with_name("settings.qml")
        for path in (panel, settings):
            path.write_text("import Quickshell\nShellRoot {}\n")
        self.launch("qs", "-p", settings)
        settings_pid = self.wait_for_panel(settings)
        runner = self.launch(RUNNER, "--restart", "panel")
        first = self.wait_for_panel(panel)
        os.kill(first, signal.SIGKILL)
        second = self.wait_for_panel(panel, first)
        self.assertEqual(runner.poll(), None)
        self.assertEqual(self.instances()[str(settings)], settings_pid)
        self.assertEqual(self.launch(RUNNER, "panel").wait(timeout=3), 0)
        replacement = self.launch(RUNNER, "--restart", "panel")
        self.wait_for_panel(panel, second)
        self.assertEqual(runner.wait(timeout=5), 0)
        subprocess.run(["qs", "kill", "-c", "panel"], env=self.env, check=True, capture_output=True)
        self.assertEqual(replacement.wait(timeout=5), 0)
        self.assertEqual(self.instances(), {str(settings): settings_pid})

    def test_repeated_startup_failure_and_logout(self):
        attempts = self.root / "attempts"
        fake = self.root / "qs"
        fake.write_text('#!/bin/sh\necho try >> "$ATTEMPTS"\nexit 1\n')
        fake.chmod(0o755)
        self.env.update(PATH=str(self.root) + os.pathsep + self.env["PATH"], ATTEMPTS=str(attempts))
        self.assertEqual(self.launch(RUNNER, "panel").wait(timeout=8), 1)
        self.assertEqual(len(attempts.read_text().splitlines()), 3)
        self.env["WAYLAND_DISPLAY"] = "closed-wayland-socket"
        self.assertEqual(self.launch(RUNNER, "panel").wait(timeout=3), 1)
        self.assertEqual(len(attempts.read_text().splitlines()), 4)
