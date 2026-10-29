pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * System presets: bundles of settings in four categories that can be applied separately.
 *   bar                  bar layout and style
 *   theme                colors, light/dark, transparency, fonts, window rounding, blur and shadows
 *   dockWidgets          the dock and the desktop widgets
 *   wallpaperAnimations  the wallpaper (a picture, a video or an animated "shader:<name>"), gaps and motion
 *   lock                 the lock screen: arrangement, animations, darkening, blur, clock style
 *   windows              free windows (as on Windows and macOS) or tiling, and the tiling layout
 * Each category may hold `config` (a partial config.json, limited to the paths below) and
 * `hyprland` (Hyprland options for HyprlandSettings), plus `mode`/`scheme` (theme),
 * `wallpaper` and `animationProfile` (wallpaperAnimations). A video from the web may come with
 * `loop: { start, end, crossfade }` (seconds): that part of it is made to repeat without a jump.
 *
 * Built-in presets are defaults/presets/*.json; your own are saved under
 * ~/.config/illogical-impulse/presets/<slug>/preset.json (with a copy of the wallpaper).
 * Applying runs in the shell (IPC "presets"), after backing up what it changes for undo. Everything
 * slow happens while the screen is still live: downloading the wallpaper, generating its palette
 * (switchwall --prepare) and decoding it on every screen. Only then is the screen captured, and
 * under that picture the prepared files, settings and layout are put in place in a moment.
 */
