"""Pointer-driven coverage of the settings and live bar editors in both orientations."""
from pathlib import Path
import unittest

import test_connectivity_pages as pages


@unittest.skipUnless(pages.QS and pages.CARGO and pages.DBUS, 'needs the isolated shell runtime')
class BarEditMotionTests(unittest.TestCase):
    def test_insertion_and_reordering(self):
        pages.SettingsPagesTests.setUpClass()
        driver = (Path(__file__).parent / 'qml/BarEditMotionFixture.qml').read_text()
        # The offscreen platform cannot construct the popups in the production widget factory.
        layout = (pages.SHELL / 'modules/ii/bar/layout/BarLayoutView.qml').read_text()
        zone = (pages.SHELL / 'modules/ii/bar/layout/BarZone.qml').read_text()
        sources = {
            'TestZone.qml': 'import qs.modules.ii.bar.layout\n' + zone.replace('ScrollHint {', 'TestHint {'),
            'TestHint.qml': 'import QtQuick\nItem { property bool reveal; property string side; property string icon; property string tooltipText }',
            'TestBarLayout.qml': 'import qs.modules.ii.bar.layout\n' + layout.replace('BarWidgetFactory {', 'TestWidgets {').replace('BarZone {', 'TestZone {'),
            'TestWidgets.qml': '''import QtQuick
QtObject {
    function gate(type) { return true; }
    function component(type, vertical) { return widget; }
    property Component widget: Component { Item { property var host; implicitWidth: 54; implicitHeight: 30 } }
}''',
        }
        output = pages.SettingsPagesTests().run_driver(driver.replace('BarLayoutView {', 'TestBarLayout {'), page_sources=sources)
        self.assertIn('DRIVER_PASS', output, output[-4500:])
        self.assertNotRegex(output, r'CHECK_FAIL|Binding loop|ReferenceError|TypeError|Cannot assign|Unable to assign')
