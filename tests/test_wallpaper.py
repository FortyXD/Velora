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
    def test_random_downloads_preserve_recent_files_per_provider(self):
        with tempfile.TemporaryDirectory(prefix='velora-random-') as directory:
            root = Path(directory)
            scripts = SHELL / 'scripts/colors/random'
            (root / 'common.sh').write_text(r'''source "$ORIGINAL_RANDOM/common.sh"
get_pictures_dir() { echo "$HOME/Pictures"; }
notify_progress() { :; }
api_get() { printf '%s' "$API_RESPONSE"; }
fetch_image() { printf '%s' "$1" > "$2"; }
apply_wallpaper() { printf '%s\n' "$1"; }
hyprctl() { echo '[{"focused":true,"width":1920,"height":1080}]'; }
''')
            saved = {}
            for provider, ids in [('wallhaven', ['abc123', 'bcd234', 'cde345', 'abc123']), ('konachan', [10, 11, 12, 10])]:
                script = root / f'random_{provider}_wall.sh'
                shutil.copyfile(scripts / script.name, script)
                for image_id in ids:
                    url = f'https://example.invalid/{image_id}.jpg?size=large'
                    response = ({'data': [{'id': image_id, 'ratio': '1.78', 'path': url}]} if provider == 'wallhaven'
                                else [{'id': image_id, 'file_url': url}])
                    result = subprocess.run(['bash', str(script)], capture_output=True, text=True, check=True,
                                            env={**os.environ, 'HOME': directory, 'ORIGINAL_RANDOM': str(scripts),
                                                 'XDG_CONFIG_HOME': str(root / 'config'), 'API_RESPONSE': json.dumps(response)})
                    path = Path(result.stdout.strip())
                    self.assertEqual(path.name, f'{provider.capitalize()}-{image_id}.jpg')
                    saved[url] = path
            self.assertEqual(len(set(saved.values())), 6)
            for url, path in saved.items():
                self.assertEqual(path.read_text(), url)

    @unittest.skipUnless(QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
    def test_image_transitions(self):
        with tempfile.TemporaryDirectory(prefix='velora-wallpaper-') as directory:
            root = Path(directory)
            shutil.copy2(SHELL / 'modules/common/widgets/WallpaperFader.qml', root)
            shutil.copy2(SHELL / 'modules/common/widgets/WallpaperGeometry.qml', root)
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
            (root / 'Process.qml').write_text('import QtQuick\nQtObject { property var command; property bool running; signal exited(int code) }\n')
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
        spec = importlib.util.spec_from_file_location('wallpaper_analysis', Path(__file__).parent / 'fixtures/legacy/least_busy_region.py')
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

    def test_different_widget_sizes_and_strategies_avoid_actual_bounds(self):
        image = np.random.default_rng(82).integers(0, 256, (600, 900, 3), dtype=np.uint8)
        image[210:500, 340:650] = 20
        cv2.imwrite(str(self.path), image)
        occupied = []
        for width, height, busiest in ((230, 260, False), (200, 200, False), (310, 160, True)):
            x, y = self.analysis.find_least_busy_region(
                str(self.path), width, height, stride=10, horizontal_padding=100,
                vertical_padding=100, busiest=busiest, avoid_rects=occupied)[0]
            for ox, oy, ow, oh in occupied:
                self.assertTrue(x + width <= ox or ox + ow <= x or y + height <= oy or oy + oh <= y,
                                ((x, y, width, height), occupied))
            occupied.append((x, y, width, height))

    def test_compact_screen_relaxes_spacing_before_covering_a_widget(self):
        cv2.imwrite(str(self.path), np.zeros((240, 410, 3), dtype=np.uint8))
        coords, _ = self.analysis.find_least_busy_region(
            str(self.path), 200, 200, stride=10, horizontal_padding=100, vertical_padding=100,
            avoid_rects=[(0, 0, 210, 240)])
        self.assertEqual(coords, (210, 0))

    def test_exact_fit_between_stride_samples(self):
        cv2.imwrite(str(self.path), np.zeros((100, 209, 3), dtype=np.uint8))
        coords, _ = self.analysis.find_least_busy_region(
            str(self.path), 100, 100, stride=10, horizontal_padding=0, vertical_padding=0,
            avoid_rects=[(0, 0, 103, 100), (203, 0, 6, 100)])
        self.assertEqual(coords, (103, 0))


@unittest.skipUnless(shutil.which('jq') and shutil.which('flock'), 'Wallpaper switching needs jq and flock')
class WallpaperSwitchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='velora-switchwall-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'config/velora/config.json'
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
        binaries = self.root / 'bin'
        binaries.mkdir()
        helpers = {
            'hyprctl': 'if [ "$1" = monitors ]; then echo \'[{"focused":true,"scale":1,"x":0,"y":0,"width":1920,"height":1080}]\'; else echo \'{"x":0,"y":0}\'; fi',
            'magick': 'echo "$*" >> "$WALLPAPER_TEST_PROBES"; if [[ "$*" == *a.svg* ]]; then touch "$WALLPAPER_TEST_STARTED"; sleep 0.4; fi',
            'identify': 'if [[ "$*" == *%w* ]]; then echo 1920; else echo 1080; fi',
            'bc': 'cat >/dev/null; echo 0',
            'gsettings': 'exit 0',
            'matugen': 'echo "palette:$(jq -r .background.wallpaperPath "$WALLPAPER_TEST_CONFIG")" >> "$WALLPAPER_TEST_EVENTS"; echo \'{"colors":{"source_color":{"default":{"color":"#336699"}}}}\'',
            'fake-palette': 'echo "terminal:$(jq -r .background.wallpaperPath "$WALLPAPER_TEST_CONFIG")" >> "$WALLPAPER_TEST_EVENTS"; echo material',
            'xdg-user-dir': 'printf "%s\\n" "$WALLPAPER_TEST_PICTURES"',
            'kdialog': 'printf "%s\\n" "$PWD" >> "$WALLPAPER_TEST_PICKER_CALLS"; printf "%s\\n" "$WALLPAPER_TEST_PICKER_IMAGE"; exit "${WALLPAPER_TEST_PICKER_EXIT:-0}"',
        }
        for name, body in helpers.items():
            path = binaries / name
            path.write_text('#!/usr/bin/env bash\n' + body + '\n')
            path.chmod(0o755)
        (self.root / 'helper').symlink_to(binaries / 'fake-palette')
        self.events = self.root / 'events'
        self.probes = self.root / 'probes'
        self.started = self.root / 'started'
        self.pictures = self.root / 'Pictures'
        self.pictures.mkdir()
        self.picker_calls = self.root / 'picker-calls'
        self.env = {**os.environ, 'PATH': str(binaries) + os.pathsep + os.environ['PATH'],
                    'XDG_CONFIG_HOME': str(self.root / 'config'), 'XDG_STATE_HOME': str(self.root / 'state'),
                    'XDG_CACHE_HOME': str(self.root / 'cache'),
                    'WALLPAPER_TEST_CONFIG': str(self.config), 'WALLPAPER_TEST_EVENTS': str(self.events),
                    'WALLPAPER_TEST_PROBES': str(self.probes), 'WALLPAPER_TEST_STARTED': str(self.started),
                    'WALLPAPER_TEST_PICTURES': str(self.pictures), 'WALLPAPER_TEST_PICKER_CALLS': str(self.picker_calls),
                    'WALLPAPER_TEST_PICKER_IMAGE': '', 'WALLPAPER_TEST_PICKER_EXIT': '0',
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

    def test_picker_opens_with_or_without_a_saved_accent(self):
        image = self.pictures / 'chosen wallpaper.svg'
        image.write_text('<svg/>')
        for accent in ('', '#FF6D00'):
            with self.subTest(accent=accent):
                config = json.loads(self.config.read_text())
                config['appearance']['palette']['accentColor'] = accent
                config['background']['wallpaperPath'] = 'old'
                self.config.write_text(json.dumps(config))
                self.picker_calls.unlink(missing_ok=True)

                # The settings button invokes switchwall with no arguments.
                self.run_switch(env={**self.env, 'WALLPAPER_TEST_PICKER_IMAGE': str(image)})

                self.assertTrue(self.picker_calls.exists(), 'Choose wallpaper did not open the file picker')
                updated = json.loads(self.config.read_text())
                self.assertEqual(updated['background']['wallpaperPath'], str(image))
                self.assertEqual(updated['appearance']['palette']['accentColor'], '')

    def test_cancelled_picker_leaves_theme_and_queued_request_unchanged(self):
        config = json.loads(self.config.read_text())
        config['appearance']['palette']['accentColor'] = '#FF6D00'
        self.config.write_text(json.dumps(config))
        request = self.root / 'cache/quickshell/wallpaper-request'
        request.parent.mkdir(parents=True)
        request.write_text('existing-request')
        for exit_code in ('0', '1'):
            with self.subTest(exit_code=exit_code):
                self.picker_calls.unlink(missing_ok=True)
                self.run_switch(env={**self.env, 'WALLPAPER_TEST_PICKER_EXIT': exit_code})
                self.assertTrue(self.picker_calls.exists(), 'Choose wallpaper did not open the file picker')
                self.assertEqual(json.loads(self.config.read_text()), config)
                self.assertEqual(request.read_text(), 'existing-request')
                self.assertFalse(self.events.exists(), 'Cancelling the picker regenerated the theme')

    def test_color_and_mode_changes_do_not_open_the_picker(self):
        for args in (('--color', '#FF6D00'), ('--mode', 'dark', '--noswitch')):
            with self.subTest(args=args):
                self.run_switch(*args, env=self.env)
                self.assertFalse(self.picker_calls.exists())
                self.assertEqual(json.loads(self.config.read_text())['background']['wallpaperPath'], 'old')

    @unittest.skipUnless(shutil.which('matugen'), 'requires matugen for real scheme generation')
    def test_explicit_schemes_recolor_legacy_install_and_preserve_wallpaper(self):
        legacy = self.root / 'config/illogical-impulse/config.json'
        legacy.parent.mkdir()
        self.config.rename(legacy)
        config = json.loads(legacy.read_text())
        config['background'].update(wallpaperPath=str(SHELL / 'assets/images/autumn.jpg'),
                                    shaderWallpaper={'name': 'aurora'})
        config['appearance']['wallpaperTheming']['enableAppsAndShell'] = False
        config['appearance']['palette']['roleOverrides'] = {'surface_container': '#291D17'}
        legacy.write_text(json.dumps(config))

        matugen = self.root / 'bin/matugen'
        matugen.unlink()
        matugen.symlink_to(shutil.which('matugen'))
        templates = self.root / 'config/matugen'
        templates.mkdir()
        output = self.root / 'colors.json'
        (templates / 'config.toml').write_text(
            f'[config]\n[templates.shell]\ninput_path = "{PROJECT / "dots/.config/matugen/templates/colors.json"}"\n'
            f'output_path = "{output}"\n')
        env = {**self.env, 'HOME': str(self.root), 'WALLPAPER_TEST_CONFIG': str(legacy)}
        self.run_switch('--noswitch', '--type', 'scheme-monochrome', '--mode', 'dark', env=env)
        mono = json.loads(output.read_text())
        self.run_switch('--noswitch', '--type', 'scheme-expressive', '--mode', 'dark', env=env)
        expressive = json.loads(output.read_text())
        for role in ['primary', 'primary_container', 'secondary', 'tertiary']:
            self.assertEqual(len(set(mono[role][i:i + 2] for i in (1, 3, 5))), 1, role)
            self.assertNotEqual(mono[role], expressive[role], role)
        self.assertEqual(json.loads(legacy.read_text()), config)
        self.assertFalse(self.config.exists())
        self.assertFalse(self.picker_calls.exists())

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
