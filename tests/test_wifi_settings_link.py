"""Wi-Fi controls must open Velora's Wi-Fi page, not KDE's network editor."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii"


class WifiSettingsLinkTests(unittest.TestCase):
    def test_sidebar_details_and_classic_shortcut_open_velora_wifi_page(self):
        dialog = (ROOT / "modules/ii/sidebarRight/wifiNetworks/WifiDialog.qml").read_text()
        classic = (ROOT / "modules/ii/sidebarRight/quickToggles/classicStyle/NetworkToggle.qml").read_text()
        settings = (ROOT / "settings.qml").read_text()
        launch = '["env", "QS_SETTINGS_PAGE=wifi", "QS_SETTINGS_SEARCH=", "qs", "-p", Quickshell.shellPath("settings.qml")]'
        self.assertIn('buttonText: Translation.tr("Details")', dialog)
        self.assertIn(launch, dialog)
        self.assertIn(launch, classic)
        footer = dialog.split('WindowDialogButtonRow {', 1)[1]
        self.assertEqual(footer.count('DialogButton {'), 1)
        self.assertNotIn('buttonText: Translation.tr("Disconnect Wi-Fi")', footer)
        self.assertNotIn('buttonText: Translation.tr("Done")', footer)
        self.assertIn('key: "wifi", group: "connections"', settings)
        self.assertIn('root.openPage(startKey, Quickshell.env("QS_SETTINGS_SECTION") ?? "")', settings)
        for source in (dialog, classic):
            self.assertNotIn("Config.options.apps.network", source)

    def test_wifi_settings_does_not_launch_kde_or_offer_unsupported_security(self):
        page = (ROOT / "modules/settings/WifiConfig.qml").read_text()
        service = (ROOT / "services/Network.qml").read_text()
        self.assertNotIn("Config.options.apps.network", page)
        self.assertNotIn('Advanced connection settings', page)
        self.assertNotIn('Other security…', page)
        self.assertIn('This security type isn\'t supported in Velora\'s Wi-Fi settings.', service)


if __name__ == '__main__':
    unittest.main()
