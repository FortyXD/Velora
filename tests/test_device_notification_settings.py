"""Exercise the three settings trees and notification delivery inside the private shell runtime."""
from pathlib import Path
import shutil
import unittest

import test_connectivity_pages as pages

FIXTURES = Path(__file__).parent / 'qml'


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED, 'needs the isolated settings runtime')
class DeviceNotificationSettingsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()

    def check_output(self, output):
        self.assertIn('DRIVER_PASS', output, output[-5500:])
        runtime = output.split('DRIVER_PASS', 1)[0]
        problems = [line for line in runtime.splitlines() if any(issue in line for issue in
                    ('CHECK_FAIL', 'TypeError', 'ReferenceError', 'Binding loop', 'Cannot assign', 'Unable to assign', 'recursive rearrange'))]
        self.assertEqual(problems, [])

    def test_settings_navigation_and_controls(self):
        host = (pages.SHELL / 'settings.qml').read_text().replace('    id: root\n', '''    id: root
    DeviceSettingsFixture { host: root; search: searchView; navigation: sidebar }
''', 1)
        fixture = (FIXTURES / 'DeviceSettingsFixture.qml').read_text()
        output = pages.SettingsPagesTests().run_driver(host, settings_page='mouse', page_sources={'DeviceSettingsFixture.qml': fixture})
        self.check_output(output)

    @unittest.skipUnless(shutil.which('gdbus'), 'needs a client for the private notification bus')
    def test_quiet_hours_exceptions_and_ephemeral_preview(self):
        driver = (FIXTURES / 'NotificationPolicyFixture.qml').read_text()
        self.check_output(pages.SettingsPagesTests().run_driver(driver))
