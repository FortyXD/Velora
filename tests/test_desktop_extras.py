"""Run in the QEMU guest: python -m unittest discover -s tests -p test_desktop_extras.py."""
import asyncio
import importlib.util
import json
import os
import subprocess
from native_helper import binary
from preview_broker import PreviewBroker
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from test_velora import velora

ROOT = Path(__file__).resolve().parents[1]


def module(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def describe(path, directory):
    return json.loads(subprocess.check_output([binary(), 'quicklook', '--directory', directory, '--', path]))

greeter = module('greeter_test', 'scripts/greeter.py')
kde = module('kde_test', 'scripts/kde.py')


class QuickLookTests(unittest.TestCase):
    def test_local_formats_and_bounds(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            text = directory / 'кириллица и пробелы.txt'
            text.write_text('строка\n' * 100000)
            result = describe(text, directory)
            self.assertEqual(result['kind'], 'text')
            self.assertTrue(result['truncated'])
            picture = directory / 'image.png'
            Image.new('RGB', (120, 60), 'red').save(picture)
            self.assertEqual(describe(picture, directory)['width'], 120)
            pdf = directory / 'paper.pdf'
            Image.new('RGB', (120, 60), 'white').save(pdf)
            result = describe(pdf, directory)
            self.assertEqual(result['kind'], 'pdf')
            self.assertTrue((directory / 'page-1.png').exists())
            archive = directory / 'test.zip'
            with zipfile.ZipFile(archive, 'w') as output:
                output.writestr('../never-extracted.txt', 'hello')
            self.assertIn('never-extracted', describe(archive, directory)['text'])
            self.assertFalse((directory.parent / 'never-extracted.txt').exists())
            pdf.write_bytes(b'%PDF-1.7 broken')
            self.assertEqual(describe(pdf, directory)['kind'], 'other')
            self.assertIn('error', describe(directory / 'missing', directory))


class CaptureTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        from PIL import Image
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        (self.root / 'runtime').mkdir(mode=0o700)
        self.image = self.root / 'frame.png'
        Image.new('RGB', (80,40), 'red').save(self.image)
        fake = self.root / 'grim'
        fake.write_text("""#!/usr/bin/python3
import json,os,pathlib,sys,time
root=pathlib.Path(os.environ['PREVIEW_TEST'])
identifier=sys.argv[sys.argv.index('-T')+1]
def record(event):
    with (root/'calls').open('a') as log:
        print(json.dumps([event, identifier, time.monotonic()]),file=log)
record('start')
time.sleep(.025)
if (root/'failed').exists(): sys.exit(1)
sys.stdout.buffer.write((root/'frame.png').read_bytes())
record('finish')
""")
        fake.chmod(0o755)
        self.events = []
        self.broker = PreviewBroker(binary(), self.events.append, {
            **os.environ, 'PATH': str(self.root) + ':' + os.environ['PATH'],
            'XDG_RUNTIME_DIR': str(self.root / 'runtime'), 'PREVIEW_TEST': str(self.root)})
        self.addAsyncCleanup(self.broker.close)

    def calls(self):
        path = self.root / 'calls'
        return [json.loads(l) for l in path.read_text().splitlines()] if path.exists() else []

    async def until(self, condition):
        for _ in range(150):
            if condition(): return
            await asyncio.sleep(.02)
        self.fail(f"Timed out; events={self.events}")

    async def test_unchanged_frames_are_not_published_again(self):
        from PIL import Image
        await self.broker.set_windows([{'id':'ab', 'live':True}])
        await self.until(lambda: len(self.calls())>=6)
        self.assertEqual(len(self.events), 1)
        frame = self.events[0]
        with Image.open(frame['path']) as image:
            self.assertTrue(0 < image.width <= 280 and 0 < image.height <= 180)
        Image.new('RGB', (80,40), 'green').save(self.image)
        await self.until(lambda: len(self.events)>=2)
        self.assertNotEqual(frame['path'], self.events[1]['path'])

    async def test_concurrency_rate_still_and_cleanup(self):
        specs = [{'id':format(i,'x'), 'live':i!=1, 'generation':3} for i in range(1,11)]
        await self.broker.set_windows(specs)
        await self.until(lambda: len(self.events)>=len(specs))
        await self.broker.set_windows(specs)
        await asyncio.sleep(.4)
        calls = self.calls()
        starts = [c for c in calls if c[0]=='start']
        self.assertEqual(sum(c[1]=='1' for c in starts), 1)
        active = set()
        for op, identifier, stamp in calls:
            if op=='start':
                self.assertNotIn(identifier, active)
                active.add(identifier)
                self.assertLessEqual(len(active), 2)
            else:
                active.remove(identifier)
        # Launch jitter of the executable can shift observed timestamps by one frame.
        self.assertLessEqual(len(starts), 5 + 16*(starts[-1][2]-starts[0][2]))
        self.assertTrue(all(e['generation']==3 for e in self.events))
        await self.broker.set_windows([])
        count = len(self.events)
        await asyncio.sleep(.25)
        self.assertEqual(count, len(self.events))
        self.assertFalse(list((self.root/'runtime').rglob('*.png')))

    async def test_error_keeps_last_frame(self):
        await self.broker.set_windows([{'id':'ab', 'live':True}])
        await self.until(lambda: len(self.events)>0)
        last = Path(self.events[0]['path'])
        (self.root/'failed').touch()
        await self.until(lambda: any(e['event']=='error' for e in self.events))
        self.assertTrue(last.is_file())


class ConfigurationTests(unittest.TestCase):
    def test_unchanged_greeter_update_does_not_request_root(self):
        with patch.object(velora.greeter, 'version', return_value='51.1'), \
                patch.object(velora.greeter, 'is_current', return_value=True), patch.object(velora, 'run') as run:
            velora.configure_greeter('velora')
        run.assert_not_called()

    def test_changed_greeter_update_requires_normal_system_install(self):
        with patch.object(velora.greeter, 'version', return_value='51.1'), \
                patch.object(velora.greeter, 'is_current', return_value=False), patch.object(velora, 'run') as run:
            velora.configure_greeter('velora')
        self.assertEqual(run.call_args.args[0][:4], ['sudo', 'python3', '-I', ROOT / 'scripts/greeter.py'])

    def test_greeter_receipt_detects_changed_source_missing_files_and_restore(self):
        is_dir = Path.is_dir
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(Path, 'is_dir', autospec=True,
                              side_effect=lambda path: path == Path('/usr/share/gdm') or is_dir(path)), \
                    patch.object(greeter, 'STATE', root / 'state'), \
                    patch.object(greeter, 'EXTENSION', root / 'extension'), \
                    patch.object(greeter, 'PROFILE', root / 'profile'), \
                    patch.object(greeter, 'SETTINGS', root / 'settings'), \
                    patch.object(greeter, 'version', return_value='51.1'), \
                    patch.object(greeter, 'enabled_extensions', return_value=[greeter.UUID]), \
                    patch.object(greeter, 'SYNC_CONFIG', root / 'sync.json'), \
                    patch.object(greeter, 'SYNC_STATE', root / 'sync-state'), \
                    patch.object(greeter, 'SYNC_FILES', {key: root / ('sync-' + str(index)) for index, key in enumerate(greeter.SYNC_FILES)}), \
                    patch.object(greeter, 'SYNC_SYSUSERS', root / 'sysusers'), \
                    patch.object(greeter, 'SYNC_SYSTEM_WANTS', root / 'system-wants'), \
                    patch.object(greeter, 'SYNC_USER_WANTS', root / 'user-wants'), \
                    patch.object(greeter.subprocess, 'run'):
                self.assertFalse(greeter.is_current(ROOT))
                self.assertTrue(greeter.apply(ROOT, 1000))
                self.assertTrue(greeter.is_current(ROOT))
                with patch.object(greeter, 'source_fingerprint', return_value='changed source'):
                    self.assertFalse(greeter.is_current(ROOT))
                (root / 'extension/autumn.jpg').unlink()
                self.assertFalse(greeter.is_current(ROOT))
                greeter.restore()
                self.assertFalse((root / 'state/current.json').exists())
                self.assertFalse(greeter.is_current(ROOT))

    def test_kde_palette_preserves_material_roles_and_rejects_invalid_colors(self):
        colors = {key: '#332211' for key in ('background', 'on_surface', 'inverse_surface', 'inverse_on_surface',
                  'primary', 'on_primary', 'on_surface_variant', 'tertiary', 'secondary', 'error')}
        colors['primary'] = '#ffb692'
        colors['on_primary'] = '#261812'
        import configparser
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            generated = root / 'quickshell/user/generated'
            generated.mkdir(parents=True)
            for name in ('kwriteconfig6', 'dbus-send'):
                (root/name).write_text('#!/bin/sh\nexit 0\n')
                (root/name).chmod(0o755)
            env = {**os.environ, 'XDG_CONFIG_HOME':folder, 'XDG_STATE_HOME':folder,
                   'XDG_DATA_HOME':folder, 'PATH':folder}
            source = generated / 'colors.json'
            source.write_text(json.dumps(colors))
            subprocess.run([binary(), 'kde-theme'], env=env, check=True)
            scheme = configparser.ConfigParser()
            scheme.read(root / 'color-schemes/Velora.colors')
            self.assertEqual(scheme['Colors:Selection']['BackgroundNormal'], '#ffb692')
            self.assertEqual(scheme['Colors:Selection']['ForegroundNormal'], '#261812')
            self.assertNotIn('Icons', scheme)
            colors['background'] = 'bad color'
            source.write_text(json.dumps(colors))
            failed = subprocess.run([binary(), 'kde-theme'], env=env, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)

    def test_additive_toolbar_is_idempotent(self):
        xml = '<gui><ToolBar name="mainToolBar"><Action name="custom"/><Action name="hamburger_menu"/></ToolBar></gui>'
        result = kde.dolphin_toolbar(xml)
        self.assertEqual(kde.dolphin_toolbar(result), result)
        self.assertIn('name="custom"', result)
        self.assertLess(result.index('name="create_dir"'), result.index('name="hamburger_menu"'))

    def test_greeter_reinstall_preserves_original_backup_and_restore(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / 'profile'
            original.write_bytes(b'previous profile')
            added = root / 'new-file'
            with patch.object(greeter, 'STATE', root / 'state'), patch.object(greeter.subprocess, 'run'):
                first = greeter.Transaction()
                first.write(original, b'first install')
                first.write(added, b'added')
                second = greeter.Transaction()
                second.write(original, b'upgrade')
                greeter.restore()
                self.assertEqual(original.read_bytes(), b'previous profile')
                self.assertFalse(added.exists())
                greeter.restore()

    def test_unsupported_gnome_never_writes_system_files(self):
        with patch.object(greeter, 'version', return_value='999'), patch.object(greeter, 'Transaction') as transaction:
            self.assertFalse(greeter.apply(ROOT))
            transaction.assert_not_called()
