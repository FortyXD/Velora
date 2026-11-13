"""Search opt-ins in the actual settings and launcher, with no model execution."""
import unittest
import test_connectivity_pages as pages


class SearchOptInTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()

    def test_defaults_switches_and_stale_ai_results(self):
        source = (pages.SHELL / 'services/Assistant.qml').read_text()
        source = source.replace('function submit(', 'function originalSubmit(', 1)
        source = source.replace('    id: root\n', '''    id: root
    property int testSubmissions: 0
    function submit(text, display, surface, intent) { testSubmissions++; return true; }
''', 1)
        driver = r'''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
    id: root
    property int step: 0
    property bool failed: false
    property var oldAction: null
    function check(ok, message) { if (!ok) { failed = true; console.log("CHECK_FAIL " + message); } }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function choices() { return LauncherSearch.results.filter(item => item.id.startsWith("assistant:")); }
    FloatingWindow {
        visible: true; implicitWidth: 960; implicitHeight: 850
        SearchConfig { id: search; anchors.fill: parent; pageShown: true }
    }
    Timer {
        interval: 200; running: Config.ready; repeat: true
        onTriggered: {
            if (root.step === 0) {
                root.check(!Config.options.search.ai.enabled && !Lens.enabled, "both search features default off");
                root.check(!root.find(search,"searchAiEnable").checked, "AI switch is unchecked");
                root.check(!root.find(search,"searchLensEnable").checked, "index switch is unchecked");
                root.check(!root.find(search,"lensSemanticEnable").checked, "meaning search starts unchecked");
                root.check(!root.find(search,"lensMediaEnable").checked, "media starts unchecked");
                Config.options.assistant.enabled = true;
                LauncherSearch.query = "explain how computers work";
            } else if (root.step === 1) {
                root.check(root.choices().length === 0, "sidebar assistant does not enable launcher AI");
                root.find(search,"searchAiEnable").clicked();
            } else if (root.step === 2) {
                root.check(LauncherSearch.aiEnabled && root.choices().length === 2, "opt-in exposes AI choices");
                root.oldAction = root.choices()[0];
                root.oldAction.execute();
                root.check(Assistant.testSubmissions === 1, "explicit enabled choice works");
                Assistant.panelOpen = true;
                root.find(search,"searchAiEnable").clicked();
            } else if (root.step === 3) {
                root.check(!LauncherSearch.aiEnabled && root.choices().length === 0, "turning off hides AI choices");
                root.check(!Assistant.panelOpen && Assistant.enabled, "launcher closes and sidebar stays enabled");
                root.oldAction.execute();
                root.check(Assistant.testSubmissions === 1, "stale AI choice cannot submit while disabled");
                LauncherSearch.query = Config.options.search.prefix.math + "24*7";
            } else if (root.step === 4) {
                root.check(LauncherSearch.mathQuery, "ordinary calculator is still available");
                root.check(!Lens.ready && !Lens.thinking, "disabled file search remains disconnected");
                console.log(root.failed ? "DRIVER_FAIL" : "DRIVER_PASS");
                Qt.quit();
            }
            root.step++;
        }
    }
}
'''
        case = pages.SettingsPagesTests()
        output = case.run_driver(driver, service_overrides={'Assistant.qml': source})
        self.assertIn('DRIVER_PASS', output, output[-7000:])
        case.assert_clean(output)
