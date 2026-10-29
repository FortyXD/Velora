"""Exercise real image transitions, including pixels, rapid requests and monitor acknowledgement."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import importlib.util
import json
import time

try:
    import cv2
    import numpy as np
except ImportError:
    cv2 = np = None

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
QT_TEST_RUNNER = shutil.which('qmltestrunner6') or next(
    (str(path) for path in (Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner'))
     if path.is_file()), None)


class WallpaperTests(unittest.TestCase):
    @unittest.skipUnless(QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
    def test_image_transitions(self):
        with tempfile.TemporaryDirectory(prefix='velora-wallpaper-') as directory:
            root = Path(directory)
            shutil.copy2(SHELL / 'modules/common/widgets/WallpaperFader.qml', root)
            shutil.copy2(SHELL / 'modules/common/MaterialPalette.qml', root)
            # Only replace the shell singleton base; all coordination logic is production code.
            (root / 'WallpaperTransition.qml').write_text(
                (SHELL / 'services/WallpaperTransition.qml').read_text()
                .replace('import Quickshell\n', '').replace('Singleton {', 'QtObject {'))
            (root / 'MaterialThemeLoader.qml').write_text('\n'.join(
                line for line in (SHELL / 'services/MaterialThemeLoader.qml').read_text().splitlines()
                if not line.startswith(('import qs.', 'import Quickshell'))).replace('Singleton {', 'Item {'))
            stubs = {
                'Appearance': 'property int paletteTransitionDuration: 0; property QtObject m3colors: MaterialPalette { transitionDuration: Appearance.paletteTransitionDuration } function scaledDuration(ms) { return ms; }',
                'Config': 'property QtObject options: QtObject { property QtObject background: QtObject { property string wallpaperPath: "" } }',
                'Directories': 'property string generatedMaterialThemePath: ""',
                'ThemeTransition': 'property int runs: 0; property bool deferred: false; property var changes: []; function run(change) { runs++; if (deferred) changes.push(change); else change(); } function flush() { for (const change of changes) change(); changes = []; }',
            }
            for name, body in stubs.items():
                (root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}\n')
            (root / 'FileView.qml').write_text('import QtQuick\nQtObject { property url path; property bool watchChanges; property bool blockLoading; signal loaded(); signal loadFailed(); signal fileChanged(); function reload() {} function text() { return ""; } }\n')
            (root / 'qmldir').write_text('\n'.join(
                f'singleton {name} 1.0 {name}.qml' for name in ('WallpaperTransition', 'MaterialThemeLoader', *stubs)) + '\n')
            for name, color in (('red', '#ff0000'), ('green', '#00ff00'), ('blue', '#0000ff')):
                (root / f'{name}.svg').write_text(
                    f'<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200">'
                    f'<path fill="{color}" d="M0 0H400V200H0z"/></svg>')
            shutil.copy2(PROJECT / 'tests/qml/tst_wallpaperfader.qml', root)
            result = subprocess.run(
                [QT_TEST_RUNNER, '-input', str(root), '-o', '-,txt'],
                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'generic',
                     'QT_QUICK_BACKEND': 'software', 'FONTCONFIG_FILE': '/etc/fonts/fonts.conf'},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


@unittest.skipUnless(cv2 is not None, 'Wallpaper analysis needs OpenCV and NumPy')
class WallpaperAnalysisTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('wallpaper_analysis', SHELL / 'scripts/images/least_busy_region.py')
        self.analysis = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.analysis)
        self.temp = tempfile.TemporaryDirectory(prefix='velora-wallpaper-analysis-')
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'wallpaper.png'

    def test_free_widget_samples_its_own_background_including_black(self):
        image = np.zeros((100, 200, 3), dtype=np.uint8)
        image[:, 100:] = 255
        cv2.imwrite(str(self.path), image)
        self.assertEqual(self.analysis.get_dominant_color(str(self.path), 10, 10, 50, 50), [0, 0, 0])
        self.assertEqual(self.analysis.get_dominant_color(str(self.path), 110, 10, 50, 50), [255, 255, 255])

    def test_color_is_deterministic_and_rgb(self):
        image = np.full((100, 100, 3), [10, 30, 220], dtype=np.uint8)
        cv2.imwrite(str(self.path), image)
        colors = [self.analysis.get_dominant_color(str(self.path), 0, 0, 100, 100) for _ in range(3)]
        self.assertEqual(colors, [[220, 30, 10]] * 3)

    def test_vectorized_search_matches_brute_force(self):
        image = np.random.default_rng(42).integers(0, 256, (80, 100), dtype=np.uint8)
        cv2.imwrite(str(self.path), image)
        windows = [(float(np.var(image[y:y+20, x:x+20])), x, y)
                   for y in range(5, 56, 5) for x in range(5, 76, 5)]
        for busiest in (False, True):
            with self.subTest(busiest=busiest):
                expected = min(windows, key=lambda p: (-p[0] if busiest else p[0], p[2], p[1]))
                coords, variance = self.analysis.find_least_busy_region(
                    str(self.path), 20, 20, stride=5, horizontal_padding=5, vertical_padding=5, busiest=busiest)
                self.assertEqual(coords, expected[1:])
                self.assertAlmostEqual(variance, expected[0])

    def test_slots_keep_widgets_apart(self):
        cv2.imwrite(str(self.path), np.zeros((400, 600, 3), dtype=np.uint8))
        positions = [self.analysis.find_least_busy_region(
            str(self.path), 100, 100, stride=10, horizontal_padding=10, vertical_padding=10, slot=i, gap=20)[0]
            for i in range(3)]
        self.assertEqual(len(set(positions)), 3)
        for a, b in zip(positions, positions[1:]):
            self.assertTrue(abs(a[0] - b[0]) >= 120 or abs(a[1] - b[1]) >= 120)


@unittest.skipUnless(shutil.which('jq') and shutil.which('flock'), 'Wallpaper switching needs jq and flock')
class WallpaperSwitchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='velora-switchwall-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'config/illogical-impulse/config.json'
        self.config.parent.mkdir(parents=True)
        self.config.write_text(json.dumps({
            'background': {'wallpaperPath': 'old', 'widgets': {'clock': {'cookie': {'aiStyling': False}}}},
            'appearance': {'palette': {'type': 'scheme-tonal-spot', 'accentColor': ''},
                           'wallpaperTheming': {'enableAppsAndShell': True, 'enableQtApps': False,
                                               'terminalGenerationProps': {'forceDarkMode': False}}}}))
        (self.root / 'config/hypr/custom/scripts').mkdir(parents=True)
        scripts = self.root / 'scripts'
        scripts.mkdir()
        self.script = scripts / 'switchwall.sh'
        shutil.copy2(SHELL / 'scripts/colors/switchwall.sh', self.script)
        (scripts / 'applycolor.sh').write_text('#!/bin/sh\nexit 0\n')
        (scripts / 'applycolor.sh').chmod(0o755)
        (scripts / 'code').mkdir()
        (scripts / 'code/material-code-set-color.sh').write_text('#!/bin/sh\nexit 0\n')
        (scripts / 'code/material-code-set-color.sh').chmod(0o755)
        activate = self.root / 'venv/bin/activate'
        activate.parent.mkdir(parents=True)
        activate.write_text('deactivate() { :; }\n')
        binaries = self.root / 'bin'
        binaries.mkdir()
        helpers = {
            'hyprctl': 'if [ "$1" = monitors ]; then echo \'[{"focused":true,"scale":1,"x":0,"y":0,"width":1920,"height":1080}]\'; else echo \'{"x":0,"y":0}\'; fi',
            'magick': 'echo "$*" >> "$WALLPAPER_TEST_PROBES"; if [[ "$*" == *a.svg* ]]; then touch "$WALLPAPER_TEST_STARTED"; sleep 0.4; fi',
            'identify': 'if [[ "$*" == *%w* ]]; then echo 1920; else echo 1080; fi',
            'bc': 'cat >/dev/null; echo 0',
            'gsettings': 'exit 0',
            'matugen': 'echo "palette:$(jq -r .background.wallpaperPath "$WALLPAPER_TEST_CONFIG")" >> "$WALLPAPER_TEST_EVENTS"',
            'python3': 'echo "terminal:$(jq -r .background.wallpaperPath "$WALLPAPER_TEST_CONFIG")" >> "$WALLPAPER_TEST_EVENTS"; echo material',
        }
        for name, body in helpers.items():
            path = binaries / name
            path.write_text('#!/usr/bin/env bash\n' + body + '\n')
            path.chmod(0o755)
        self.events = self.root / 'events'
        self.probes = self.root / 'probes'
        self.started = self.root / 'started'
        self.env = {**os.environ, 'PATH': str(binaries) + os.pathsep + os.environ['PATH'],
                    'XDG_CONFIG_HOME': str(self.root / 'config'), 'XDG_STATE_HOME': str(self.root / 'state'),
                    'XDG_CACHE_HOME': str(self.root / 'cache'), 'ILLOGICAL_IMPULSE_VIRTUAL_ENV': str(self.root / 'venv'),
                    'WALLPAPER_TEST_CONFIG': str(self.config), 'WALLPAPER_TEST_EVENTS': str(self.events),
                    'WALLPAPER_TEST_PROBES': str(self.probes), 'WALLPAPER_TEST_STARTED': str(self.started),
                    'VELORA_HELPER': ''}  # The scripts, unless a test gives a helper

    def start(self, name, *extra, env=None):
        image = self.root / f'{name}.svg'
        image.write_text('<svg/>')
        process = subprocess.Popen(['bash', str(self.script), '--image', str(image), '--type', 'scheme-tonal-spot', '--mode', 'dark', *extra],
                                   env=env or self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        return process

    def wait_for(self, predicate):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.01)
        self.fail('Wallpaper switch did not reach the expected stage')

    def test_palette_is_generated_before_new_wallpaper_is_published(self):
        process = self.start('new')
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, stdout + stderr)
        self.assertEqual(self.events.read_text().splitlines(), ['palette:old', f'terminal:{self.root / "new.svg"}'])

    def test_latest_queued_request_wins_without_overlapping_palette_writes(self):
        first = self.start('a')
        self.wait_for(self.started.exists)
        second = self.start('b')
        request = self.root / 'cache/quickshell/wallpaper-request'
        self.wait_for(lambda: request.exists() and request.read_text().endswith(f'-{second.pid}'))
        third = self.start('c')
        self.wait_for(lambda: request.read_text().endswith(f'-{third.pid}'))
        for process in (first, second, third):
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, stdout + stderr)
        self.assertEqual(json.loads(self.config.read_text())['background']['wallpaperPath'], str(self.root / 'c.svg'))
        self.assertNotIn('b.svg', self.probes.read_text())

    def helper_env(self):
        helper = self.root / 'bin/velora-helper'
        helper.write_text('#!/usr/bin/env bash\n'
                          'case "$1 $2" in\n'
                          '  "theme stage") mkdir -p "$XDG_CACHE_HOME/staged"; echo "stage:$(jq -r .background.wallpaperPath "$WALLPAPER_TEST_CONFIG")" >> "$WALLPAPER_TEST_EVENTS"; echo "$XDG_CACHE_HOME/staged" ;;\n'
                          '  "theme commit") echo "commit:$3" >> "$WALLPAPER_TEST_EVENTS" ;;\n'
                          'esac\n')
        helper.chmod(0o755)
        return {**self.env, 'VELORA_HELPER': str(helper)}

    def run_switch(self, *args, env):
        result = subprocess.run(['bash', str(self.script), *args], env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_prepare_changes_nothing_and_commit_puts_the_staged_palette_in_place(self):
        env = self.helper_env()
        process = self.start('new', '--prepare', env=env)
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, stdout + stderr)
        request = json.loads(stdout.strip().splitlines()[-1])
        self.assertTrue(request['staged'])
        self.assertEqual(request['wallpaper'], str(self.root / 'new.svg'))
        self.assertEqual(request['accent'], '')  # A picture of its own clears a fixed accent
        config = json.loads(self.config.read_text())
        self.assertEqual(config['background']['wallpaperPath'], 'old')
        self.assertEqual(self.events.read_text().splitlines(), ['stage:old'])

        self.run_switch('--commit', request['request'], env=env)
        self.assertEqual(self.events.read_text().splitlines(), ['stage:old', f'commit:{self.root / "cache/staged"}'])
        self.assertEqual(json.loads(self.config.read_text())['background']['wallpaperPath'], str(self.root / 'new.svg'))
        self.assertFalse(Path(request['request']).exists())

    def test_commit_without_publishing_leaves_config_to_the_shell(self):
        env = self.helper_env()
        process = self.start('new', '--prepare', env=env)
        stdout, _ = process.communicate(timeout=5)
        request = json.loads(stdout.strip().splitlines()[-1])
        self.run_switch('--commit', request['request'], '--no-publish', '--no-post', env=env)
        self.assertEqual(json.loads(self.config.read_text())['background']['wallpaperPath'], 'old')
        self.assertTrue(Path(request['request']).exists())  # Kept for --post
        self.run_switch('--post', request['request'], env=env)
        self.assertFalse(Path(request['request']).exists())

    def test_without_helper_prepare_defers_generation_to_commit(self):
        process = self.start('new', '--prepare')
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, stdout + stderr)
        request = json.loads(stdout.strip().splitlines()[-1])
        self.assertFalse(request['staged'])
        self.assertFalse(self.events.exists())
        self.run_switch('--commit', request['request'], env=self.env)
        self.assertEqual(self.events.read_text().splitlines(), ['palette:old', f'terminal:{self.root / "new.svg"}'])


if __name__ == '__main__':
    unittest.main()
