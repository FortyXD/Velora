"""Run exclusively in QEMU, including the real bubblewrap image decoder."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bridge', ROOT / 'scripts/greeter_wallpaper.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class ProtocolTests(unittest.TestCase):
    def read(self, data):
        left, right = socket.socketpair()
        with left, right:
            left.sendall(data)
            left.shutdown(socket.SHUT_WR)
            return bridge.read_frame(right)

    def test_rgb_and_clear(self):
        self.assertEqual(self.read(bridge.HEADER.pack(b'VRG1', 1, 1) + b'abc'), (1, 1, b'abc'))
        self.assertIsNone(self.read(bridge.HEADER.pack(b'VCLR', 0, 0)))

    def test_bounds_magic_truncated_trailing_and_paths(self):
        for data in (b'/etc/passwd', bridge.HEADER.pack(b'JPEG', 1, 1),
                     bridge.HEADER.pack(b'VRG1', 0, 1), bridge.HEADER.pack(b'VRG1', 2561, 1),
                     bridge.HEADER.pack(b'VRG1', 2560, 2560), bridge.HEADER.pack(b'VRG1', 1, 1) + b'a',
                     bridge.HEADER.pack(b'VRG1', 1, 1) + b'abcd', bridge.HEADER.pack(b'VCLR', 0, 1)):
            with self.subTest(data=data), self.assertRaises(ValueError):
                self.read(data)

    def test_wrong_uid_rejected_before_payload_or_logind(self):
        left, right = socket.socketpair()
        with left, right, patch.object(bridge, 'active_desktop') as active:
            with self.assertRaises(PermissionError):
                bridge.handle(right, os.getuid() + 1)
            active.assert_not_called()

    def test_inactive_account_rejected(self):
        left, right = socket.socketpair()
        with left, right, patch.object(bridge, 'active_desktop', return_value=None):
            with self.assertRaises(PermissionError):
                bridge.handle(right, os.getuid())

    def test_rate_limit(self):
        left, right = socket.socketpair()
        with left, right, patch.object(bridge, 'active_desktop', return_value='Hyprland'):
            with self.assertRaises(ValueError):
                bridge.handle(right, os.getuid(), bridge.time.monotonic())

    def test_absolute_receive_deadline(self):
        left, right = socket.socketpair()
        with left, right, self.assertRaises(TimeoutError):
            bridge.receive(right, 1, bridge.time.monotonic() - 1)


class AuthorizationTests(unittest.TestCase):
    def session(self, **overrides):
        props = dict(User='1000', Active='yes', Remote='no', Class='user', Type='wayland',
                     Seat='seat0', LockedHint='no', Desktop='GNOME')
        props.update(overrides)
        return '\n'.join(k + '=' + v for k, v in props.items())

    def test_only_local_unlocked_graphical_owner(self):
        with patch.object(bridge, 'loginctl', side_effect=['4', self.session()]):
            self.assertEqual(bridge.active_desktop(1000), 'GNOME')
        for overrides in ({'User':'1001'}, {'Active':'no'}, {'Remote':'yes'}, {'Class':'greeter'},
                          {'Type':'tty'}, {'Seat':''}, {'LockedHint':'yes'}, {'LockedHint':''}):
            with self.subTest(overrides=overrides), patch.object(bridge, 'loginctl', side_effect=['4', self.session(**overrides)]):
                self.assertIsNone(bridge.active_desktop(1000))

    def test_bad_session_name_is_not_passed_as_option(self):
        with patch.object(bridge, 'loginctl', return_value='--help') as command:
            self.assertIsNone(bridge.active_desktop(1000))
            self.assertEqual(command.call_count, 1)


class PublicationTests(unittest.TestCase):
    def test_atomic_bounded_history_and_logout_race(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as directory, patch.object(bridge, 'STATE', Path(directory)):
            root = Path(directory)
            for color in (b'abc', b'xyz', b'123', b'678'):
                bridge.publish((1, 1, color), lambda: True)
            self.assertEqual(len(list(root.glob('*.jpg'))), 2)
            manifest = (root / 'current.json').read_bytes()
            name = json.loads(manifest)['image']
            self.assertRegex(name, bridge.IMAGE_NAME)
            with Image.open(root / name) as image:
                self.assertEqual(image.size, (1, 1))
                self.assertFalse(image.getexif())
            with self.assertRaises(PermissionError):
                bridge.publish((1, 1, b'new'), lambda: False)
            self.assertEqual((root / 'current.json').read_bytes(), manifest)
            bridge.publish(None, lambda: True)
            self.assertEqual(json.loads((root / 'current.json').read_bytes()), {'image': ''})
            self.assertFalse(list(root.glob('*.jpg')))

    def test_atomic_replace_does_not_follow_target_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'keep'
            target.write_text('unchanged')
            link = root / 'link'
            link.symlink_to(target)
            bridge.atomic(link, b'new')
            self.assertEqual(target.read_text(), 'unchanged')
            self.assertFalse(link.is_symlink())


class SandboxTests(unittest.TestCase):
    def require_sandbox(self):
        # Hosted runners can forbid nested user/network namespaces. Probe the host
        # independently of our decoder; QEMU release checks require this to work.
        if not shutil.which('bwrap'):
            reason = 'bubblewrap is not installed'
        else:
            probe = subprocess.run(['bwrap', '--unshare-all', '--cap-drop', 'ALL',
                                    '--ro-bind', '/', '/', '/usr/bin/true'],
                                   capture_output=True, text=True, timeout=10)
            if probe.returncode == 0:
                return
            reason = probe.stderr.strip()
        if os.environ.get('VELORA_REQUIRE_SANDBOX_TESTS') == '1':
            self.fail('Required image sandbox unavailable: ' + reason)
        self.skipTest('Host cannot create the image sandbox: ' + reason)

    def test_real_decoder_unicode_spaces_alpha_gif_and_bounds(self):
        self.require_sandbox()
        from PIL import Image
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for filename, mode, size in [('тест и пробелы.png', 'RGBA', (3200, 1800)),
                                         ('animated.gif', 'RGB', (20, 10))]:
                path = root / filename
                Image.new(mode, size, 'red').save(path)
                data = bridge.decode(path)
                magic, width, height = bridge.HEADER.unpack(data[:12])
                self.assertEqual(magic, b'VRG1')
                self.assertLessEqual(width, 2560)
                self.assertLessEqual(height, 1600)
                self.assertEqual(len(data), 12 + width * height * 3)

    def test_corrupt_fifo_device_oversized_and_bomb(self):
        self.require_sandbox()
        from PIL import Image
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            broken, fifo, large, bomb = (root / name for name in ('bad.png', 'fifo', 'large', 'bomb.png'))
            broken.write_bytes(b'not a picture')
            os.mkfifo(fifo)
            with large.open('wb') as file:
                file.truncate(bridge.MAX_INPUT + 1)
            Image.new('L', (6000, 5000)).save(bomb)
            for path in (broken, fifo, large, bomb, Path('/dev/zero')):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    bridge.decode(path)

    def test_no_network_or_relative_paths(self):
        for value in ('https://example.org/image.jpg', 'file://example.org/image.jpg', 'relative.jpg',
                      'file:///tmp/picture?query=1'):
            with self.assertRaises(ValueError):
                bridge.local_path(value)
        self.assertEqual(bridge.local_path('file:///tmp/a%20b.png'), Path('/tmp/a b.png'))


if __name__ == '__main__':
    unittest.main()
