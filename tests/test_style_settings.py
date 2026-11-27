"""Exercise the settings previews in a private shell, including the actual input and apply paths."""
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

import test_connectivity_pages as pages


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED, 'needs the isolated settings runtime')
class StyleSettingsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()
        cls.runner = pages.SettingsPagesTests()

    def run_page(self, key, probe, screen_size=(1920, 1200), initial_config=None, tool_stubs=None):
        source = (pages.SHELL / 'settings.qml').read_text().replace('import QtQuick.Controls', 'import QtTest\nimport QtQuick.Controls', 1)
        source = source.replace('    ]\n    property int currentPage:', '    ].filter(entry => ["advanced", "wallpaper", "presets"].includes(entry.key))\n    property int currentPage:', 1)
        source = source.replace('    Component.onCompleted: {', '    Component.onCompleted: {\n        Quickshell.watchFiles = false;', 1)
        shared = r'''
    TestCase { id: input; when: false; windowShown: root.visible; name: "StyleSettings" }
    component DriverTimer: Timer {
        property bool handlingInput: false
        signal exercise()
        onTriggered: {
            if (handlingInput) return;
            handlingInput = true;
            try { exercise(); } finally { handlingInput = false; }
        }
    }
    property int stage: 0
    function named(name) { return input.findChild(currentPageItem, name); }
    function check(value, message) {
        if (!value) { console.log("CHECK_FAIL", stage, message); Qt.quit(); }
        return value;
    }
    Timer { interval: 22000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", root.stage, root.currentPageItem?.tab, root.named("presetIntro")?.running, root.named("presetDivider")?.value, root.currentPageItem?.selectedId); Qt.quit(); } }
'''
        source = source.replace('    id: root\n', '    id: root\n' + shared + probe, 1)
        stub = 'if [ "$5" = presets ]; then printf "%s\\n" "$*" >> "$HOME/preset-calls"; fi'
        output = self.runner.run_driver(source, settings_page=key, tool_stubs={'qs': stub, **(tool_stubs or {})}, screen_size=screen_size, initial_config=initial_config)
        self.assertIn('DRIVER_PASS', output, output[-5000:])
        self.assertNotRegex(output.split('DRIVER_PASS')[0], r'CHECK_FAIL|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign|recursive rearrange')

    def test_advanced_navigation_and_panorama(self):
        self.run_page('advanced', r'''
    property var safetyLink
    DriverTimer {
        interval: 140; repeat: true; running: Config.ready
        onExercise: {
            const page = root.currentPageItem;
            if (!page?.pageShown) {
                if (root.stage !== 3 || !root.searching) return;
            }
            const frame = root.named("panoramaFrame"), panorama = root.named("wallpaperPanorama");
            switch (root.stage) {
            case 0:
                if (!page?.pageShown) return;
                root.width = 1160; root.height = 820;
                break;
            case 1:
                if (root.named("advancedFileGrid")?.columns !== 2) return;
                root.safetyLink = root.findSection(page, "safety");
                root.safetyLink.clicked();
                if (!root.check(page.tab === "safety", "open public network filters")) return;
                root.goBack();
                break;
            case 2:
                if (!root.check(root.safetyLink.activeFocus, "return focus to safety")) return;
                Config.options.language.ui = "ru_RU"; root.width = 740; sidebar.expandOverride = true;
                sidebar.searchText = Translation.tr("Hide such wallpapers");
                break;
            case 3: {
                if (root.named("advancedFileGrid")?.columns !== 1) return;
                const match = searchView.results.find(row => row.pageIndex === root.pageIndex("advanced") && row.title === Translation.tr("Hide such wallpapers"));
                if (!match) { sidebar.searchText = Translation.tr("Hide such wallpapers"); return; }
                searchView.resultChosen(match.pageIndex, match.item);
                break;
            }
            case 4:
                if (page.tab !== "safety") return;
                root.goBack();
                root.openPage("wallpaper");
                break;
            case 5:
                if (!frame || page.tab !== "overview") return;
                if (!root.named("desktopWidget-clock")) return;
                if (!root.check(frame.logicalWidth === 1920 && frame.logicalHeight === 1200 &&
                    Math.abs(frame.width / frame.height - 1.6) < 0.008, "real monitor aspect")) return;
                frame.forceActiveFocus(); input.keyClick(Qt.Key_Right);
                if (!root.check(panorama.workspace === 2 && panorama.position === 2, "keyboard with motion off")) return;
                {
                    const media = root.named("panoramaMedia");
                    if (!root.check(media.fractionX === 1 && media.fractionY === 0.5, "horizontal workspace offset")) return;
                    root.findSection(page, "motion").clicked();
                }
                break;
            case 6:
                root.named("verticalParallax").click();
                break;
            case 7:
                if (!root.check(Config.options.background.parallax.vertical && root.named("panoramaMedia").fractionY === 1,
                    "saved vertical workspace offset")) return;
                root.goBack();
                break;
            case 8:
                root.named("panoramaLeftSidebar").click();
                if (!root.check(root.named("panoramaMedia").fractionX < 0.5, "sidebar shifts the background")) return;
                input.mousePress(frame, frame.width * 0.24, frame.height * 0.58);
                input.mouseMove(frame, frame.width * 0.32, frame.height * 0.58, 20, Qt.LeftButton);
                input.mouseMove(frame, frame.width * 0.87, frame.height * 0.58, 30, Qt.LeftButton);
                input.mouseRelease(frame, frame.width * 0.87, frame.height * 0.58);
                break;
            case 9:
                if (!root.check(panorama.workspace === 1 && panorama.position === 1, "drag snaps one workspace")) return;
                if (!root.check(Config.options.background.parallax.vertical && Math.abs(Config.options.background.parallax.workspaceZoom - 1.3) < 0.0001,
                    "panorama gestures changed saved parallax " + [Config.options.background.parallax.vertical, Config.options.background.parallax.workspaceZoom])) return;
                if (!root.check(!root.findSection(page, "sources"), "source preferences moved out of Wallpaper")) return;
                root.findSection(page, "greeter").clicked();
                if (!root.check(page.tab === "greeter", "GDM branch")) return;
                root.goBack();
                root.openPage("advanced");
                break;
            case 10:
                if (root.currentPageData.key !== "advanced") return;
                root.findSection(page, "sources").click();
                if (!root.check(page.tab === "sources" && !!root.findSection(page, Translation.tr("Online sources")) &&
                    !!root.findSection(page, Translation.tr("Wallpaper of the day")), "source controls live in Advanced")) return;
                root.goBack();
                root.openPage("wallpaper", "Online sources");
                break;
            case 11:
                if (root.currentPageData.key !== "advanced" || page.tab !== "sources") return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            root.stage++;
        }
    }
''', initial_config={'language': {'ui': 'en_US'}, 'appearance': {'animationSpeed': 0},
                     'background': {'parallax': {'enableWorkspace': True, 'workspaceZoom': 1.3, 'enableSidebar': True, 'vertical': False}}})

    def test_recent_wallpapers_preview_and_apply_in_order(self):
        self.run_page('wallpaper', r'''
    property string initialPath
    property string candidate
    FileView {
        id: wallpaperConfig
        path: Config.filePath
        blockLoading: true
        blockWrites: true
        function applyPath(path) {
            // switchwall.sh commits the selected wallpaper to the shared config file.
            reload();
            const config = JSON.parse(text());
            config.background.wallpaperPath = path;
            setText(JSON.stringify(config));
        }
    }
    FileView {
        id: recorded
        path: CF.FileUtils.trimFileProtocol(Directories.state) + "/recent-wallpapers.json"
        blockLoading: true; printErrors: false
        function keys() {
            reload();
            try { return JSON.parse(text()).entries.map(entry => entry.key); } catch (error) { return []; }
        }
    }
    FileView {
        id: wallpaperCalls
        path: CF.FileUtils.trimFileProtocol(Directories.home) + "/wallpaper-calls"
        printErrors: false
    }
    DriverTimer {
        interval: 100; repeat: true; running: Config.ready
        onExercise: {
            const gallery = root.named("wallpaperGallery"), sample = root.named("wallpaperSample-komona-sunset");
            if (!gallery?.pageShown || !Wallpapers.historyReady) return;
            const media = root.named("panoramaMedia"), cancel = root.named("wallpaperCancelPreview");
            const primary = root.named("wallpaperPrimaryAction"), frame = root.named("panoramaFrame");
            switch (root.stage) {
            case 0:
                if (!root.check(gallery.recent.length === 1 && gallery.recent[0].path === Config.options.background.wallpaperPath
                    && !root.named("wallpaperSample-mountain-night"), "fresh history contains only the active image")) return;
                Wallpapers.load();
                Directories.wallpaperSwitchScriptPath = "record-wallpaper";
                break;
            case 1:
                if (root.preloading || recorded.keys()[0] !== Config.options.background.wallpaperPath) return;
                wallpaperConfig.applyPath(Directories.defaultWallpaper);
                break;
            case 2:
                if (!sample || gallery.recent.length !== 2 || recorded.keys().length !== 2) return;
                root.initialPath = Config.options.background.wallpaperPath;
                sample.forceActiveFocus(); input.keyClick(Qt.Key_Return);
                break;
            case 3:
                root.candidate = gallery.chosen?.path ?? "";
                if (!root.check(root.candidate.endsWith("/komona-sunset.jpg") && media.picture === root.candidate &&
                    Config.options.background.wallpaperPath === root.initialPath && !wallpaperCalls.text().trim(),
                    "choosing art only changes the preview " + [root.candidate, media.picture, Config.options.background.wallpaperPath, root.initialPath, wallpaperCalls.text()])) return;
                input.keyClick(Qt.Key_Escape);
                if (!root.check(!gallery.chosen && media.picture === root.initialPath && recorded.keys()[0] === root.initialPath,
                    "Escape restores the current wallpaper and leaves history unchanged")) return;
                sample.click();
                cancel.click();
                if (!root.check(!gallery.chosen, "cancel restores the current wallpaper")) return;
                sample.click();
                primary.click();
                break;
            case 4: {
                wallpaperCalls.reload();
                const args = wallpaperCalls.text().trim().split("\n");
                if (args.length < 4) return;
                if (!root.check(args.length === 4 && args[0] === "--mode" && ["dark","light"].includes(args[1]) &&
                    args[2] === "--image" && args[3] === root.candidate, "apply sends only the selected wallpaper")) return;
                wallpaperConfig.applyPath(root.candidate);
                root.width = 690;
                break;
            }
            case 5: {
                if (recorded.keys()[0] !== root.candidate) return;
                if (!root.check(!gallery.chosen && !cancel.visible && Math.abs(frame.width/frame.height - 1.6) < 0.01,
                    "applied wallpaper and monitor ratio after compact layout")) return;
                if (!root.check(gallery.recent[0].path === root.candidate && gallery.recent[1].path === root.initialPath &&
                    recorded.keys().length === 2, "reapplying moves an existing file to the front")) return;
                const slider = root.named("wallpaperWorkspaceSlider"), panorama = root.named("wallpaperPanorama");
                input.mousePress(slider, slider.width*0.27, slider.height/2);
                input.mouseMove(slider, slider.width*0.38, slider.height/2, 20, Qt.LeftButton);
                input.mouseRelease(slider, slider.width*0.38, slider.height/2);
                if (!root.check(panorama.position > 0 && panorama.position < 1 && panorama.position !== Math.round(panorama.position), "continuous workspace control")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            }
            root.stage++;
        }
    }
''', initial_config={'language': {'ui': 'ru_RU'}, 'appearance': {'animationSpeed': 0},
                     'background': {'wallpaperPath': str(pages.SHELL / 'assets/images/komona-sunset.jpg')}},
            tool_stubs={'record-wallpaper': 'printf "%s\\n" "$@" >> "$HOME/wallpaper-calls"'})

    def test_live_wallpapers_and_history_from_another_session(self):
        with tempfile.TemporaryDirectory() as directory:
            photo = Path(directory) / 'Утро #8.jpg'
            video = Path(directory) / 'Волны и ветер.webm'
            poster = video.with_suffix('.webm.jpg')
            shutil.copyfile(pages.SHELL / 'assets/images/autumn.jpg', photo)
            shutil.copyfile(pages.SHELL / 'assets/images/komona-sunset.jpg', poster)
            video.touch()
            self.run_page('wallpaper', r'''
    readonly property string clipPath: VIDEO_FILE
    readonly property string posterPath: POSTER_FILE
    readonly property var previousColors: ["#112233", "#445566", "#778899", "#223344"]
    property int ipcTicks: 0
    FileView {
        id: previousSession
        path: CF.FileUtils.trimFileProtocol(Directories.state) + "/recent-wallpapers.json"
        blockWrites: true; printErrors: false
    }
    FileView {
        id: videoCalls
        path: CF.FileUtils.trimFileProtocol(Directories.home) + "/video-picker-result"
        blockLoading: true; printErrors: false
    }
    FileView {
        id: ipcResult
        path: CF.FileUtils.trimFileProtocol(Directories.home) + "/shader-ipc-result"
        blockLoading: true; printErrors: false
    }
    DriverTimer {
        interval: 120; repeat: true; running: Config.ready
        onExercise: {
            const gallery = root.named("wallpaperGallery"), media = root.named("panoramaMedia");
            const apply = root.named("wallpaperPrimaryAction"), chooseVideo = root.named("wallpaperChooseVideo");
            const page = root.currentPageItem;
            if (!gallery || !page.pageShown || !Wallpapers.historyReady) return;
            switch (root.stage) {
            case 0: {
                Directories.wallpaperSwitchScriptPath = "record-video";
                const missing = clipPath + ".removed.jpg";
                previousSession.setText(JSON.stringify({entries:[
                    {key:missing, path:missing, poster:missing},
                    {key:clipPath, path:clipPath, poster:posterPath},
                    {key:"shader:dunes", path:"", shader:"dunes", colors:previousColors, poster:ShaderWallpaper.posterPath("dunes")}
                ]}));
                break;
            }
            case 1:
                if (gallery.recent.length !== 3 || gallery.recent[2]?.shader !== "dunes") return;
                if (!root.check(gallery.recent[0].name === "Утро #8" && !gallery.recent[0].collectionPath
                    && gallery.recent[1].path === clipPath, "previous session restored and missing file skipped")) return;
                root.named("wallpaperSample-" + clipPath).click();
                if (!root.check(media.video === clipPath && media.picture === posterPath && !root.named("wallpaperPreviewPlayer").active,
                    "a recent video opens on its own still frame")) return;
                root.named("wallpaperLive-dunes").click();
                if (!root.check(media.shaderName === "dunes" && media.shaderColors[0] === previousColors[0] &&
                    !ShaderWallpaper.active && gallery.recent[0].name === "Утро #8", "a live draft preserves colors and history")) return;
                apply.click();
                break;
            case 2:
                if (++root.ipcTicks > 35 && ShaderWallpaper.name !== "dunes") {
                    ipcResult.reload();
                    root.check(false, "shader IPC: " + ipcResult.text() + " current=" + ShaderWallpaper.name + " selected=" + gallery.chosenKey);
                    return;
                }
                if (ShaderWallpaper.name !== "dunes") return;
                if (!root.check(JSON.stringify(Array.from(ShaderWallpaper.options.colors)) === JSON.stringify(previousColors) &&
                    !gallery.chosen && gallery.recent[0].shader === "dunes", "shell IPC applied the selected animation and palette")) return;
                root.findSection(page, "motion").click();
                if (!root.check(page.tab === "motion" && !chooseVideo.enabled && !root.named("wallpaperLive-dunes").enabled &&
                    root.findSection(page, Translation.tr("Video playback")).enabled, "Motion only offers preferences")) return;
                root.goBack();
                break;
            case 3:
                if (!chooseVideo.enabled || !gallery.pageShown) return;
                chooseVideo.click();
                break;
            case 4:
                videoCalls.reload();
                if (!videoCalls.text().trim()) return;
                if (!root.check(videoCalls.text().trim() === "--image\n" + clipPath, "video picker passes the exact filename")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            root.stage++;
        }
    }
'''.replace('VIDEO_FILE', json.dumps(str(video))).replace('POSTER_FILE', json.dumps(str(poster))),
                initial_config={'appearance': {'animationSpeed': 0}, 'background': {'wallpaperPath': str(photo)}},
                tool_stubs={
                    'qs': f'printf "%s\\n" "$*" >> "$HOME/shader-ipc-result"; if [ "$5" = shaderWallpaper ]; then shift 3; {shlex.quote(pages.QS)} ipc --any-display -p "${{HOME%/*}}/shell/shell.qml" "$@" >> "$HOME/shader-ipc-result" 2>&1; fi',
                    'kdialog': f'printf "%s\\n" {shlex.quote(str(video))}',
                    'record-video': 'printf "%s\\n" "$@" > "$HOME/video-picker-result"',
                })

    def test_wallpaper_shuffle_from_overview(self):
        with tempfile.TemporaryDirectory() as directory:
            random_scripts = Path(directory) / 'colors/random'
            random_scripts.mkdir(parents=True)
            personal = Path(directory) / 'My wallpapers'
            (personal / 'Albums').mkdir(parents=True)
            personal_file = personal / 'Мой кадр #4.jpg'
            shutil.copyfile(pages.SHELL / 'assets/images/autumn.jpg', personal_file)
            for provider in ['wallhaven', 'konachan']:
                script = random_scripts / f'random_{provider}_wall.sh'
                script.write_text(f'#!/bin/sh\nprintf "%s\\n" "{provider}" >> "$HOME/shuffle-calls"\n')
                script.chmod(0o755)
            self.run_page('wallpaper', r'''
    FileView {
        id: shuffleCalls
        path: CF.FileUtils.trimFileProtocol(Directories.home) + "/shuffle-calls"
        blockLoading: true; printErrors: false
    }
    DriverTimer {
        interval: 120; repeat: true; running: Config.ready
        onExercise: {
            const gallery = root.named("wallpaperGallery"), shuffle = root.named("wallpaperRandomAction");
            const picker = root.named("wallpaperRandomSource"), frame = root.named("panoramaFrame"), strip = root.named("wallpaperFilmstrip");
            if (!gallery?.pageShown || !gallery.collection.length || !shuffle || !picker) return;
            shuffleCalls.reload();
            const calls = shuffleCalls.text().trim().split("\n").filter(Boolean);
            switch (root.stage) {
            case 0:
                root.width = 1040;
                Directories.scriptPath = SCRIPT_DIR;
                Directories.wallpaperSwitchScriptPath = "record-collection";
                break;
            case 1:
                if (!gallery.sideRail) return;
                if (!root.check(strip.mapToItem(gallery, 0, 0).x >= frame.mapToItem(gallery, frame.width, 0).x - 1 &&
                    picker.visible && picker.currentValue === "wallhaven" && shuffle.visible, "wide photo and capture actions")) return;
                shuffle.forceActiveFocus(); input.keyClick(Qt.Key_Return);
                break;
            case 2:
                if (calls.length < 1) return;
                picker.openPopup();
                picker.pick({kind:"option", option:picker.options.find(option => option.value === "konachan")});
                break;
            case 3:
                if (calls.length < 2) return;
                shuffle.click();
                break;
            case 4:
                if (calls.length < 3) return;
                if (!root.check(calls.join(",") === "wallhaven,konachan,konachan", "one provider call per deliberate action")) return;
                Config.options.policies.weeb = 0;
                root.width = 640; sidebar.expandOverride = true;
                break;
            case 5:
                if (gallery.sideRail) return;
                if (!root.check(!picker.visible && picker.currentValue === "collection" && shuffle.enabled &&
                    strip.mapToItem(gallery, 0, 0).y >= frame.mapToItem(gallery, 0, frame.height).y - 1,
                    "compact photo strip and offline shuffle")) return;
                root.named("wallpaperLive-grid").click();
                shuffle.click();
                break;
            case 6:
                if (calls.length < 4) return;
                if (!root.check(calls.length === 4 && calls[3] !== gallery.currentKey &&
                    gallery.collection.some(entry => entry.path === calls[3]) && !gallery.chosen,
                    "local shuffle picks another installed image and clears the draft")) return;
                Wallpapers.directory = CF.FileUtils.fileUrl(PERSONAL_DIR);
                break;
            case 7:
                if (Wallpapers.filesInCurrentFolder().length !== 1) return;
                shuffle.click();
                break;
            case 8:
                if (calls.length < 5) return;
                if (!root.check(calls[4] === PERSONAL_FILE, "local shuffle uses a personal picture and skips directories")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            root.stage++;
        }
    }
'''.replace('SCRIPT_DIR', json.dumps(directory)).replace('PERSONAL_DIR', json.dumps(str(personal)))
                .replace('PERSONAL_FILE', json.dumps(str(personal_file))), initial_config={'language': {'ui': 'ru_RU'}, 'appearance': {'animationSpeed': 0},
            'policies': {'weeb': 1}, 'background': {'wallpaperPath': str(pages.SHELL / 'assets/images/autumn.jpg')}},
                tool_stubs={'record-collection': 'printf "%s\\n" "$4" >> "$HOME/shuffle-calls"'})

    def test_static_photographs_in_all_preset_sections(self):
        self.run_page('presets', r'''
    property var card
    property var samples: ["autumn", "material-glass", "bar-floating"]
    property int sampleIndex: 0
    DriverTimer {
        interval: 100; repeat: true; running: Config.ready
        onExercise: {
            const page = root.currentPageItem;
            if (!page?.pageShown) return;
            switch (root.stage) {
            case 0: {
                root.card = root.named("presetCard-" + root.samples[root.sampleIndex]);
                if (!root.card) return;
                const pane = page.scrollerOf(root.card);
                pane.contentY = Math.max(0, Math.min(root.card.mapToItem(pane.contentItem, 0, 0).y - 15, pane.contentHeight - pane.height));
                break;
            }
            case 1: {
                const photo = input.findChild(root.card, "presetCover"), layer = input.findChild(root.card, "presetCoverInterface");
                if (photo.status !== Image.Ready || layer.status !== Image.Ready) return;
                if (!root.check(photo.source.toString().endsWith("autumn.jpg") &&
                    layer.source.toString().endsWith("/" + root.samples[root.sampleIndex] + ".png") &&
                    !root.named("desktopSurface") && !page.coverCache.frames.size,
                    "a photograph and its desktop UI in each catalog section")) return;
                if (++root.sampleIndex < root.samples.length) { root.stage = 0; return; }
                root.card.click();
                break;
            }
            case 2:
                if (!root.card.captured) return;
                root.goBack();
                break;
            case 3: {
                const layer = input.findChild(root.card, "presetCoverInterface");
                if (layer.status !== Image.Ready) return;
                if (!root.check(layer.source.toString() === root.card.captured.url.toString() &&
                    !root.named("desktopSurface"), "returning shows the actual completed comparison as a single photograph")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            }
            root.stage++;
        }
    }
''', initial_config={'appearance': {'animationSpeed': 0}, 'background': {'wallpaperPath': str(pages.SHELL / 'assets/images/autumn.jpg'),
                        'widgets': {'clock': {'enable': True, 'style': 'cookie', 'placementStrategy': 'free'}}}})

    def test_preset_comparison_and_explicit_apply(self):
        self.run_page('presets', r'''
    property var card
    property string saved
    FileView {
        id: calls
        path: CF.FileUtils.trimFileProtocol(Directories.home) + "/preset-calls"
        watchChanges: true
        onFileChanged: reload()
    }
    function snapshot() {
        return JSON.stringify([Config.options.bar.vertical, Config.options.bar.style.radius, Config.options.dock.enable,
            Config.options.background.wallpaperPath, Config.options.appearance.palette.type]);
    }
    function clickInView(item) {
        const pane = currentPageItem.scrollerOf(item);
        pane.stopScroll();
        const top = item.mapToItem(pane.contentItem, 0, 0).y;
        pane.contentY = Math.max(0, Math.min(top - 20, pane.contentHeight - pane.height));
        input.mouseClick(item, item.width / 2, item.height / 3);
    }
    DriverTimer {
        interval: 150; running: Config.ready; repeat: true
        onExercise: {
            const page = root.currentPageItem;
            if (!page?.pageShown) return;
            switch (root.stage) {
            case 0: {
                if (!Presets.find("autumn") || Presets.loading) return;
                const autumn = root.named("presetCard-autumn");
                if (!autumn || input.findChild(autumn, "presetCover")?.status !== Image.Ready ||
                    input.findChild(autumn, "presetCoverInterface")?.status !== Image.Ready) return;
                input.mouseMove(autumn, autumn.width / 2, autumn.height / 3);
                if (!root.check(!input.findChild(autumn, "desktopSurface") && !input.findChild(autumn, "wallpaperPreviewPlayer"),
                    "the gallery displays a still of the desktop on the photograph, including on hover")) return;
                if (!root.check(Presets.find("folis")?.name === "Velora" && Presets.find("bar-folis")?.name === "Velora bar", "Velora preset names")) return;
                Presets.importPreset({name:"Subset",
                    bar:{config:{bar:{vertical:true, style:{glass:true}}}},
                    dockWidgets:{config:{dock:{enable:false}}},
                    wallpaperAnimations:{wallpaper:"daily:bing"},
                    theme:{accent:"#AE4210", mode:"dark"}, lock:{config:{lock:{dim:0.4}}},
                    windows:{hyprland:{"shell:windowMode":"floating"}}});
                root.saved = root.snapshot();
                break;
            }
            case 1:
                root.card = root.named("presetCard-user:subset");
                if (!root.card) return;
                root.card.forceActiveFocus();
                input.keyClick(Qt.Key_Return);
                break;
            case 2: {
                const scene = root.named("candidateScene"), divider = root.named("presetDivider");
                if (!scene || !divider) return;
                const panel = input.findChild(scene, "desktopPreviewBar");
                if (!panel) return;
                if (!root.check(panel.preview && panel.vertical && panel.height === scene.monitor.logicalHeight &&
                    Math.abs(scene.width / scene.height - scene.monitor.aspect) < 0.008, "monitor aspect and real full-height bar")) return;
                if (!root.check(scene.vertical && scene.barStyle.radius === 23 && scene.barStyle.glass && !scene.dock.enable, "merged partial preset " + JSON.stringify([scene.vertical,scene.barStyle.radius,scene.barStyle.glass,scene.dock.enable,Config.options.bar.style.radius]))) return;
                if (!root.check(root.named("previewPart-lock").description.includes("40") &&
                    root.named("previewPart-windows").description === Translation.tr("Free windows"), "lock and window summaries")) return;
                divider.forceActiveFocus(); input.keyClick(Qt.Key_Right);
                if (!root.check(divider.value > 0.5, "keyboard comparison")) return;
                input.mousePress(divider, divider.width * 0.6, divider.height / 2);
                input.mouseMove(divider, divider.width * 0.79, divider.height / 2, 25, Qt.LeftButton);
                input.mouseRelease(divider, divider.width * 0.79, divider.height / 2);
                if (!root.check(Math.abs(divider.value - 0.79) < 0.03 && scene.width === divider.width, "drag reveals without resizing")) return;
                for (const part of page.chosenCategories.slice()) root.named("previewPart-" + part).clicked();
                if (!root.check(!root.named("applyPresetSelection").enabled && !scene.vertical && scene.dock.enable && !scene.showBackdrop,
                    "empty selection projects the current desktop")) return;
                root.named("previewPart-bar").clicked();
                if (!root.check(scene.vertical && scene.dock.enable && !scene.showBackdrop, "bar-only preview")) return;
                root.goBack();
                break;
            }
            case 3:
                if (page.tab === "overview" && !root.card.activeFocus) return;
                if (!root.check(page.tab === "overview" && root.card.activeFocus, "focus restored to preset " +
                    [root.currentPageData.key, page.tab, root.activeFocusItem, page.detailHistory.map(entry => entry.key)])) return;
                if (!root.check(!calls.text().trim() && root.snapshot() === root.saved, "preview sent a command or changed settings")) return;
                root.clickInView(root.card);
                if (!root.check(page.tab === "preview", "the card opens the comparison on click")) return;
                for (const part of page.chosenCategories.slice()) if (part !== "theme") root.named("previewPart-" + part).clicked();
                root.named("applyPresetSelection").click();
                break;
            case 4:
                if (!calls.text().includes("presets apply user:subset theme")) { calls.reload(); return; }
                if (!root.check(page.tab === "overview", "apply returns to catalog")) return;
                root.clickInView(root.named("quickApply-bar-floating"));
                if (!root.check(page.tab === "overview", "quick apply stays in the catalog")) return;
                break;
            case 5: {
                const lines = calls.text().trim().split("\n");
                if (lines.length < 2) { calls.reload(); return; }
                if (!root.check(lines.join("|") === "-c ii ipc call presets apply user:subset theme|-c ii ipc call presets apply bar-floating bar",
                    "exactly one apply per explicit action")) return;
                root.clickInView(root.findSection(page, "save"));
                if (!root.check(page.tab === "save", "create from the catalog")) return;
                root.goBack();
                root.clickInView(root.findSection(page, "importPreset"));
                if (!root.check(page.tab === "importPreset", "import from the catalog")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            }
            root.stage++;
        }
    }
''', initial_config={'appearance': {'animationSpeed': 0}, 'bar': {'vertical': False, 'style': {'radius': 23}}, 'dock': {'enable': True}})

    def test_intro_sweep_and_continuous_drag_on_portrait_monitor(self):
        self.run_page('presets', r'''
    property bool sawSweep: false
    property real minimumSplit: 1
    property real releasedAt: 0
    property int stillTicks: 0
    Timer {
        interval: 24; repeat: true; running: Config.ready
        onTriggered: {
            const page = root.currentPageItem;
            if (!page?.pageShown) return;
            const divider = root.named("presetDivider"), intro = root.named("presetIntro");
            switch (root.stage) {
            case 0:
                if (Presets.loading || !root.named("presetCard-mountain-night")) return;
                Config.options.powerSaving.mode = "off";
                Config.options.appearance.animationSpeed = 1;
                root.named("presetCard-mountain-night").clicked();
                break;
            case 1: {
                if (!divider || !intro) return;
                if (intro.running) {
                    root.sawSweep = true;
                    root.minimumSplit = Math.min(root.minimumSplit, divider.value);
                    return;
                }
                if (!root.sawSweep || Math.abs(divider.value - 0.5) > 0.001) return;
                if (!root.check(root.minimumSplit < 0.02, "new look fully revealed before resting at the middle")) return;
                const scene = root.named("candidateScene"), clock = input.findChild(scene, "desktopWidget-clock");
                if (!clock) return;
                if (!root.check(clock.clockStyle === "digital" && clock.scaledScreenWidth === 1080 &&
                    clock.scaledScreenHeight === 1920 && Math.abs(scene.width / scene.height - 9 / 16) < 0.006,
                    "real digital clock on a portrait desktop")) return;
                if (!root.check(!Notifications.serving, "settings started a notification server")) return;
                const timers = Persistent.states.timer;
                timers.countdown.end = 1;
                timers.countdown.running = true;
                timers.pomodoro.start = 1;
                timers.pomodoro.running = true;
                const phase = timers.pomodoro.isBreak;
                TimerService.refreshCountdown();
                TimerService.refreshPomodoro();
                if (!root.check(timers.countdown.running && timers.pomodoro.isBreak === phase &&
                    TimerService.countdownSecondsLeft === 0 && TimerService.pomodoroSecondsLeft === 0,
                    "previews show expired timers without completing a desktop session's alarms")) return;
                timers.countdown.running = false;
                timers.pomodoro.running = false;
                root.goBack();
                break;
            }
            case 2:
                if (page.tab !== "overview") return;
                root.named("presetCard-autumn").clicked();
                break;
            case 3: {
                if (!intro?.running || divider.value >= 0.95 || divider.value < 0.1) return;
                const x = Math.floor(divider.width * 0.41);
                input.mousePress(divider, x, divider.height / 2);
                input.mouseMove(divider, x + 1, divider.height / 2, 12, Qt.LeftButton);
                const first = divider.value;
                input.mouseMove(divider, x + 4, divider.height / 2, 12, Qt.LeftButton);
                input.mouseRelease(divider, x + 4, divider.height / 2);
                if (!root.check(!intro.running && divider.value > first && divider.value - first < 0.024,
                    "continuous drag interrupts the sweep with sub-step precision")) return;
                root.releasedAt = divider.value;
                break;
            }
            case 4:
                if (++root.stillTicks < 12) return;
                if (!root.check(Math.abs(divider.value - root.releasedAt) < 0.0001, "released divider stays in place")) return;
                {
                    const scene = root.named("candidateScene");
                    const shelf = input.findChild(scene, "desktopPreviewDock"), bar = input.findChild(scene, "desktopPreviewBar");
                    const clock = input.findChild(scene, "desktopWidget-clock"), weather = input.findChild(scene, "desktopWidget-weather");
                    if (!shelf || !bar?.zoneItems[0].hasContent || !clock || !weather) return;
                    if (!root.check(Qt.colorEqual(shelf.background.color, "#261812") && Qt.colorEqual(bar.barColors.colBarBackground, "#261812") &&
                        bar.vertical && bar.zoneItems[0].orderedHosts().length > 0, "Autumn's dark dock and visible left islands")) return;
                    if (!root.check(Qt.colorEqual(clock.widgetColors.colSecondaryContainer, "#773207") &&
                        Qt.colorEqual(weather.widgetColors.colOnSecondaryContainer, "#ffd8c7"), "Autumn's generated container and foreground pair")) return;
                }
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            root.stage++;
        }
    }
''', screen_size=(1080, 1920))

    @unittest.skipUnless(shutil.which('ffmpeg'), 'needs ffmpeg for a test video')
    def test_video_poster_play_pause_and_missing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            video = Path(directory) / 'test clip.mp4'
            subprocess.run(['ffmpeg', '-loglevel', 'error', '-f', 'lavfi', '-i', 'color=c=teal:s=96x64:r=12',
                            '-t', '1', '-c:v', 'mpeg4', str(video)], check=True)
            poster = video.with_suffix('.mp4.jpg')
            subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', str(video), '-frames:v', '1', str(poster)], check=True)
            self.run_page('wallpaper', r'''
    Timer {
        interval: 160; running: Config.ready; repeat: true
        onTriggered: {
            const page = root.currentPageItem;
            const media = root.named("panoramaMedia");
            if (!media || !page.pageShown) return;
            const player = input.findChild(media, "wallpaperPreviewPlayer");
            switch (root.stage) {
            case 0:
                Config.options.background.wallpaperPath = VIDEO;
                Config.options.background.thumbnailPath = POSTER;
                break;
            case 1:
                if (input.findChild(media, "wallpaperPreviewPicture").status !== Image.Ready) return;
                if (!root.check(media.picture === POSTER && !player.active, "poster before play")) return;
                root.named("panoramaPlay").click();
                break;
            case 2:
                if (!player.item?.hasVideo || player.item.position <= 0) return;
                Config.options.powerSaving.mode = "on";
                if (!root.check(!player.active, "saving power releases the player")) return;
                Config.options.powerSaving.mode = "off";
                root.named("panoramaPlay").click();
                page.navigateToSection("motion");
                if (!root.check(!player.active, "leaving overview releases the player")) return;
                page.navigateBack();
                Config.options.background.wallpaperPath = VIDEO + ".missing.jpg";
                break;
            case 3:
                if (input.findChild(media, "wallpaperPreviewPicture").status !== Image.Error) return;
                if (!root.check(media.unavailable && !root.named("panoramaPlay").visible && !player.active, "unavailable image fallback")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            root.stage++;
        }
    }
'''.replace('VIDEO', json.dumps(str(video))).replace('POSTER', json.dumps(str(poster))))
