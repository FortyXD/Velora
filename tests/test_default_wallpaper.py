"""Exercise bundled wallpaper startup offline with real QML and inert IO adapters."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import test_velora

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
QT_TEST_RUNNER = shutil.which('qmltestrunner6') or next(
    (str(path) for path in (Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner'))
     if path.is_file()), None)


class DefaultWallpaperTests(unittest.TestCase):
    def test_three_bundled_wallpapers_are_available_offline_with_attribution(self):
        pictures = {}
        for path in (SHELL / 'defaults/presets').glob('*.json'):
            preset = json.loads(path.read_text())
            if preset.get('wallpaperAnimations', {}).get('wallpaper'):
                pictures[path.stem] = preset
                for key, value in (('preview', preset['wallpaperPreview']),
                                   ('wallpaper', preset['wallpaperAnimations']['wallpaper'])):
                    self.assertTrue((path.parent / value).resolve().is_file(), (path.name, key))
                self.assertTrue(preset['credits']['author'])
                self.assertTrue(preset['credits']['licenseUrl'])
        self.assertEqual(set(pictures), {'autumn', 'komona-sunset', 'mountain-night'})

    def test_bundled_preset_paths_resolve_inside_the_shell(self):
        preset_path = SHELL / 'defaults/presets/autumn.json'
        preset = json.loads(preset_path.read_text())
        image = SHELL / 'assets/images/autumn.jpg'
        for value in (preset['wallpaperPreview'], preset['wallpaperAnimations']['wallpaper']):
            self.assertEqual((preset_path.parent / value).resolve(), image)
        self.assertGreater(image.stat().st_size, 100_000)
        self.assertEqual(image.read_bytes()[:3], b'\xff\xd8\xff')
        self.assertEqual(preset['credits']['author'], 'Josef Bartoň (JoeyJazz)')
        self.assertEqual(preset['credits']['restrictions'], 'Commercial use of this artwork by third parties is not permitted.')

    def test_fresh_install_links_the_local_asset_and_repeat_keeps_the_users_choice(self):
        fixture = test_velora.InstallerTests('test_install_and_repeat_preserve_existing_shell_settings')
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        for relative in ('dots/.config/quickshell/ii/assets/images/autumn.jpg',
                         'dots/.config/quickshell/ii/defaults/presets/autumn.json',
                         'dots/.config/illogical-impulse/config.example.json'):
            destination = fixture.repo / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(PROJECT / relative, destination)
        result = fixture.link()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        linked_shell = Path(fixture.env['XDG_CONFIG_HOME']) / 'quickshell/ii'
        preset_path = linked_shell / 'defaults/presets/autumn.json'
        preset = json.loads(preset_path.read_text())
        wallpaper = preset_path.parent / preset['wallpaperAnimations']['wallpaper']
        self.assertEqual(wallpaper.read_bytes(), (SHELL / 'assets/images/autumn.jpg').read_bytes())
        config_path = Path(fixture.env['XDG_CONFIG_HOME']) / 'illogical-impulse/config.json'
        config = json.loads(config_path.read_text())
        config['background']['wallpaperPath'] = '/pictures/personal.jpg'
        config_path.write_text(json.dumps(config))
        result = fixture.link()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(config_path.read_text())['background']['wallpaperPath'], '/pictures/personal.jpg')

    @unittest.skipUnless(QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
    def test_first_frame_empty_config_and_existing_wallpaper(self):
        with tempfile.TemporaryDirectory(prefix='velora-wallpaper-') as directory:
            root = Path(directory)
            for name, relative in {
                'Config': 'modules/common/Config.qml',
                'Directories': 'modules/common/Directories.qml',
                'FirstRunExperience': 'services/FirstRunExperience.qml',
            }.items():
                source = '\n'.join(line for line in (SHELL / relative).read_text().splitlines()
                                   if not line.startswith(('import qs', 'import Quickshell')))
                source = source.replace('../../services/ai/PromptDefaults.js', 'PromptDefaults.js')
                for component in ('configFileView', 'firstRunFile', 'initialWallpaper', 'onboardingState'):
                    source = source.replace(f'id: {component}\n', f'id: {component}\n        objectName: "{component}"\n')
                (root / f'{name}.qml').write_text(source)
            shutil.copy2(SHELL / 'services/ai/PromptDefaults.js', root / 'PromptDefaults.js')
            (root / 'Singleton.qml').write_text('import QtQuick\nQtObject { default property list<QtObject> content }')
            (root / 'JsonObject.qml').write_text('import QtQuick\nQtObject {}')
            (root / 'JsonAdapter.qml').write_text('import QtQuick\nQtObject {}')
            (root / 'Process.qml').write_text('import QtQuick\nQtObject { property bool running; property var command; signal exited(int code, int status) }')
            (root / 'FileView.qml').write_text('''import QtQuick
                QtObject {
                    default property list<QtObject> content
                    property var path; property bool printErrors; property bool watchChanges; property bool blockWrites
                    property string value; property int writes; property int reloads
                    signal fileChanged(); signal adapterUpdated(); signal loaded(); signal saveFailed(int error); signal loadFailed(int error)
                    function reload() { reloads++; } function writeAdapter() { writes++; }
                    function setText(value) { this.value=value; writes++; } function text() { return value; }
                }''')
            stubs = {
                'Quickshell': 'property int processId:42; property var detached: []; function execDetached(command) { detached=detached.concat([command]); } function shellPath(path) { return ' + json.dumps(str(SHELL) + '/') + '+path; }',
                'FileUtils': 'function trimFileProtocol(path) { return path.replace(/^file:\\/\\//, ""); }',
                'Translation': 'function tr(text) { return text; }',
                'Appearance': 'property var font: ({pixelSize:{smaller:12}})',
                'SystemInfo': 'property string username:"isolated-test"',
                'FileViewError': 'enum Error { FileNotFound }',
            }
            for name, body in stubs.items():
                (root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}')
            (root / 'qmldir').write_text('\n'.join(f'singleton {name} 1.0 {name}.qml'
                                                for name in ('Config', 'Directories', 'FirstRunExperience', *stubs)))
            (root / 'tst_wallpaper.qml').write_text('''import QtQuick
                import QtTest
                TestCase {
                    name: "BundledWallpaper"
                    Image { id: picture; source: "file://" + Directories.defaultWallpaper }
                    function test_a_first_frame_has_a_decodable_local_image() {
                        compare(Config.ready, false);
                        compare(Config.options.background.wallpaperPath, Directories.defaultWallpaper);
                        tryCompare(picture, "status", Image.Ready);
                        compare(picture.sourceSize.width, 2560);
                        compare(picture.sourceSize.height, 1440);
                    }
                    function test_b_missing_config_is_ready_with_the_local_default() {
                        const config = findChild(Config, "configFileView");
                        config.loadFailed(FileViewError.FileNotFound);
                        verify(Config.ready);
                        compare(config.writes, 1);
                        compare(Config.options.background.wallpaperPath, Directories.defaultWallpaper);
                    }
                    function test_c_empty_example_config_gets_the_default_but_custom_path_is_preserved() {
                        const config = findChild(Config, "configFileView");
                        Config.options.background.wallpaperPath = "";
                        config.loaded();
                        compare(Config.options.background.wallpaperPath, Directories.defaultWallpaper);
                        Config.options.background.wallpaperPath = "/pictures/my own choice.jpg";
                        config.loaded();
                        compare(Config.options.background.wallpaperPath, "/pictures/my own choice.jpg");
                    }
                    function test_c_retired_bundled_images_migrate_but_personal_names_are_preserved() {
                        const config = findChild(Config, "configFileView");
                        for (const path of [
                            "/home/user/.config/quickshell/ii/assets/images/default_wallpaper.png"
                        ]) {
                            Config.options.background.wallpaperPath = path;
                            config.loaded();
                            compare(Config.options.background.wallpaperPath, Directories.defaultWallpaper);
                        }
                        Config.options.background.wallpaperPath = "/pictures/autumn.jpg";
                        config.loaded();
                        compare(Config.options.background.wallpaperPath, "/pictures/autumn.jpg");
                        Config.options.background.wallpaperPath = "/pictures/my own choice.jpg";
                    }
                    function test_d_first_run_waits_for_config_and_preserves_existing_wallpaper() {
                        const first = findChild(FirstRunExperience, "firstRunFile");
                        const job = findChild(FirstRunExperience, "initialWallpaper");
                        Config.ready = false;
                        FirstRunExperience.decide(false);
                        compare(first.writes, 0);
                        verify(!job.running);
                        Config.ready = true;
                        Quickshell.detached = [];
                        FirstRunExperience.decide(false);
                        verify(!job.running);
                        compare(Quickshell.detached.length, 1);
                        compare(Quickshell.detached[0][0], "qs");
                        compare(Config.options.background.wallpaperPath, "/pictures/my own choice.jpg");
                    }
                    function test_e_new_desktop_initializes_colors_from_the_bundled_image() {
                        FirstRunExperience.onboardingOpened = false;
                        Quickshell.detached = [];
                        Config.options.background.wallpaperPath = Directories.defaultWallpaper;
                        FirstRunExperience.decide(false);
                        const job = findChild(FirstRunExperience, "initialWallpaper");
                        verify(job.running);
                        compare(job.command, [Directories.wallpaperSwitchScriptPath, Directories.defaultWallpaper]);
                        compare(Quickshell.detached.length, 0);
                        job.running = false;
                        wait(20);
                        compare(Quickshell.detached.length, 0);
                        job.exited(0, 0);
                        tryCompare(FirstRunExperience, "onboardingOpened", true);
                        compare(Quickshell.detached.length, 1);
                        // Config and FileView callbacks can repeat during first-run writes.
                        FirstRunExperience.openOnboarding();
                        job.exited(0, 0);
                        wait(20);
                        compare(Quickshell.detached.length, 1);
                    }
                }''')
            result = subprocess.run([QT_TEST_RUNNER, '-input', str(root), '-o', '-,txt'],
                                    env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen',
                                         'QT_QPA_PLATFORMTHEME': 'generic', 'QT_QUICK_BACKEND': 'software'},
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotRegex(result.stdout + result.stderr, 'ReferenceError|TypeError')


if __name__ == '__main__':
    unittest.main()
