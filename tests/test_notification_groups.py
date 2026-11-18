"""Render the real notification group and exercise actions through its delegates."""
from pathlib import Path
import shutil
import unittest

import test_connectivity_pages as pages


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED, 'needs the isolated Quickshell runtime')
class NotificationGroupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()

    def test_grouped_messages_and_actions(self):
        driver = (Path(__file__).parent / 'qml/NotificationGroupFixture.qml').read_text()
        fake = '''pragma Singleton
import Quickshell
Singleton {
    property string invoked: ""
    property int dismissed: -1
    signal discard(int id)
    function attemptInvokeAction(id, action) { invoked = id + "/" + action; }
    function discardNotification(id) { dismissed = id; discard(id); }
}
'''
        output = pages.SettingsPagesTests().run_driver(driver, service_overrides={'Notifications.qml': fake})
        self.assertIn('DRIVER_PASS', output, output[-3500:])
        self.assertNotRegex(output, r'CHECK_FAIL|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')

    def test_large_stack_reveals_without_moving_the_front(self):
        driver = (Path(__file__).parent / 'qml/NotificationStackMotionFixture.qml').read_text()
        output = pages.SettingsPagesTests().run_driver(driver)
        self.assertIn('DRIVER_PASS', output, output[-3500:])
        self.assertNotRegex(output, r'CHECK_FAIL|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')

    @unittest.skipUnless(shutil.which('gdbus'), 'needs a notification client on the private bus')
    def test_live_notifications_dismiss_once_and_cancel_pending_timeouts(self):
        driver = (Path(__file__).parent / 'qml/NotificationDismissalFixture.qml').read_text()
        output = pages.SettingsPagesTests().run_driver(driver)
        self.assertIn('DRIVER_PASS', output, output[-3500:])
        self.assertNotRegex(output, r'CHECK_FAIL|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')
