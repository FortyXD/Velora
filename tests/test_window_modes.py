"""Free windows (hyprland/modes/floating.lua) and the mode switch, run against a stand-in for Hyprland."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
HYPR = PROJECT / 'dots/.config/hypr'
LUA = shutil.which('lua5.4') or shutil.which('lua')


@unittest.skipUnless(LUA, 'Lua 5.4 is not installed')
class WindowModeTests(unittest.TestCase):
    def lua(self, script=None, env=None, code=None):
        command = [LUA, '-e', f'package.path="{HYPR}/?.lua;"..package.path']
        command += ['-e', code] if code else [script]
        return subprocess.run(command, env={**os.environ, **(env or {})}, capture_output=True, text=True, timeout=20)

    def test_free_windows_snap_minimize_and_remember(self):
        with tempfile.TemporaryDirectory(prefix='velora-free-') as state:
            result = self.lua(str(PROJECT / 'tests/lua/floating_spec.lua'), {'VELORA_TEST_STATE': state})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_gestures_keep_the_old_ones_and_follow_overrides(self):
        with tempfile.TemporaryDirectory(prefix='velora-gestures-') as runtime:
            result = self.lua(str(PROJECT / 'tests/lua/gestures_spec.lua'), {'VELORA_TEST_STATE': runtime})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_mode_comes_from_the_settings_file(self):
        with tempfile.TemporaryDirectory(prefix='velora-mode-') as config:
            custom = Path(config) / 'hypr/custom'
            custom.mkdir(parents=True)
            probe = 'print(require("hyprland.window_mode").current())'
            self.assertEqual(self.lua(env={'XDG_CONFIG_HOME': config}, code=probe).stdout.strip(), 'tiling')
            (custom / 'shell_settings.json').write_text(json.dumps({'general:layout': 'dwindle', 'shell:windowMode': 'floating'}, indent=4))
            self.assertEqual(self.lua(env={'XDG_CONFIG_HOME': config}, code=probe).stdout.strip(), 'floating')
            (custom / 'shell_settings.json').write_text(json.dumps({'shell:windowMode': 'tiling'}))
            self.assertEqual(self.lua(env={'XDG_CONFIG_HOME': config}, code=probe).stdout.strip(), 'tiling')


if __name__ == '__main__':
    unittest.main()
