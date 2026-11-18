"""Exercise the real settings host: asynchronous warmup, navigation and suspended work."""
import json
import os
import re
import unittest

import test_connectivity_pages as pages


FIXTURE = '''import QtQuick
import qs.modules.common.widgets
ContentPage {
    property int visits: 0
    property int reveals: 0
    property bool activeAtCompletion: true
    property string sectionKey: ""
    onPageShownChanged: if (pageShown) visits++
    Component.onCompleted: activeAtCompletion = pageShown
    function navigateToSection(key) { sectionKey = key; }
    function revealItem(item, highlight = true) { reveals++; }
    Item {
        objectName: "target"
        property bool settingsSearchable: true
        property bool settingsSection: true
        property string title: "Fixture needle"
        property string searchText: title
        width: 300; height: 50
    }
    Repeater { model: 800; delegate: Item { width: 10; height: 1 } }
}
'''


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED,
                     'needs qs, cargo and dbus-daemon')
class SettingsLoadingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()
        cls.runner = pages.SettingsPagesTests()

    def run_host(self, probe, *, fixture=False):
        source = (pages.SHELL / 'settings.qml').read_text()
        source = source.replace('    id: root\n', '    id: root\n' + probe, 1)
        if fixture:
            entries = [dict(key=key, name=key, description='', icon='settings', color='#888888',
                            component='Missing.qml' if key == 'broken' else 'Fixture.qml')
                       for key in ('first', 'second', 'third', 'fourth', 'broken')]
            source = source.replace('        root.initialized = true;',
                                    '        root.pages = ' + json.dumps(entries) + ';\n'
                                    '        root.currentPage = 0;\n'
                                    '        root.history = [0];\n'
                                    '        root.historyIndex = 0;\n'
                                    '        root.initialized = true;', 1)
        return self.runner.run_driver(source, settings_page='wifi',
                                      page_sources={'Fixture.qml': FIXTURE} if fixture else None)

    def test_warmup_navigation_search_and_suspend(self):
        output = self.run_host(r'''
    property int testStage: 0
    property int testTicks: 0
    property var savedPage: null
    property int savedSettled: 0
    function check(ok, message) {
        if (!ok) { console.log("CHECK_FAIL " + message); Qt.quit(); }
        return ok;
    }
    Timer {
        interval: 16; running: true; repeat: true
        onTriggered: {
            root.testTicks++;
            let loading = 0;
            for (let i = 0; i < root.pages.length; i++) {
                const loader = pageRepeater.itemAt(i);
                if (!loader) continue;
                if (!root.check(loader.asynchronous, "a page became synchronous")) return;
                if (loader.status === Loader.Loading) loading++;
                if (loader.item && !root.check(!loader.item.activeAtCompletion, "page activated during construction")) return;
            }
            if (!root.check(loading <= 1, "more than one page incubating")) return;
            if (root.testStage === 0) {
                if (!root.currentPageItem) return;
                if (!root.check(root.currentPageItem.pageShown, "selected page is inactive")) return;
                root.openPage("third", "target");
                root.openPage("second");
                root.testStage++;
            } else if (root.testStage === 1) {
                if (!root.currentPageItem) return;
                if (!root.check(root.currentPageData.key === "second" && !revealTimer.running,
                                "stale deep link survived navigation")) return;
                root.followBreadcrumb({pageIndex: 2, sectionKey: "details"});
                root.testStage++;
            } else if (root.testStage === 2) {
                if (!root.currentPageItem || root.currentPageItem.sectionKey !== "details") return;
                if (!root.check(root.currentPageData.key === "third", "cold breadcrumb route")) return;
                root.savedPage = root.currentPageItem;
                root.testStage++;
            } else if (root.testStage === 3) {
                if (!root.backgroundPreload) return;
                root.hide();
                root.testTicks = 0;
                root.savedSettled = root.settledPages;
                root.testStage++;
            } else if (root.testStage === 4) {
                if (root.testTicks < 12) return;
                if (!root.check(!root.loadingPage && !nextPageTimer.running && !warmupDelay.running
                                && !root.savedPage.pageShown && root.settledPages === root.savedSettled,
                                "hidden work: loading=" + !!root.loadingPage + " next=" + nextPageTimer.running
                                + " delay=" + warmupDelay.running + " active=" + root.savedPage.pageShown
                                + " settled=" + root.settledPages + "/" + root.savedSettled)) return;
                root.show();
                root.testStage++;
            } else if (root.testStage === 5) {
                if (root.preloading) return;
                if (!root.check(root.currentPageItem === root.savedPage && root.savedPage.pageShown,
                                "resume discarded cached page")) return;
                if (!root.check(root.pageItemAt(3).visits === 0, "background page started active work")) return;
                if (!root.check(pageRepeater.itemAt(4).status === Loader.Error && !root.loadingPage,
                                "failed page stalled warmup")) return;
                sidebar.searchText = "Fixture needle";
                root.testStage++;
            } else if (root.testStage === 6) {
                if (searchView.results.length < 4) return;
                if (!root.check(!root.savedPage.pageShown, "search left a page active")) return;
                const result = searchView.results.find(entry => entry.pageIndex === 3);
                if (!root.check(!!result?.item, "search missed warmed page")) return;
                searchView.resultChosen(result.pageIndex, result.item);
                root.openPage("first");
                root.testTicks = 0;
                root.testStage++;
            } else if (root.testStage === 7) {
                if (root.testTicks < 45) return;
                if (!root.check(root.pageItemAt(3).reveals === 0 && !revealCheckTimer.running,
                                "old search result scrolled after navigation")) return;
                root.openPage("broken");
                root.currentPageLoader.modelData.component = "Fixture.qml";
                root.currentPageLoader.retry();
                root.testStage++;
            } else if (root.testStage === 8) {
                if (!root.currentPageItem || root.preloading) return;
                if (!root.check(root.currentPageItem.pageShown, "retry did not recover")) return;
                root.testTicks = 0;
                root.testStage++;
            } else if (root.testStage === 9 && root.testTicks > 20) {
                if (!root.check(!nextPageTimer.running && !warmupDelay.running && !root.loadingPage,
                                "completed warmup kept scheduling work")) return;
                console.log("DRIVER_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 20000; running: true; onTriggered: {
        console.log("CHECK_FAIL timeout at stage " + root.testStage); Qt.quit();
    } }
''', fixture=True)
        self.assertIn('DRIVER_PASS', output, output[-7000:])
        self.assertNotIn('CHECK_FAIL', output, output[-7000:])
        self.assertNotRegex(output, r'TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')

    def test_real_pages_navigation_and_event_loop(self):
        output = self.run_host(r'''
    property double lastTick: Date.now()
    property double maximumGap: 0
    property int navigationStep: 0
    property var navigationKeys: ["appearance", "wallpaper", "widgets", "desktop", "bar", "sidebars",
        "keyboard", "shortcuts", "search", "ai", "wifi", "appearance", "wallpaper", "widgets"]
    Timer {
        interval: 16; running: true; repeat: true
        onTriggered: {
            const now = Date.now();
            root.maximumGap = Math.max(root.maximumGap, now - root.lastTick);
            root.lastTick = now;
            for (let i = 0; i < root.pages.length; i++) {
                const loader = pageRepeater.itemAt(i);
                if (loader && !loader.asynchronous) { console.log("CHECK_FAIL synchronous loader"); Qt.quit(); }
            }
        }
    }
    Timer {
        interval: 220; running: Config.ready; repeat: true
        onTriggered: {
            if (root.navigationStep < root.navigationKeys.length) {
                root.openPage(root.navigationKeys[root.navigationStep++]);
                return;
            }
            if (root.preloading) return;
            if (!root.currentPageItem || root.currentPageData.key !== "widgets") {
                console.log("CHECK_FAIL navigation changed during warmup"); Qt.quit(); return;
            }
            console.log("PERF_MAX_GAP " + root.maximumGap);
            console.log("DRIVER_PASS"); Qt.quit();
        }
    }
    Timer { interval: 30000; running: true; onTriggered: { console.log("CHECK_FAIL warmup timeout"); Qt.quit(); } }
''')
        self.assertIn('DRIVER_PASS', output, output[-7000:])
        self.assertNotIn('CHECK_FAIL', output, output[-7000:])
        self.assertNotRegex(output, r'TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')
        gap = int(re.search(r'PERF_MAX_GAP (\d+)', output)[1])
        print(f'\nSettings maximum event-loop gap (cold start + navigation + warmup): {gap} ms')
        # Explicit opt-in for a controlled performance run; overloaded CI is not a benchmark.
        if os.environ.get('VELORA_SETTINGS_PERF') == '1':
            self.assertLessEqual(gap, 150, output[-7000:])

    def test_shortcut_rows_are_incremental_searchable_and_pause_when_hidden(self):
        output = self.runner.run_driver(r'''
import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.settings
ApplicationWindow {
    id: root
    visible: true; width: 1000; height: 760
    property bool windowUsable: true
    property int stage: 0
    property int ticks: 0
    property int pausedBudget: 0
    property var firstRow: null
    function check(ok, message) { if (!ok) { console.log("CHECK_FAIL " + message); Qt.quit(); } return ok; }
    function findRow(node, title) {
        if (node.settingsSearchable && node.title === title) return node;
        for (const child of node.children ?? []) { const found = findRow(child, title); if (found) return found; }
        return null;
    }
    Loader { id: page; anchors.fill: parent; asynchronous: true; source: "modules/settings/ShortcutsConfig.qml" }
    SettingsSearch {
        id: search; visible: false
        pages: [{name: "Shortcuts", description: "", icon: "keyboard"}]
        pageItemAt: index => page.item
        query: "Perf shortcut 159"
    }
    Connections { target: page.item; function onSearchContentChanged() { search.scheduleRefresh(); } }
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (page.status !== Loader.Ready) return;
            if (root.stage === 0) {
                HyprlandKeybinds.groups = [{id:"one",name:"One",icon:"keyboard"}, {id:"two",name:"Two",icon:"keyboard"}];
                let binds = [], map = {};
                for (let i = 0; i < 160; i++) {
                    const bind = {id:"perf"+i, group:i<80?"one":"two", description:"Perf shortcut "+i,
                                  mods:["Super"], key:"F"+(i+1), default_mods:["Super"], default_key:"F"+(i+1), remappable:true};
                    binds.push(bind); map[bind.id] = bind;
                }
                HyprlandKeybinds.bindMap = map;
                HyprlandKeybinds.binds = binds;
                root.stage++;
            } else if (root.stage === 1) {
                if (page.item.rowBudget < 8) return;
                if (!root.check(page.item.rowBudget < 160, "all shortcut rows built at once")) return;
                root.firstRow = root.findRow(page.item, "Perf shortcut 0");
                root.pausedBudget = page.item.rowBudget;
                root.windowUsable = false;
                root.ticks = 0;
                root.stage++;
            } else if (root.stage === 2) {
                if (++root.ticks < 12) return;
                if (!root.check(page.item.rowBudget === root.pausedBudget, "hidden shortcuts kept building")) return;
                root.windowUsable = true;
                root.stage++;
            } else if (root.stage === 3) {
                if (page.item.rowBudget < 160 || !search.results.length) return;
                if (!root.check(root.firstRow === root.findRow(page.item, "Perf shortcut 0"), "batch replaced existing rows")) return;
                if (!root.check(search.results.some(result => result.title === "Perf shortcut 159"), "late shortcut missing from search")) return;
                console.log("DRIVER_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: { console.log("CHECK_FAIL shortcuts timeout " + root.stage); Qt.quit(); } }
}
''')
        self.assertIn('DRIVER_PASS', output, output[-7000:])
        self.assertNotIn('CHECK_FAIL', output, output[-7000:])
        self.runner.assert_clean(output)

    def test_wallpaper_preview_only_ticks_on_its_visible_page(self):
        output = self.run_host(r'''
    property int energyStage: 0
    property int energyTicks: 0
    property var shaderPreview: null
    property real savedShaderTime: 0
    function findShader(node) {
        if (node.name === "aurora" && node.time !== undefined && node.fps === 24) return node;
        for (const child of node.children ?? []) { const found = findShader(child); if (found) return found; }
        return null;
    }
    function energyCheck(ok, message) { if (!ok) { console.log("CHECK_FAIL " + message); Qt.quit(); } return ok; }
    Timer {
        interval: 50; running: Config.ready; repeat: true
        onTriggered: {
            if (root.energyStage === 0) {
                Config.options.background.shaderWallpaper.name = "aurora";
                const wallpaper = root.pageItemAt(root.pageIndex("wallpaper"));
                if (!wallpaper) return;
                root.shaderPreview = root.findShader(wallpaper);
                if (!root.energyCheck(!!root.shaderPreview, "shader preview missing")) return;
                root.savedShaderTime = root.shaderPreview.time;
                root.energyStage++;
            } else if (++root.energyTicks >= 6) {
                root.energyTicks = 0;
                if (root.energyStage === 1) {
                    if (!root.energyCheck(root.shaderPreview.time === root.savedShaderTime, "background preview ticks")) return;
                    root.openPage("wallpaper");
                } else if (root.energyStage === 2) {
                    if (!root.energyCheck(root.shaderPreview.time > root.savedShaderTime, "shown preview is frozen")) return;
                    root.hide();
                    root.savedShaderTime = root.shaderPreview.time;
                } else if (root.energyStage === 3) {
                    if (!root.energyCheck(root.shaderPreview.time === root.savedShaderTime, "hidden window preview ticks")) return;
                    root.openPage("wifi");
                    root.show();
                } else {
                    if (!root.energyCheck(root.shaderPreview.time === root.savedShaderTime, "leaving page restarted preview")) return;
                    console.log("DRIVER_PASS"); Qt.quit();
                }
                root.energyStage++;
            }
        }
    }
    Timer { interval: 18000; running: true; onTriggered: { console.log("CHECK_FAIL preview timeout"); Qt.quit(); } }
''')
        self.assertIn('DRIVER_PASS', output, output[-7000:])
        self.assertNotIn('CHECK_FAIL', output, output[-7000:])
        self.assertNotRegex(output, r'TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')


if __name__ == '__main__':
    unittest.main()