Singleton {
    id: root

    readonly property list<string> categoryIds: ["bar", "theme", "dockWidgets", "wallpaperAnimations", "lock", "windows"]
    readonly property var categories: [
        { "id": "bar", "name": Translation.tr("Bar"), "icon": "toast" },
        { "id": "theme", "name": Translation.tr("Theme and colors"), "icon": "palette" },
        { "id": "dockWidgets", "name": Translation.tr("Dock and desktop widgets"), "icon": "widgets" },
        { "id": "wallpaperAnimations", "name": Translation.tr("Wallpaper and motion"), "icon": "animation" },
        { "id": "lock", "name": Translation.tr("Lock screen"), "icon": "lock" },
        { "id": "windows", "name": Translation.tr("Window behavior"), "icon": "select_window" },
    ]
    // Config paths each category may change; anything else in a preset is ignored
    readonly property var allowedPaths: ({
        "bar": ["bar"],
        "theme": ["appearance.palette", "appearance.transparency", "appearance.fonts", "appearance.extraBackgroundTint", "appearance.fakeScreenRounding"],
        "dockWidgets": ["dock", "background.widgets"],
        "wallpaperAnimations": ["appearance.animationSpeed", "background.liveWallpaper.pauseWhen", "background.shaderWallpaper"],
        "lock": ["lock.layout", "lock.animations", "lock.animatedWallpaper", "lock.dim", "lock.blur", "lock.showLockedText", "background.widgets.clock.styleLocked"],
        "windows": [],
    })
    // Hyprland options each category may change, by prefix (RegExps don't survive a `var` property)
    readonly property var allowedHyprland: ({
        "theme": ["decoration:", "general:border_size"],
        "wallpaperAnimations": ["general:gaps_", "animations:enabled", "misc:animate_"],
        "windows": ["shell:windowMode", "general:layout"],
    })
    function hyprlandAllowed(category, key) {
        return (root.allowedHyprland[category] ?? []).some(prefix => key.startsWith(prefix));
    }

    readonly property string builtinDir: FileUtils.trimFileProtocol(Quickshell.shellPath("defaults/presets"))
    readonly property string userDir: `${Directories.shellConfig}/presets`
    readonly property string backupDir: `${FileUtils.trimFileProtocol(Directories.state)}/user/presets/backup`

    property list<var> presets: []
    property bool loading: listProc.running
    property bool hasBackup: false
    property bool applying: false
    property bool interactivePreview: false
    // A snapshot would freeze the setup assistant's hover, press and selection animations.
    Binding {
        target: ThemeTransition
        property: "captureInhibited"
        value: root.applying && root.interactivePreview
    }

    signal applied(string id)

    function load() {
        listProc.running = false;
        listProc.running = true;
        backupCheck.running = true;
        downloadedProc.running = false;
        downloadedProc.running = true;
    }

    // File names in the folder of downloaded preset videos, so a card can play its look's own loop
    property list<string> downloadedVideos: []
    readonly property string videoDir: `${FileUtils.trimFileProtocol(Directories.videos)}/Wallpapers/Presets`

    readonly property var defaultPreset: root.presets.find(preset => preset.isDefault) ?? null

    function find(id) {
        return root.presets.find(preset => preset.id === id) ?? null;
    }

    // Which categories a preset has something for
    function categoriesOf(preset) {
        return root.categoryIds.filter(id => preset?.[id] && typeof preset[id] === "object");
    }

    // Commands a preset would run through bar widgets, to show before importing it
    function commandsIn(preset) {
        let commands = [];
        const bar = preset?.bar?.config?.bar ?? {};
        for (const layout of [bar.layout, bar.verticalLayout]) commands.push(...BarLayout.commandsIn(layout));
        return commands;
    }

    function getPath(object, path) {
        let node = object;
        for (const key of path.split(".")) {
            if (node === null || node === undefined || typeof node !== "object") return undefined;
            node = node[key];
        }
        return node;
    }

    function setPath(object, path, value) {
        const keys = path.split(".");
        let node = object;
        for (let i = 0; i < keys.length - 1; i++) {
            if (typeof node[keys[i]] !== "object" || node[keys[i]] === null) node[keys[i]] = {};
            node = node[keys[i]];
        }
        node[keys[keys.length - 1]] = value;
    }

    // Keeps only the allowed paths of a config patch
    function filterConfig(config, paths) {
        let result = {};
        for (const path of paths) {
            const value = root.getPath(config ?? {}, path);
            if (value !== undefined) root.setPath(result, path, JSON.parse(JSON.stringify(value)));
        }
        if (result.bar) delete result.bar.screenList; // Screens are per machine
        if (result.appearance?.palette) delete result.appearance.palette.accentColor; // Written by switchwall
        return result;
    }

    function mergeInto(target, source) {
        for (const key of Object.keys(source)) {
            if (source[key] !== null && typeof source[key] === "object" && !Array.isArray(source[key])
                && target[key] !== null && typeof target[key] === "object" && !Array.isArray(target[key])) {
                root.mergeInto(target[key], source[key]);
            } else {
                target[key] = source[key];
            }
        }
        return target;
    }

    // switchwall arguments for a preset's accent color: a fixed one, or colors from the wallpaper
    function accentArgs(preset) {
        const accent = preset.theme?.accent ?? preset.theme?.config?.appearance?.palette?.accentColor ?? "";
        return /^#?[0-9a-f]{6}$/i.test(accent) ? ["--color", accent.startsWith("#") ? accent : `#${accent}`] : ["--color", "clear"];
    }

    function themeOptions(preset) {
        const scheme = preset.theme?.config?.appearance?.palette?.type;
        return [...(["dark", "light"].includes(preset.theme?.mode) ? ["--mode", preset.theme.mode] : []),
            ...(scheme ? ["--type", scheme] : []), ...root.accentArgs(preset)];
    }

    function isRemote(path) {
        return /^https?:\/\//.test(path ?? "");
    }

    // Where a preset's wallpaper from the web is kept once downloaded: pictures with pictures, videos with videos
    function remoteWallpaperPath(preset) {
        const url = preset.wallpaperAnimations.wallpaper.split("?")[0];
        const video = FileUtils.isVideoPath(url);
        // A made loop is always H.264 in MP4 (scripts/colors/random/common.sh, make_loop)
        const ext = root.loopArgs(preset).length > 0 ? "mp4"
            : video ? url.split(".").pop().toLowerCase() : (url.match(/\.(jpe?g|png|webp)$/i)?.[1] ?? "jpg").toLowerCase();
        const dir = video ? root.videoDir : `${FileUtils.trimFileProtocol(Directories.pictures)}/Wallpapers/Presets`;
        return `${dir}/${preset.id.replace(/[^A-Za-z0-9._-]/g, "_")}.${ext}`;
    }

    // download_wallpaper.sh arguments for a video's `loop`, if it has a usable one
    function loopArgs(preset) {
        const loop = preset?.wallpaperAnimations?.loop;
        if (!loop || !(loop.end > loop.start) || !(loop.start >= 0)) return [];
        const crossfade = loop.crossfade > 0 ? loop.crossfade : 0.6;
        return ["--loop", `${loop.start}:${loop.end}:${crossfade}`];
    }

    // A moving wallpaper: a video, or an animated one drawn by the shell (ShaderWallpaper)
    function isLive(preset) {
        const wallpaper = preset?.wallpaperAnimations?.wallpaper ?? "";
        return wallpaper.startsWith("shader:") || FileUtils.isVideoPath(wallpaper.split("?")[0]);
    }

    // Image for a preset's card: its own preview (a link, or a file next to the built-in presets),
    // the frame saved with a video, or the wallpaper saved with it
    function previewOf(preset) {
        const preview = preset?.wallpaperPreview ?? "";
        if (root.isRemote(preview)) return preview;
        if (preview.length > 0 && preset.kind === "builtin") return `file://${root.builtinDir}/${preview}`;
        const local = root.wallpaperFile(preset);
        if (local.length > 0 && FileUtils.isVideoPath(local)) return preset.dir ? `file://${preset.dir}/preview.jpg` : "";
        return local.length > 0 ? `file://${local}` : "";
    }

    // A short clip for the card to play while the pointer is on it
    function previewVideoOf(preset) {
        const clip = preset?.wallpaperPreviewVideo ?? "";
        if (root.isRemote(clip)) return clip;
        const local = root.wallpaperFile(preset);
        if (local.length > 0 && FileUtils.isVideoPath(local)) return `file://${local}`;
        // A video from the web plays on the card once it has been downloaded, never streamed
        const wallpaper = preset?.wallpaperAnimations?.wallpaper ?? "";
        if (!root.isRemote(wallpaper) || !FileUtils.isVideoPath(wallpaper.split("?")[0])) return "";
        const downloaded = root.remoteWallpaperPath(preset);
        return root.downloadedVideos.includes(downloaded.split("/").pop()) ? `file://${downloaded}` : "";
    }

    function wallpaperFile(preset) {
        const wallpaper = preset?.wallpaperAnimations?.wallpaper ?? "";
        if (!wallpaper || wallpaper.startsWith("daily:") || wallpaper.startsWith("shader:") || root.isRemote(wallpaper)) return "";
        if (wallpaper.startsWith("/")) return wallpaper;
        return preset.dir ? `${preset.dir}/${wallpaper}` : "";
    }

    // Applies the chosen categories of a preset (all it has when `categories` is empty). "motion" is
    // wallpaperAnimations without the wallpaper: its gaps and animations on the picture you have.
    // `themeFrom` takes the theme of another preset instead, so different looks share one palette;
    // `mode` ("light" or "dark") overrides the one the theme has.
    function apply(id, categories = [], themeFrom = "", mode = "", interactivePreview = false) {
        let preset = root.find(id);
        if (!preset) {
            console.warn("[Presets] Unknown preset", id);
            return;
        }
        const themeSource = themeFrom === "current" ? { "theme": {
            "mode": Appearance.m3colors.darkmode ? "dark" : "light",
            "accent": Config.options.appearance.palette.accentColor ?? "",
        } } : themeFrom.length > 0 ? root.find(themeFrom) : preset;
        if (themeSource?.theme && (themeFrom.length > 0 || ["light", "dark"].includes(mode))) {
            const theme = Object.assign({}, themeSource.theme, ["light", "dark"].includes(mode) ? { "mode": mode } : {});
            preset = Object.assign({}, preset, { "theme": theme });
        }
        if (categories.includes("motion") && preset.wallpaperAnimations) {
            const motion = Object.assign({}, preset.wallpaperAnimations);
            delete motion.wallpaper;
            delete motion.loop;
            preset = Object.assign({}, preset, { "wallpaperAnimations": motion });
            categories = categories.map(category => category === "motion" ? "wallpaperAnimations" : category);
        }
        const chosen = (categories.length > 0 ? categories : root.categoriesOf(preset)).filter(category => preset[category]);
        if (chosen.length === 0) return;
        root.applyCount++;
        themeTimer.stop();
        ThemeTransition.release(root.activeTransition);
        root.activeTransition = 0;
        root.interactivePreview = interactivePreview;
        root.applying = true;
        root.pending = { "preset": preset, "categories": chosen, "applyCount": root.applyCount };
        backupProc.running = true; // Continues in finishApply() once the backup is written
    }

    property var pending: null

    // Counts applies, so a download that finishes after another look was applied doesn't switch back to its own
    property int applyCount: 0

    property int activeTransition: 0
    property int transitionApplyCount: 0
    property bool waitingForColors: false
    property string activePresetId: ""

    function finishApply() {
        const request = root.pending;
        root.pending = null;
        if (!request || request.applyCount !== root.applyCount) return;
        const preset = request.preset;
        const remote = request.categories.includes("wallpaperAnimations") && root.isRemote(preset.wallpaperAnimations.wallpaper);
        if (remote) {
            // Network and video encoding happen before a screen is captured.
            const dest = root.remoteWallpaperPath(preset);
            downloadProc.start(request, dest,
                [Quickshell.shellPath("scripts/colors/random/download_wallpaper.sh"), preset.wallpaperAnimations.wallpaper,
                 dest, "--meta", JSON.stringify(preset.credits ?? {}), "--title", Translation.tr(preset.name), ...root.loopArgs(preset)]);
        } else {
            root.prepareTheme(request, "");
        }
    }

    // switchwall arguments for what a preset changes, or null when it needs no run of it here
    // (an animated or daily wallpaper brings its own colors)
    function themeArgs(preset, chosen, downloadedWallpaper) {
        const setting = chosen.includes("wallpaperAnimations") ? (preset.wallpaperAnimations.wallpaper ?? "") : "";
        if (setting.startsWith("shader:") || setting.startsWith("daily:")) return null;
        const remote = root.isRemote(setting);
        const wallpaper = remote ? downloadedWallpaper : setting.length > 0 ? root.wallpaperFile(preset) : "";
        if (wallpaper.length === 0 && !remote && !chosen.includes("theme")) return null;
        const modeArgs = chosen.includes("theme") ? root.themeOptions(preset) : [];
        return [...(wallpaper.length > 0 ? ["--image", wallpaper] : ["--noswitch"]), ...modeArgs];
    }

    // While the screen is still live: the palette generated aside, then the new picture decoded
    function prepareTheme(request, downloadedWallpaper) {
        if (request.applyCount !== root.applyCount) return;
        request.downloadedWallpaper = downloadedWallpaper;
        const args = root.themeArgs(request.preset, request.categories, downloadedWallpaper);
        if (args === null) {
            root.startTransition(request, null);
            return;
        }
        prepareJob.createObject(root, { "request": request, "command": [Directories.wallpaperSwitchScriptPath, "--prepare", ...args] });
    }

    function preloadThenStart(request, prepared) {
        if (request.applyCount !== root.applyCount) return;
        const picture = prepared ? (FileUtils.isVideoPath(prepared.wallpaper) ? prepared.thumbnail : prepared.wallpaper) : "";
        if (!picture || WallpaperTransition.isPreloaded(picture)) {
            root.startTransition(request, prepared);
            return;
        }
        preloadWait.request = request;
        preloadWait.prepared = prepared;
        preloadWait.picture = picture;
        preloadWait.restart();
        WallpaperTransition.preload(picture);
    }
    function startPreloaded() {
        const request = preloadWait.request;
        preloadWait.stop();
        preloadWait.request = null;
        if (request) root.startTransition(request, preloadWait.prepared);
    }
    Timer {
        id: preloadWait
        property var request: null
        property var prepared: null
        property string picture: ""
        interval: 1500 // A screen that can't decode it in time decodes it under the picture instead
        onTriggered: root.startPreloaded()
    }

    function startTransition(request, prepared) {
        if (request.applyCount !== root.applyCount) return;
        ThemeTransition.run(token => {
            if (request.applyCount !== root.applyCount) {
                ThemeTransition.release(token);
                return;
            }
            root.activeTransition = token;
            root.transitionApplyCount = request.applyCount;
            root.activePresetId = request.preset.id;
            root.applyNow(request.preset, request.categories, request.applyCount, request.downloadedWallpaper ?? "", prepared);
        }, true);
    }

    function colorsFinished(applyCount) {
        if (applyCount !== root.applyCount || applyCount !== root.transitionApplyCount) return;
        root.waitingForColors = false;
        root.finishTransitionIfReady();
    }

    function finishTransitionIfReady() {
        completionTimer.restart();
    }
    function completeTransition() {
        if (!root.applying || root.transitionApplyCount !== root.applyCount || root.waitingForColors || WallpaperTransition.changing) return;
        if (HyprlandSettings.applying) return;
        if (MaterialThemeLoader.pendingColors.length > 0) return;
        ThemeTransition.release(root.activeTransition);
        root.activeTransition = 0;
        root.applying = false;
        root.runPostRequest();
        root.hasBackup = true;
        if (root.activePresetId.length > 0) root.applied(root.activePresetId);
    }
    Connections {
        target: WallpaperTransition
        function onChangingChanged() { root.finishTransitionIfReady() }
        function onPreloadedChanged() {
            if (preloadWait.running && WallpaperTransition.isPreloaded(preloadWait.picture)) root.startPreloaded();
        }
    }
    Connections {
        target: HyprlandSettings
        function onApplyingChanged() { root.finishTransitionIfReady() }
    }
    // Qt and VS Code theming, once the wave is over: nothing on screen waits for it
    property string postRequest: ""
    function runPostRequest() {
        if (ThemeTransition.phase !== "idle" || root.postRequest.length === 0) return;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--post", root.postRequest]);
        root.postRequest = "";
    }
    Connections {
        target: ThemeTransition
        function onPhaseChanged() {
            root.runPostRequest();
        }
    }
    Connections {
        target: MaterialThemeLoader
        function onPendingColorsChanged() { root.finishTransitionIfReady() }
    }
    Timer {
        id: completionTimer
        interval: 80 // Includes the config file watcher and the first rendered layout.
        onTriggered: root.completeTransition()
    }

    function applyNow(preset, chosen, applyCount, preparedWallpaper = "", prepared = null) {
        root.waitingForColors = false;
        // Shell settings. Every key is written explicitly: keys missing from the file would keep their old value.
        let patch = {};
        for (const category of chosen) root.mergeInto(patch, root.filterConfig(preset[category].config, root.allowedPaths[category]));
        // What switchwall would publish, in the same single write
        if (prepared?.wallpaper) {
            root.setPath(patch, "background.wallpaperPath", prepared.wallpaper);
            if (prepared.thumbnail) root.setPath(patch, "background.thumbnailPath", prepared.thumbnail);
            if (!prepared.keepShader) root.setPath(patch, "background.shaderWallpaper.name", "");
        }
        if (prepared && prepared.accent !== null && prepared.accent !== undefined)
            root.setPath(patch, "appearance.palette.accentColor", prepared.accent);
        Config.applyPatch(patch);

        // Hyprland options and window motion, with a single reload
        let hyprland = {};
        for (const category of chosen) {
            for (const key of Object.keys(preset[category].hyprland ?? {})) {
                if (root.hyprlandAllowed(category, key)) hyprland[key] = preset[category].hyprland[key];
            }
        }
        if (chosen.includes("wallpaperAnimations") && preset.wallpaperAnimations.animationProfile) {
            const profile = preset.wallpaperAnimations.animationProfile;
            if (HyprlandSettings.animationProfiles.includes(profile)) hyprland["shell:animationProfile"] = profile;
        }
        if (Object.keys(hyprland).length > 0) {
            if (hyprland["shell:animationProfile"] === "material") {
                delete hyprland["shell:animationProfile"];
                HyprlandSettings.reset(["shell:animationProfile"]);
            }
            HyprlandSettings.setLive(hyprland); // In effect at once: windows settle under the picture
        }

        // Colors: one run of switchwall once the config is written, with the new wallpaper if any
        const modeArgs = chosen.includes("theme") ? root.themeOptions(preset) : [];
        const remote = chosen.includes("wallpaperAnimations") && root.isRemote(preset.wallpaperAnimations.wallpaper);
        const wallpaper = remote ? preparedWallpaper : chosen.includes("wallpaperAnimations") ? root.wallpaperFile(preset) : "";
        const daily = chosen.includes("wallpaperAnimations") && (preset.wallpaperAnimations.wallpaper ?? "").startsWith("daily:");
        const shader = chosen.includes("wallpaperAnimations") && (preset.wallpaperAnimations.wallpaper ?? "").startsWith("shader:");
        root.waitingForColors = shader || remote || daily || wallpaper.length > 0 || chosen.includes("theme");
        if (shader) {
            ShaderWallpaper.activate(preset.wallpaperAnimations.wallpaper.slice(7), modeArgs,
                () => root.colorsFinished(applyCount));
        } else if (prepared) {
            // Generated already: only put in place, the slow app theming after the wave
            commitJob.createObject(root, { "applyCount": applyCount, "request": prepared.request,
                "command": [Directories.wallpaperSwitchScriptPath, "--commit", prepared.request, "--no-publish", "--no-post"] });
        } else if (wallpaper.length > 0 || remote || chosen.includes("theme")) {
            themeTimer.args = [...(wallpaper.length > 0 ? ["--image", wallpaper] : ["--noswitch"]), ...modeArgs];
            themeTimer.applyCount = applyCount;
            themeTimer.restart();
        }
        if (daily) {
            Config.options.background.daily.source = preset.wallpaperAnimations.wallpaper.slice(6);
            Config.options.background.daily.enable = true;
            WallpaperOfTheDay.run();
        } else if (wallpaper.length > 0 || remote || shader) {
            Config.options.background.daily.enable = false; // A look with its own picture keeps it
        }
        root.finishTransitionIfReady();
    }

    Process {
        id: downloadProc
        property var request: null
        property string dest: ""
        property var queued: null

        function start(request, dest, command) {
            const next = { request: request, dest: dest, command: command };
            if (downloadProc.running) {
                downloadProc.queued = next;
                downloadProc.running = false;
            } else downloadProc.run(next);
        }
        function run(next) {
            downloadProc.request = next.request;
            downloadProc.dest = next.dest;
            downloadProc.command = next.command;
            downloadProc.running = true;
        }
        onExited: exitCode => {
            if (downloadProc.queued) {
                const next = downloadProc.queued;
                downloadProc.queued = null;
                downloadProc.run(next);
                return;
            }
            root.load();
            if (downloadProc.request?.applyCount !== root.applyCount) return;
            // Offline: still switch the layout and palette, retaining the existing wallpaper.
            root.prepareTheme(downloadProc.request, exitCode === 0 ? downloadProc.dest : "");
        }
    }

    Process {
        id: downloadedProc
        command: ["bash", "-c", 'cd -- "$1" 2>/dev/null && ls -1', "_", root.videoDir]
        stdout: StdioCollector {
            onStreamFinished: root.downloadedVideos = text.split("\n").filter(name => name.length > 0)
        }
    }

    Timer {
        id: themeTimer
        property var args: []
        property int applyCount: 0
        interval: Math.max(100, Config.readWriteDelay * 2 + 30)
        onTriggered: {
            if (themeTimer.applyCount !== root.applyCount) return;
            themeJob.createObject(root, {
                "applyCount": themeTimer.applyCount,
                "command": [Directories.wallpaperSwitchScriptPath, ...themeTimer.args]
            });
        }
    }
    Component {
        id: themeJob
        Process {
            id: job
            required property int applyCount
            running: true
            onExited: {
                root.colorsFinished(job.applyCount);
                job.destroy();
            }
        }
    }
    Component {
        id: prepareJob
        Process {
            id: preparing
            objectName: "themePrepareJob"
            required property var request
            property bool done: false
            running: true
            function finish(prepared) {
                if (preparing.done) return;
                preparing.done = true;
                root.preloadThenStart(preparing.request, prepared);
                preparing.destroy();
            }
            // The last line is the prepared request, as JSON
            stdout: StdioCollector {
                onStreamFinished: {
                    let prepared = null;
                    try {
                        prepared = JSON.parse(text.trim().split("\n").pop());
                    } catch (e) {}
                    preparing.finish(prepared?.request ? prepared : null);
                }
            }
            // Failed: applied the slow way, generating under the picture
            onExited: exitCode => { if (exitCode !== 0) preparing.finish(null); }
        }
    }
    Component {
        id: commitJob
        Process {
            id: committing
            objectName: "themeCommitJob"
            required property int applyCount
            required property string request
            running: true
            onExited: {
                root.postRequest = committing.request;
                root.colorsFinished(committing.applyCount);
                committing.destroy();
            }
        }
    }

    Connections {
        target: WallpaperOfTheDay
        function onRunningChanged() {
            if (!WallpaperOfTheDay.running && root.waitingForColors && Config.options.background.daily.enable)
                root.colorsFinished(root.transitionApplyCount);
        }
    }

    // Puts back what the last apply changed
    property int restoreRequestCount: 0
    function undo() {
        if (!root.hasBackup) return;
        root.restoreRequestCount = ++root.applyCount;
        themeTimer.stop();
        ThemeTransition.release(root.activeTransition);
        root.activeTransition = 0;
        root.interactivePreview = false;
        root.applying = true;
        restoreProc.running = true;
    }

    // Saves the current settings of the chosen categories as a new preset
    function saveCurrent(name, description, categories, extra = {}) {
        const slug = name.toLowerCase().replace(/[^a-z0-9а-яё]+/gi, "-").replace(/^-+|-+$/g, "") || `preset-${Date.now()}`;
        const dir = `${root.userDir}/${slug}`;
        const options = ObjectUtils.toPlainObject(Config.options);
        let preset = Object.assign({
            "name": name,
            "description": description,
            "icon": "bookmark",
            "version": 1,
        }, extra);
        for (const category of categories) {
            preset[category] = { "config": root.filterConfig(options, root.allowedPaths[category]) };
            if (root.allowedHyprland[category]) {
                let hyprland = {};
                for (const key of Object.keys(HyprlandSettings.values)) {
                    if (root.hyprlandAllowed(category, key)) hyprland[key] = HyprlandSettings.values[key];
                }
                if (category === "windows") hyprland["shell:windowMode"] = HyprlandSettings.windowMode; // Not a Hyprland option
                preset[category].hyprland = hyprland;
            }
        }
        if (preset.dockWidgets) {
            // Pinned apps are personal and don't travel with a look
            delete preset.dockWidgets.config.dock?.pinnedApps;
            delete preset.dockWidgets.config.dock?.pinnedAppCommands;
        }
        let wallpaperSource = "";
        if (preset.theme) {
            preset.theme.mode = Appearance.m3colors.darkmode ? "dark" : "light";
            preset.theme.accent = Config.options.appearance.palette.accentColor ?? "";
        }
        if (preset.wallpaperAnimations) {
            preset.wallpaperAnimations.animationProfile = HyprlandSettings.animationProfile;
            const shaderName = Config.options.background.shaderWallpaper?.name ?? "";
            if (shaderName.length > 0) {
                preset.wallpaperAnimations.wallpaper = `shader:${shaderName}`; // Drawn by the shell, nothing to copy
            } else {
                wallpaperSource = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath ?? "");
                if (wallpaperSource.length > 0) preset.wallpaperAnimations.wallpaper = `wallpaper.${wallpaperSource.split(".").pop()}`;
            }
        }
        // A video gets a picture of itself for the card
        saveProc.exec(["bash", "-c",
            'mkdir -p "$1" && printf "%s\\n" "$2" > "$1/preset.json" && { [ -z "$3" ] || cp -f -- "$3" "$1/$4"; } && { [ "$5" != 1 ] || ffmpeg -y -ss 1 -i "$1/$4" -vframes 1 -vf scale=640:-2 "$1/preview.jpg" >/dev/null 2>&1; true; }',
            "_", dir, JSON.stringify(preset, null, 4), wallpaperSource, preset.wallpaperAnimations?.wallpaper ?? "",
            FileUtils.isVideoPath(wallpaperSource) ? "1" : "0"]);
    }

    function remove(id) {
        const preset = root.find(id);
        if (!preset || preset.kind !== "user" || !preset.dir) return;
        saveProc.exec(["rm", "-rf", "--", preset.dir]);
    }

    function exportText(id) {
        let preset = Object.assign({}, root.find(id) ?? {});
        for (const key of ["id", "kind", "dir", "path"]) delete preset[key];
        return JSON.stringify(preset, null, 4);
    }

    // Reads a preset from text; returns { preset, commands } or { error }
    function parse(text) {
        let preset;
        try {
            preset = JSON.parse(text);
        } catch (e) {
            return { "error": Translation.tr("Not valid JSON") };
        }
        if (!preset || typeof preset !== "object" || typeof preset.name !== "string" || root.categoriesOf(preset).length === 0)
            return { "error": Translation.tr("This is not a preset") };
        return { "preset": preset, "commands": root.commandsIn(preset) };
    }

    function importPreset(preset) {
        const slug = (preset.name ?? "preset").toLowerCase().replace(/[^a-z0-9а-яё]+/gi, "-").replace(/^-+|-+$/g, "") || `preset-${Date.now()}`;
        let copy = Object.assign({}, preset);
        const wallpaper = copy.wallpaperAnimations?.wallpaper ?? "";
        if (wallpaper && !wallpaper.startsWith("daily:") && !root.isRemote(wallpaper))
            delete copy.wallpaperAnimations.wallpaper; // A local image isn't part of the text, a link is
        saveProc.exec(["bash", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" > "$1/preset.json"',
            "_", `${root.userDir}/${slug}`, JSON.stringify(copy, null, 4)]);
    }

    Process {
        id: listProc
        command: ["bash", "-c", `
            shopt -s nullglob
            for f in "$1"/*.json; do
                jq -c --arg path "$f" '. + {path: $path, kind: "builtin", id: ($path | split("/") | last | rtrimstr(".json"))}' "$f" 2>/dev/null
            done
            for f in "$2"/*/preset.json; do
                d=\${f%/preset.json}
                jq -c --arg path "$f" --arg dir "$d" '. + {path: $path, dir: $dir, kind: "user", id: ("user:" + ($dir | split("/") | last))}' "$f" 2>/dev/null
            done`, "_", root.builtinDir, root.userDir]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                for (const line of text.split("\n")) {
                    if (line.trim().length === 0) continue;
                    try {
                        list.push(JSON.parse(line));
                    } catch (e) {
                        console.warn("[Presets] Couldn't read a preset:", e);
                    }
                }
                // Your default look first, then built-in ones in their own order, then yours by name
                list.sort((a, b) => (!!b.isDefault - !!a.isDefault)
                    || (a.kind === b.kind ? 0 : a.kind === "builtin" ? -1 : 1)
                    || (a.order ?? 100) - (b.order ?? 100) || (a.name ?? "").localeCompare(b.name ?? ""));
                root.presets = list;
            }
        }
    }

    Process {
        id: saveProc
        onExited: root.load()
    }

    // Copies of what applying may change: config, Hyprland overrides, wallpaper and light/dark
    Process {
        id: backupProc
        command: ["bash", "-c", 'mkdir -p "$1" && cp -f -- "$2" "$1/config.json" && { cp -f -- "$3" "$1/shell_settings.json" 2>/dev/null || echo "{}" > "$1/shell_settings.json"; } && printf "%s\\n%s\\n" "$4" "$5" > "$1/wallpaper.txt"',
            "_", root.backupDir, Directories.shellConfigPath, HyprlandSettings.jsonPath,
            FileUtils.trimFileProtocol(Config.options.background.wallpaperPath ?? ""), Appearance.m3colors.darkmode ? "dark" : "light"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[Presets] Backup failed; not applying");
                root.applying = false;
                root.pending = null;
                return;
            }
            root.finishApply();
        }
    }

    Process {
        id: backupCheck
        command: ["test", "-f", `${root.backupDir}/config.json`]
        onExited: exitCode => root.hasBackup = exitCode === 0
    }

    Process {
        id: restoreProc
        command: ["bash", "-c", 'cat "$1/config.json"; printf "\\n\\u001e\\n"; cat "$1/shell_settings.json"; printf "\\n\\u001e\\n"; cat "$1/wallpaper.txt"', "_", root.backupDir]
        onExited: exitCode => {
            if (exitCode !== 0 && root.restoreRequestCount === root.applyCount) root.applying = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.restoreRequestCount !== root.applyCount) return;
                const parts = text.split("\n\u001e\n");
                if (parts.length < 3) {
                    root.applying = false;
                    return;
                }
                let config = {};
                let overrides = {};
                try {
                    config = JSON.parse(parts[0]);
                    overrides = JSON.parse(parts[1]);
                } catch (e) {
                    console.warn("[Presets] Couldn't restore the backup:", e);
                    root.applying = false;
                    return;
                }
                const applyCount = root.restoreRequestCount;
                ThemeTransition.run(token => {
                    if (applyCount !== root.applyCount) {
                        ThemeTransition.release(token);
                        return;
                    }
                    root.activeTransition = token;
                    root.transitionApplyCount = applyCount;
                    root.activePresetId = "";
                    root.waitingForColors = true;
                    let patch = {};
                    for (const category of root.categoryIds) root.mergeInto(patch, root.filterConfig(config, root.allowedPaths[category]));
                    Config.applyPatch(patch);
                    HyprlandSettings.replaceOverrides(overrides);
                    const [wallpaper, mode] = parts[2].trim().split("\n");
                    const accent = config.appearance?.palette?.accentColor ?? "";
                    // The picture of an animated wallpaper is its still frame; without --keep-shader switchwall would stop the animation
                    const shader = (config.background?.shaderWallpaper?.name ?? "").length > 0;
                    themeTimer.args = [...(wallpaper ? ["--image", wallpaper] : ["--noswitch"]), ...(shader && wallpaper ? ["--keep-shader"] : []),
                        ...(mode ? ["--mode", mode] : []), ...root.accentArgs({ "theme": { "accent": accent } })];
                    themeTimer.applyCount = applyCount;
                    themeTimer.restart();
                }, true);
            }
        }
    }

    IpcHandler {
        target: "presets"

        function list(): string {
            return root.presets.map(preset => `${preset.id}\t${preset.name}`).join("\n");
        }
        // categories: comma-separated, or empty for all of them
        function apply(id: string, categories: string): void {
            root.apply(id, categories.split(",").map(category => category.trim()).filter(category => category.length > 0));
        }
        // Like apply, with the theme of another preset (or "") and light or dark forced (or "").
        // Returns the apply's number, for busy()
        function applyWith(id: string, categories: string, themeFrom: string, mode: string): int {
            root.apply(id, categories.split(",").map(category => category.trim()).filter(category => category.length > 0), themeFrom, mode);
            return root.applyCount;
        }
        // Setup keeps its own UI animated while the live desktop preview changes beneath it.
        function applyForOnboarding(id: string, categories: string, themeFrom: string, mode: string): int {
            root.apply(id, categories.split(",").map(category => category.trim()).filter(category => category.length > 0), themeFrom, mode, true);
            return root.applyCount;
        }
        // Whether apply number `count` is still on its way: downloading, generating colors or in its wave
        function busy(count: int): bool {
            return root.applying && root.applyCount === count;
        }
        function undo(): void {
            root.undo();
        }
        // Saves everything as it is now as your default look
        function saveDefault(name: string): void {
            root.saveCurrent(name.length > 0 ? name : Translation.tr("My look"), Translation.tr("Your own wallpaper, bar, theme, dock and motion"),
                root.categoryIds, { "icon": "home", "isDefault": true });
        }
        function reload(): void {
            root.load();
        }
    }

    Component.onCompleted: root.load()
}
