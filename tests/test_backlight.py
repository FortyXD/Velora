import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'dots/.config/quickshell/ii/scripts/hardware/backlight.py'
spec = importlib.util.spec_from_file_location('backlight', SCRIPT)
backlight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backlight)


class BacklightSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.backlights = self.root / 'backlight'
        self.drm = self.root / 'drm'
        self.backlights.mkdir()
        self.drm.mkdir()

    def connector(self, card, output, status):
        gpu = self.root / f'gpu{card}'
        gpu.mkdir(exist_ok=True)
        card_path = gpu / 'drm' / f'card{card}'
        card_path.mkdir(parents=True, exist_ok=True)
        if not (card_path / 'device').exists():
            (card_path / 'device').symlink_to(gpu)
        connector = card_path / f'card{card}-{output}'
        connector.mkdir()
        (connector / 'status').write_text(status)
        (self.drm / connector.name).symlink_to(connector)
        return connector, gpu

    def device(self, name, parent, owner, current=50, maximum=100, kind='raw'):
        device = parent / name
        device.mkdir()
        (device / 'device').symlink_to(owner)
        for key, value in {'brightness': current, 'max_brightness': maximum, 'type': kind}.items():
            (device / key).write_text(str(value))
        (self.backlights / name).symlink_to(device)

    def select(self, output='eDP-1'):
        return backlight.backlight_for_output(output, self.backlights, self.drm)

    def test_hybrid_uses_connected_panel_instead_of_unused_nvidia(self):
        panel, amd = self.connector(1, 'eDP-1', 'connected')
        _, nvidia = self.connector(0, 'eDP-2', 'disconnected')
        self.device('nvidia_0', nvidia, nvidia, 100)
        self.device('amdgpu_bl1', panel, panel, 200000, 400000)
        self.assertEqual(self.select(), {'device': 'amdgpu_bl1', 'current': 200000, 'max': 400000})

    def test_gpu_switch_selects_nvidia_when_it_drives_panel(self):
        panel, amd = self.connector(1, 'eDP-1', 'disconnected')
        _, nvidia = self.connector(0, 'eDP-2', 'connected')
        self.device('amdgpu_bl1', panel, panel)
        self.device('nvidia_0', nvidia, nvidia)
        self.assertEqual(self.select('eDP-2')['device'], 'nvidia_0')

    def test_platform_backlight_without_drm_parent(self):
        self.connector(0, 'eDP-1', 'connected')
        platform = self.root / 'platform'
        platform.mkdir()
        self.device('acpi_video0', platform, platform, kind='firmware')
        self.assertEqual(self.select()['device'], 'acpi_video0')

    def test_external_screen_does_not_control_internal_backlight(self):
        panel, _ = self.connector(1, 'eDP-1', 'connected')
        self.connector(1, 'DP-1', 'connected')
        self.device('amdgpu_bl1', panel, panel)
        with self.assertRaises(ValueError):
            self.select('DP-1')

    def test_missing_backlight_reports_unavailable(self):
        self.connector(0, 'eDP-1', 'connected')
        with self.assertRaises(ValueError):
            self.select()

    def test_invalid_maximum_reports_unavailable(self):
        panel, _ = self.connector(1, 'eDP-1', 'connected')
        self.device('amdgpu_bl1', panel, panel, 0, 0)
        with self.assertRaises(ValueError):
            self.select()


if __name__ == '__main__':
    unittest.main()
