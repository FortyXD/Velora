"""Open the real settings trees with the isolated Quickshell settings host."""
import shutil
import unittest

import test_connectivity_pages as pages


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED, 'needs the settings test runtime')
class SettingsTreeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()

    def test_navigation_search_and_focus_in_both_languages(self):
        probe = r'''
    property int stage: 0
    property int languageIndex: 0
    property var dockLink
    property var dockSize
    property var appsLink
    property var testPage: currentPageItem
    property int expectedDockSize: 0
    property int expectedWarning: 0
    property string observed: ""
    property int layoutTicks: 0
    FileView { id: savedConfig; path: Config.filePath; watchChanges: true; onFileChanged: reload() }
    function findControl(node, predicate) {
        if (!node) return null;
        if (predicate(node)) return node;
        for (const child of node.children ?? []) {
            const item = findControl(child, predicate);
            if (item) return item;
        }
        return null;
    }
    function check(ok, message) {
        if (!ok) { console.log("CHECK_FAIL", stage, message); Qt.quit(); }
        return ok;
    }
    function row(key) { return findSection(testPage, key); }
    Timer {
        interval: 180; running: true; repeat: true
        onTriggered: {
            if (!Config.ready || !root.testPage) return;
            const page = root.testPage;
            switch (root.stage) {
            case 0:
                Config.options.language.ui = root.languageIndex ? "ru_RU" : "en_US";
                root.width = root.languageIndex ? 760 : 1150;
                root.openPage("desktop");
                break;
            case 1:
                if (root.currentPageData.key !== "desktop" || !page.pageShown) return;
                page.navigateToSection("");
                root.dockLink = root.row("dock");
                if (!root.check(root.dockLink && root.dockLink.width > 0 && root.dockLink.summary.length, "dock row")) return;
                {
                    page.setDockMode("hover");
                    const size = root.findControl(page, n => n.defaultValueText === "60 px" && n.settingsSearchable);
                    const mark = root.findControl(size, n => n.objectName === "sliderDefaultMark");
                    if (!root.check(size && mark, "dock size and default marker")) return;
                    root.expectedDockSize = root.languageIndex ? 65 : 70;
                    root.dockSize = size;
                    size.value = root.expectedDockSize;
                    if (!root.check(mark.visible && Math.abs(mark.position - (60 - 40) / 56) < 0.001, "fixed dock reference")) return;
                }
                root.dockLink.clicked();
                break;
            case 2:
                if (!root.check(page.tab === "dock", "open dock")) return;
                root.dockSize.moved();
                root.appsLink = root.row("dockApps");
                root.appsLink.clicked();
                break;
            case 3:
                if (!root.check(page.navigationTrail.map(e => e.key).join("/") === "dock/dockApps", "nested trail")) return;
                root.goBack();
                break;
            case 4:
                if (!root.check(page.tab === "dock" && root.appsLink.activeFocus, "back restores launching row")) return;
                root.followBreadcrumb({pageIndex:root.currentPage});
                root.openPage("desktop", Translation.tr("Hot corners"));
                break;
            case 5:
                if (page.tab !== "corners") return;
                root.layoutTicks = 0;
                root.openPage("sound");
                break;
            case 6:
                if (root.currentPageData.key !== "sound" || !page.pageShown) return;
                if (++root.layoutTicks < 4) return;
                page.navigateToSection("");
                if (!root.check(root.row("microphone").title.length > 0, "microphone status")) return;
                {
                    const left = root.row("output"), right = root.row("microphone");
                    const a = left.mapToItem(page, 0, left.height), b = right.mapToItem(page, 0, right.height);
                    const aligned = Math.abs(a.x - b.x) < 2 ? b.y > a.y : Math.abs(a.y - b.y) <= 1;
                    if (!root.check(Math.abs(left.width - right.width) <= 1 && aligned,
                        "device card alignment " + JSON.stringify([left.width, right.width, a.x, a.y, b.x, b.y]))) return;
                }
                sidebar.searchText = Translation.tr("Test the microphone");
                break;
            case 7: {
                const match = searchView.results.find(r => r.title === Translation.tr("Test the microphone"));
                if (!match) return;
                searchView.resultChosen(match.pageIndex, match.item);
                break;
            }
            case 8:
                if (page.tab !== "microphone") return;
                root.openPage("battery", "analytics");
                break;
            case 9:
                if (root.currentPageData.key !== "battery" || page.tab !== "analytics") return;
                page.navigateToSection("");
                {
                    const low = root.findControl(page, n => n.enabled && n.text === Translation.tr("Low warning (%)") && n.stepSize !== undefined);
                    root.expectedWarning = root.languageIndex ? 25 : 30;
                    low.value = root.expectedWarning;
                }
                root.row("warnings").clicked();
                break;
            case 10:
                if (!root.check(page.tab === "warnings", "full charge and suspend destination")) return;
                if (!root.check(!root.findControl(page, n => n.enabled && n.text === Translation.tr("Low warning (%)") && n.stepSize !== undefined), "low warning must only appear on the overview")) return;
                break;
            case 11: {
                const disk = JSON.parse(savedConfig.text() || "{}");
                root.observed = JSON.stringify([disk.battery?.low, disk.dock?.height, Config.options.battery.low, Config.options.dock.height, root.expectedWarning, root.expectedDockSize]);
                if (disk.battery?.low !== root.expectedWarning || disk.dock?.height !== root.expectedDockSize) return;
                if (!root.check(root.title === (root.languageIndex ? "Настройки Velora" : "Velora Settings"), root.title)) return;
                if (!root.check(Config.filePath.endsWith("/velora/config.json"), Config.filePath)) return;
                if (!root.languageIndex) { root.languageIndex++; root.stage = 0; return; }
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            }
            root.stage++;
        }
    }
    Timer { interval: 25000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", root.stage, root.observed); Qt.quit(); } }
'''
        driver = (pages.SHELL / 'settings.qml').read_text().replace('    id: root\n', '    id: root\n' + probe, 1)
        output = pages.SettingsPagesTests().run_driver(driver, settings_page='desktop')
        self.assertIn('DRIVER_PASS', output, output[-6000:])
        self.assertNotRegex(output, r'CHECK_FAIL|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')

    def test_appearance_layout_links_and_live_settings(self):
        probe = r'''
    property int step: 0
    property int layoutTicks: 0
    property var contrast
    property var speed
    FileView { id: calls; path: Quickshell.shellPath("theme-calls"); watchChanges: true; onFileChanged: reload() }
    function findControl(node, predicate) {
        if (predicate(node)) return node;
        for (const child of node.children ?? []) {
            const match = findControl(child, predicate);
            if (match) return match;
        }
        return null;
    }
    function expect(ok, label) {
        if (!ok) { console.log("CHECK_FAIL", step, label); Qt.quit(); }
        return ok;
    }
    Timer {
        interval: 160; running: true; repeat: true
        onTriggered: {
            const page = root.currentPageItem;
            if (!Config.ready || !page) return;
            const preview = root.findControl(page, n => n.objectName === "appearanceDesktopPreview");
            const colors = root.findSection(page, Translation.tr("Colors"));
            const fonts = root.findSection(page, "fonts");
            switch (root.step) {
            case 0:
                if (!page.pageShown) return;
                Directories.wallpaperSwitchScriptPath = Quickshell.shellPath("theme command.sh");
                Config.options.language.ui = "ru_RU";
                root.width = 1100;
                break;
            case 1: {
                if (!preview?.item || !colors || ++root.layoutTicks < 4) return;
                const left = preview.mapToItem(page, 0, preview.height), right = colors.mapToItem(page, 0, colors.height);
                if (!root.expect(left.x < right.x && Math.abs(left.y - right.y) <= 1 && Math.abs(preview.width - colors.width) <= 1, "paired cards")) return;
                const windows = root.findSection(page, "windows"), glass = root.findSection(page, "transparency");
                if (!root.expect(windows.height === glass.height && Math.abs(windows.width - glass.width) <= 1, "equal detail tiles")) return;
                const palette = root.findControl(page, n => n.text === Translation.tr("Palette") && n.dropdown);
                const light = root.findControl(page, n => n.dark === false && n.label === Translation.tr("Light"));
                if (!root.expect(palette.options.length === 9 && light.selected === !Appearance.m3colors.darkmode, "mode and palette")) return;
                palette.selected("scheme-rainbow");
                light.clicked();
                fonts.clicked();
                break;
            }
            case 2: {
                if (!root.expect(page.tab === "fonts" && !preview.item, "preview suspended on detail")) return;
                const main = root.findControl(page, n => n.fontKey === "main");
                main.picked("Noto Sans");
                root.goBack();
                break;
            }
            case 3:
                if (!root.expect(fonts.activeFocus && fonts.summary === "Noto Sans", "back restores focus and current font")) return;
                root.openPage("appearance", Translation.tr("Screen corners"));
                break;
            case 4:
                if (page.tab !== "windows") return;
                {
                    const square = root.findControl(page, n => n.mode === 0 && n.label === Translation.tr("Square"));
                    square.clicked();
                    if (!root.expect(Config.options.appearance.fakeScreenRounding === 0, "corner mode")) return;
                }
                sidebar.searchText = Translation.tr("Terminal text contrast");
                break;
            case 5: {
                const match = searchView.results.find(r => r.pageIndex === root.pageIndex("appearance") && r.title === Translation.tr("Terminal text contrast"));
                if (!match) return;
                searchView.resultChosen(match.pageIndex, match.item);
                break;
            }
            case 6: {
                if (page.tab !== "colors") return;
                root.contrast = root.findControl(page, n => n.text === Translation.tr("Terminal text contrast") && n.defaultValue !== undefined);
                contrast.value = 0.7;
                break;
            }
            case 7: {
                if (Math.abs(contrast.value - 0.7) > 0.001) return;
                contrast.moved();
                const mark = root.findControl(contrast, n => n.objectName === "sliderDefaultMark");
                if (!root.expect(mark.visible && Math.abs(mark.position - 0.35) < 0.001 && Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost === 0.7, "terminal value and default mark")) return;
                root.openPage("appearance", "motion");
                break;
            }
            case 8: {
                if (page.tab !== "motion") return;
                root.speed = root.findControl(page, n => n.defaultValueText === "1×");
                speed.value = 0;
                break;
            }
            case 9: {
                if (speed.value !== 0) return;
                speed.moved();
                const sample = root.findControl(page, n => typeof n.replay === "function" && n.enterDuration !== undefined);
                sample.replay();
                if (!root.expect(sample.enterDuration === 0 && sample.progress === 1, "motion preview respects disabled animations")) return;
                speed.value = 0.6;
                break;
            }
            case 10: {
                if (Math.abs(speed.value - 0.6) > 0.001) return;
                speed.moved();
                page.navigateToSection("");
                root.width = 760;
                root.layoutTicks = 0;
                break;
            }
            case 11: {
                if (!sidebar.expanded) { sidebar.expandOverride = true; root.layoutTicks = 0; return; }
                if (!preview?.item || ++root.layoutTicks < 5) return;
                const top = preview.mapToItem(page, 0, preview.height), below = colors.mapToItem(page, 0, 0);
                if (!root.expect(Math.abs(top.x - below.x) <= 1 && below.y > top.y, "single column " + [root.width, sidebar.width, top, below])) return;
                if (!root.expect(root.findSection(page, "motion").summary.includes("0,6×"), "localized live speed")) return;
                const commands = calls.text().trim().split("\n");
                if (commands.length < 3) return;
                if (!root.expect(commands.filter(c => c === "--noswitch --type scheme-rainbow --mode dark").length === 2 &&
                    commands.includes("--noswitch --type scheme-rainbow --mode light"), "theme commands and terminal debounce")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            }
            root.step++;
        }
    }
    Timer { interval: 22000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", root.step); Qt.quit(); } }
'''
        driver = (pages.SHELL / 'settings.qml').read_text().replace('    id: root\n', '    id: root\n' + probe, 1)
        stub = 'printf "%s\\n" "$*" >> "$(dirname "$0")/theme-calls"\n'
        output = pages.SettingsPagesTests().run_driver(driver, settings_page='appearance',
                                                       page_sources={'theme command.sh': stub, 'theme-calls': ''})
        self.assertIn('DRIVER_PASS', output, output[-6000:])
        self.assertNotRegex(output, r'CHECK_FAIL|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')

    @unittest.skipUnless(shutil.which('matugen'), 'needs matugen to generate the selected schemes')
    def test_scheme_selection_reaches_the_running_clock(self):
        src = (pages.SHELL / 'settings.qml').read_text().replace('import QtQuick.Controls',
            'import QtTest\nimport qs.modules.ii.background.widgets.clock\nimport QtQuick.Controls', 1)
        probe = r'''
    TestCase { id: input; when: false }
    CookieClock { id: clock; x: -500; preview: true }
    Process {
        id: prepare
        command: ["prepare-palette-fixture"]
        running: true
        property bool done: false
        onExited: code => done = code === 0
    }
    property int stage: 0
    property string monochromeClock: ""
    Timer {
        interval: 120; repeat: true; running: Config.ready && prepare.done
        onTriggered: {
            const selector = root.currentPageItem && input.findChild(root.currentPageItem, "appearanceScheme");
            if (!selector) return;
            if (root.stage === 0) {
                selector.selected("scheme-monochrome");
                root.stage++;
            } else if (root.stage === 1) {
                if (!Qt.colorEqual(Appearance.colors.colPrimary, "#ffffff") || clock.colBackground.r !== clock.colBackground.g) return;
                root.monochromeClock = clock.colBackground.toString();
                selector.selected("scheme-expressive");
                root.stage++;
            } else if (root.stage === 2) {
                if (clock.colBackground.toString() === root.monochromeClock || clock.colBackground.r === clock.colBackground.g) return;
                if (Config.options.appearance.palette.type === "scheme-expressive" &&
                    Qt.colorEqual(clock.colBackground, Appearance.m3colors.m3primaryContainer) &&
                    Qt.colorEqual(Appearance.m3colors.m3surfaceContainer, "#291d17") && Appearance.m3colors.darkmode) {
                    console.log("DRIVER_PASS"); Qt.quit();
                }
            }
        }
    }
    Timer { interval: 18000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", root.stage, clock.colBackground, Appearance.colors.colPrimary); Qt.quit(); } }
'''
        template = pages.PROJECT / 'dots/.config/matugen/templates/colors.json'
        prepare = ('mkdir -p "$XDG_CONFIG_HOME/matugen"\n'
                   'cat > "$XDG_CONFIG_HOME/matugen/config.toml" <<EOF\n'
                   f'[config]\n[templates.shell]\ninput_path = "{template}"\n'
                   'output_path = "$XDG_STATE_HOME/quickshell/user/generated/colors.json"\nEOF')
        log = pages.SettingsPagesTests().run_driver(src.replace('    id: root\n', '    id: root\n' + probe, 1),
            settings_page='appearance', tool_stubs={'prepare-palette-fixture': prepare, 'gsettings': 'exit 0'},
            initial_config={'appearance': {'animationSpeed': 0, 'palette': {'roleOverrides': {'surface_container': '#291D17'}},
                                          'wallpaperTheming': {'enableAppsAndShell': False, 'enableQtApps': False}},
                            'background': {'wallpaperPath': str(pages.SHELL / 'assets/images/autumn.jpg')}})
        self.assertIn('DRIVER_PASS', log, log[-3500:])

    def test_interactive_theme_palette(self):
        fixture = (pages.PROJECT / 'tests/qml/ThemePaletteFixture.qml').read_text()
        output = pages.SettingsPagesTests().run_driver(fixture)
        self.assertIn('DRIVER_PASS', output, output[-5500:])
        self.assertNotRegex(output, r'CHECK_FAIL|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')

    def test_capture_tools_previews_and_search(self):
        probe = r'''
    property int stage: 0
    property var shotCard
    function findTool(item, predicate) {
        if (predicate(item)) return item;
        for (const child of item.children ?? []) {
            const result = findTool(child, predicate);
            if (result) return result;
        }
        return null;
    }
    function check(ok, label) {
        if (!ok) { console.log("CHECK_FAIL", stage, label); Qt.quit(); }
        return ok;
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            const page = root.currentPageItem;
            if (!page || !Config.ready) return;
            const control = label => root.findTool(page, n => n.settingsSearchable && n.text === Translation.tr(label));
            const preview = scene => root.findTool(page, n => n.scene === scene && typeof n.replay === "function" && n.shown);
            switch (root.stage) {
            case 0:
                if (root.currentPageData.key !== "tools" || !page.pageShown) return;
                Config.options.language.ui = "ru_RU";
                Config.options.appearance.animationSpeed = 1;
                break;
            case 1: {
                const record = root.findSection(page, "screen-recording");
                root.shotCard = root.findSection(page, "screenshots");
                if (!root.shotCard || !record || !preview("screenshot") || root.shotCard.width <= 0) return;
                if (!root.check(root.shotCard.height === record.height && Math.abs(root.shotCard.width - record.width) <= 1, "same-sized capture cards")) return;
                preview("screenshot").replay();
                break;
            }
            case 2: {
                const motion = preview("screenshot");
                if (!root.check(motion.playing && motion.progress > 0 && motion.progress < 1, "selection grows during replay")) return;
                Config.options.appearance.animationSpeed = 0;
                if (!root.check(!motion.playing && motion.progress === 1, "reduced motion settles immediately")) return;
                root.shotCard.clicked();
                break;
            }
            case 3: {
                if (!root.check(page.tab === "screenshots" && !preview("recording"), "only the screenshot detail is active")) return;
                const cursor = control("Show cursor in screenshots");
                cursor.clicked();
                if (!root.check(Config.options.screenSnip.showCursor && preview("screenshot").progress === 1, "screenshot cursor")) return;
                root.goBack();
                break;
            }
            case 4:
                if (!root.check(root.shotCard.activeFocus, "back restores the screenshot card")) return;
                root.openPage("tools", "screen-recording");
                break;
            case 5: {
                if (page.tab !== "screen-recording") return;
                const audio = control("Audio source"), system = control("System audio device"), mic = control("Microphone device");
                audio.selected("both");
                if (!root.check(system.visible && mic.visible && page.needsSources, "two recording inputs")) return;
                mic.selected("missing-device");
                if (!root.check(mic.options.some(s => s.value === "missing-device" && s.icon === "warning"), "stored disconnected input")) return;
                audio.selected("none");
                if (!root.check(!system.visible && !mic.visible && !page.needsSources, "silent capture")) return;
                control("Capture area").selected("screen");
                control("Frame rate").selected(60);
                sidebar.searchText = Translation.tr("Stroke width");
                break;
            }
            case 6: {
                const match = searchView.results.find(r => r.pageIndex === root.pageIndex("tools") && r.title === Translation.tr("Stroke width"));
                if (!match) return;
                searchView.resultChosen(match.pageIndex, match.item);
                break;
            }
            case 7: {
                if (page.tab !== "selection") return;
                control("Google Lens").selected("circle");
                control("Stroke width").value = 12;
                if (!root.check(Config.options.regionSelector.circle.strokeWidth === 12 &&
                    root.findTool(preview("selection"), n => n.circle === true), "circle selection responds to options")) return;
                root.openPage("tools", "overlay");
                break;
            }
            case 8: {
                if (page.tab !== "overlay") return;
                Config.options.appearance.animationSpeed = 1;
                Config.options.overlay.openingZoomAnimation = false;
                const overlay = preview("overlay");
                overlay.replay();
                if (!root.check(!overlay.canAnimate && !overlay.playing && overlay.progress === 1, "overlay without zoom")) return;
                const crosshair = root.findTool(overlay, n => typeof n.loadFromCode === "function");
                Config.options.crosshair.code = "0;P;c;8;u;4488ccff";
                if (!root.check(crosshair.colorCode === "#4488cc", "live crosshair color")) return;
                Config.options.crosshair.code = "0;P;c;8;u;F";
                if (!root.check(crosshair.colorCode === "#FFFFFF", "partially entered color")) return;
                if (!root.check(page.recording.mode === "screen" && page.recording.fps === 60 && page.recording.audio === "none", "recording choices preserved")) return;
                break;
            }
            case 9:
                if (root.preloading) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            root.stage++;
        }
    }
    Timer { interval: 20000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", root.stage); Qt.quit(); } }
'''
        driver = (pages.SHELL / 'settings.qml').read_text().replace('    id: root\n', '    id: root\n' + probe, 1)
        output = pages.SettingsPagesTests().run_driver(driver, settings_page='tools')
        self.assertIn('DRIVER_PASS', output, output[-4000:])
        self.assertNotRegex(output, r'CHECK_FAIL|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign')
