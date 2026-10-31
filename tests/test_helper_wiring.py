"""What moved into velora-helper stays wired up: the launcher finds it, and nothing calls the old scripts."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
GONE = ('keyring/is_unlocked', 'keyring/try_lookup', 'keyring/unlock', 'toolbox/open.sh', 'toolbox/quick.sh', 'top-apps.sh',
        'layout_keys.py', 'backlight.py', 'pick-color.sh', 'zoom.sh', 'workspace_action.sh', 'fuzzel-emoji.sh', 'default_apps.py',
        'text_color.py', 'text-color-venv', 'find_regions', 'find-regions-venv', 'thumbgen.py', 'thumbgen-venv', 'generate-thumbnails-magick', 'hyprconfigurator')


class HelperWiringTests(unittest.TestCase):
    def sources(self):
        for root in (PROJECT / 'dots', PROJECT / 'scripts'):
            for path in root.rglob('*'):
                if path.is_file() and path.suffix in ('.qml', '.lua', '.sh', '.py', '.fish', '.desktop') or path.name in ('helper',):
                    yield path

    def test_nothing_refers_to_the_old_scripts(self):
        offenders = {}
        for path in self.sources():
            text = path.read_text(errors='ignore')
            found = [name for name in GONE if name in text]
            if found:
                offenders[str(path.relative_to(PROJECT))] = found
        self.assertEqual(offenders, {})

    def test_the_launcher_finds_the_helper_and_says_where_the_shell_is(self):
        with tempfile.TemporaryDirectory(prefix='velora-launcher-') as directory:
            root = Path(directory)
            scripts = root / 'shell/scripts'
            scripts.mkdir(parents=True)
            launcher = scripts / 'helper'
            shutil.copy2(SHELL / 'scripts/helper', launcher)
            home = root / 'home'
            (home / '.local/bin').mkdir(parents=True)
            fake = home / '.local/bin/velora-helper'
            fake.write_text('#!/bin/sh\necho "$VELORA_SHELL_DIR $*"\n')
            fake.chmod(0o755)
            # ~/.local/bin isn't in this PATH, as in the running shell
            result = subprocess.run([str(launcher), 'zoom', 'reset'], capture_output=True, text=True,
                                    env={'PATH': '/usr/bin:/bin', 'HOME': str(home)})
            self.assertEqual(result.stdout.strip(), f'{root / "shell"} zoom reset')

    def record_script(self, root, *arguments, helper=True):
        scripts = root / 'videos'
        scripts.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SHELL / 'scripts/videos/record.sh', scripts / 'record.sh')
        (scripts / 'recorder.py').write_text('import sys; print("python", *sys.argv[1:])\n')
        fake = root / 'fake-helper'
        fake.write_text('#!/bin/sh\necho "helper $*"\n')
        fake.chmod(0o755)
        environment = {'PATH': '/usr/bin:/bin', 'HOME': str(root / 'home')}
        if helper:
            environment['VELORA_HELPER'] = str(fake)
        return subprocess.run([str(scripts / 'record.sh'), *arguments], capture_output=True, text=True, env=environment).stdout.strip()

    def test_the_recorder_status_needs_no_interpreter(self):
        with tempfile.TemporaryDirectory(prefix='velora-record-') as directory:
            self.assertEqual(self.record_script(Path(directory), 'status'), 'helper recorder-status')

    def test_recording_itself_stays_in_the_script(self):
        with tempfile.TemporaryDirectory(prefix='velora-record-') as directory:
            self.assertEqual(self.record_script(Path(directory), '--fullscreen', '--silent'), 'python --fullscreen --silent')
            self.assertEqual(self.record_script(Path(directory), 'status', '--extra'), 'python status --extra')

    def test_the_recorder_status_works_without_the_helper(self):
        with tempfile.TemporaryDirectory(prefix='velora-record-') as directory:
            self.assertEqual(self.record_script(Path(directory), 'status', helper=False), 'python status')

    def test_every_file_using_quickshell_imports_it(self):
        # Stand-in singletons in other tests hide this, and only the page's own log shows it at run time
        offenders = []
        for path in SHELL.rglob('*.qml'):
            text = path.read_text(errors='ignore')
            code = re.sub(r'//.*', '', text)
            if re.search(r'\bQuickshell\.[a-z]', code) and not re.search(r'^\s*import\s+Quickshell\s*;?\s*$', text, re.M):
                offenders.append(str(path.relative_to(SHELL)))
        self.assertEqual(offenders, [])

    def test_the_launcher_is_executable(self):
        self.assertTrue(os.access(SHELL / 'scripts/helper', os.X_OK))

    def test_the_emoji_data_is_shared_with_the_launcher_page(self):
        data = PROJECT / 'dots/.config/hypr/hyprland/data/emoji.txt'
        self.assertGreater(len(data.read_text().splitlines()), 1000)
        self.assertIn('hypr/hyprland/data/emoji.txt', (SHELL / 'services/Emojis.qml').read_text())
        self.assertIn('hyprland/data/emoji.txt', (PROJECT / 'tools/velora-helper/src/emoji.rs').read_text())


if __name__ == '__main__':
    unittest.main()
