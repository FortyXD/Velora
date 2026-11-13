"""Run in the QEMU guest: python -m unittest discover -s tests -p test_desktop_extras.py."""
import asyncio
import importlib.util
import json
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


quicklook = module('quicklook', 'dots/.config/quickshell/ii/scripts/quicklook.py')
previews = module('previews', 'dots/.config/quickshell/ii/scripts/window-previews.py')
greeter = module('greeter_test', 'scripts/greeter.py')
kde = module('kde_test', 'scripts/kde.py')
kde_theme = module('kde_theme', 'dots/.config/quickshell/ii/scripts/colors/kde-theme.py')


class QuickLookTests(unittest.TestCase):
    def test_local_formats_and_bounds(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            text = directory / 'кириллица и пробелы.txt'
            text.write_text('строка\n' * 100000)
            result = quicklook.describe(text, directory)
            self.assertEqual(result['kind'], 'text')
            self.assertTrue(result['truncated'])
            picture = directory / 'image.png'
            Image.new('RGB', (120, 60), 'red').save(picture)
            self.assertEqual(quicklook.describe(picture, directory)['width'], 120)
            pdf = directory / 'paper.pdf'
            Image.new('RGB', (120, 60), 'white').save(pdf)
            result = quicklook.describe(pdf, directory)
            self.assertEqual(result['kind'], 'pdf')
            self.assertTrue((directory / 'page-1.png').exists())
            archive = directory / 'test.zip'
            with zipfile.ZipFile(archive, 'w') as output:
                output.writestr('../never-extracted.txt', 'hello')
            self.assertIn('never-extracted', quicklook.describe(archive, directory)['text'])
            self.assertFalse((directory.parent / 'never-extracted.txt').exists())
            pdf.write_bytes(b'%PDF-1.7 broken')
            self.assertEqual(quicklook.describe(pdf, directory)['kind'], 'other')
            self.assertIn('error', quicklook.describe(directory / 'missing', directory))


class CaptureTests(unittest.IsolatedAsyncioTestCase):
    async def test_unchanged_frames_are_not_published_again(self):
        events = []
        pixels = b'first frame'
        calls = 0
        async def capture(spec, path):
            nonlocal calls
            calls += 1
            path.write_bytes(pixels)
            return 80, 40
        with tempfile.TemporaryDirectory() as directory, patch.object(previews, 'emit', events.append):
            broker = previews.Broker(directory, capture)
            await broker.set_windows([{'id':'ab', 'live':True}])
            await asyncio.sleep(.4)
            self.assertGreaterEqual(calls, 3)
            self.assertEqual(sum(e['event'] == 'frame' for e in events), 1)
            pixels = b'new frame'
            await asyncio.sleep(.55)
            self.assertEqual(sum(e['event'] == 'frame' for e in events), 2)
            await broker.close()
            self.assertFalse(list(Path(directory).iterdir()))

    async def test_many_visible_windows_share_a_capture_budget(self):
        starts = []
        async def capture(spec, path):
            starts.append(asyncio.get_running_loop().time())
            path.write_bytes(str(len(starts)).encode())
            return 80, 40
        with tempfile.TemporaryDirectory() as directory, patch.object(previews, 'emit'):
            broker = previews.Broker(directory, capture)
            await broker.set_windows([{'id':f'{i:x}', 'live':True} for i in range(12)])
            await asyncio.sleep(.58)
            await broker.close()
        self.assertGreaterEqual(len(starts), 5)
        self.assertLessEqual(len(starts), 10)
        self.assertTrue(all(b - a >= .055 for a, b in zip(starts, starts[1:])))

    async def test_concurrency_rate_still_and_cleanup(self):
        active = set()
        peak = 0
        calls = {}
        events = []

        async def capture(spec, path):
            nonlocal peak
            identifier = spec['id']
            self.assertNotIn(identifier, active)
            active.add(identifier)
            peak = max(peak, len(active))
            calls[identifier] = calls.get(identifier, 0) + 1
            try:
                await asyncio.sleep(.025)
                path.write_bytes(b'frame')
                return 80, 40
            finally:
                active.remove(identifier)

        with tempfile.TemporaryDirectory() as directory, patch.object(previews, 'emit', events.append):
            broker = previews.Broker(directory, capture)
            specs = [{'id': hex(index)[2:], 'live': index != 1} for index in range(1, 6)]
            await broker.set_windows(specs)
            await asyncio.sleep(.58)
            await broker.set_windows(specs)  # Identical subscriptions must not restart still captures.
            await asyncio.sleep(.20)
            self.assertEqual(calls['1'], 1)
            self.assertLessEqual(peak, 2)
            self.assertLessEqual(max(calls.values()), 7)
            await broker.set_windows([])
            count = len(events)
            await asyncio.sleep(.15)
            self.assertEqual(len(events), count)
            self.assertFalse(active)
            self.assertFalse(list(Path(directory).iterdir()))
            await broker.close()

    async def test_error_keeps_last_frame(self):
        counter = 0

        async def capture(spec, path):
            nonlocal counter
            counter += 1
            if counter > 1:
                raise RuntimeError('window busy')
            path.write_bytes(b'last good frame')
            return 80, 40

        events = []
        with tempfile.TemporaryDirectory() as directory, patch.object(previews, 'emit', events.append):
            broker = previews.Broker(directory, capture)
            await broker.set_windows([{'id': 'ab', 'live': True}])
            await asyncio.sleep(.3)
            frame = next(event for event in events if event['event'] == 'frame')
            self.assertTrue(Path(frame['path']).exists())
            await broker.close()


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
        result = kde_theme.palette(colors)
        self.assertEqual(result['Colors:Selection']['BackgroundNormal'], '#ffb692')
        self.assertEqual(result['Colors:Selection']['ForegroundNormal'], '#261812')
        self.assertNotIn('Icons', result)
        colors['background'] = 'bad color'
        with self.assertRaises(ValueError):
            kde_theme.palette(colors)

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
