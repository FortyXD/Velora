"""Bluetooth controls open Velora settings instead of KDE's Bluetooth editor."""
from pathlib import Path
import unittest

SHELL = Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii"
LAUNCH = '["env", "QS_SETTINGS_PAGE=bluetooth", "QS_SETTINGS_SEARCH=", "qs", "-p", Quickshell.shellPath("settings.qml")]'


class BluetoothSettingsLinkTests(unittest.TestCase):
    def test_details_and_shortcuts_open_bluetooth_page(self):
        dialog = (SHELL / "modules/ii/sidebarRight/bluetoothDevices/BluetoothDialog.qml").read_text()
        classic = (SHELL / "modules/ii/sidebarRight/quickToggles/classicStyle/BluetoothToggle.qml").read_text()
        waffle = (SHELL / "modules/waffle/actionCenter/bluetooth/BluetoothControl.qml").read_text()
        settings = (SHELL / "settings.qml").read_text()
        for source in (dialog, classic, waffle):
            self.assertIn(LAUNCH, source)
            self.assertNotIn("Config.options.apps.bluetooth", source)
        self.assertIn('buttonText: Translation.tr("Details")', dialog)
        footer = dialog.split('WindowDialogButtonRow {', 1)[1]
        self.assertEqual(footer.count('DialogButton {'), 1)
        self.assertNotIn('buttonText: Translation.tr("Done")', footer)
        self.assertIn('key: "bluetooth", group: "connections"', settings)
        self.assertIn('root.openPage(startKey, Quickshell.env("QS_SETTINGS_SECTION") ?? "")', settings)

    def test_bluetooth_settings_do_not_link_back_to_kde(self):
        page = (SHELL / "modules/settings/BluetoothConfig.qml").read_text()
        self.assertNotIn("Config.options.apps.bluetooth", page)
        self.assertNotIn('Advanced Bluetooth settings', page)
        self.assertIn('Show the battery of connected devices in the bar', page)


if __name__ == "__main__":
    unittest.main()
