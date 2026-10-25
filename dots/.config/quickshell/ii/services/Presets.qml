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
 * Each category may hold `config` (a partial config.json, limited to the paths below) and
 * `hyprland` (Hyprland options for HyprlandSettings), plus `mode`/`scheme` (theme),
 * `wallpaper` and `animationProfile` (wallpaperAnimations). A video from the web may come with
 * `loop: { start, end, crossfade }` (seconds): that part of it is made to repeat without a jump.
 *
 * Built-in presets are defaults/presets/*.json; your own are saved under
 * ~/.config/illogical-impulse/presets/<slug>/preset.json (with a copy of the wallpaper).
 * Applying runs in the shell (IPC "presets"), after backing up what it changes for undo.
 */
Singleton {
    id: root

    readonly property list<string> categoryIds: ["bar", "theme", "dockWidgets", "wallpaperAnimations", "lock"]
    readonly property var categories: [
        { "id": "bar", "name": Translation.tr("Bar"), "icon": "toast" },
        { "id": "theme", "name": Translation.tr("Theme and colors"), "icon": "palette" },
        { "id": "dockWidgets", "name": Translation.tr("Dock and desktop widgets"), "icon": "widgets" },
        { "id": "wallpaperAnimations", "name": Translation.tr("Wallpaper and motion"), "icon": "animation" },
        { "id": "lock", "name": Translation.tr("Lock screen"), "icon": "lock" },
    ]
    // Config paths each category may change; anything else in a preset is ignored
    readonly property var allowedPaths: ({
        "bar": ["bar"],
        "theme": ["appearance.palette", "appearance.transparency", "appearance.fonts", "appearance.extraBackgroundTint", "appearance.fakeScreenRounding"],
        "dockWidgets": ["dock", "background.widgets"],
        "wallpaperAnimations": ["appearance.animationSpeed", "background.liveWallpaper.pauseWhen", "background.shaderWallpaper"],
        "lock": ["lock.layout", "lock.animations", "lock.animatedWallpaper", "lock.dim", "lock.blur", "lock.showLockedText", "background.widgets.clock.styleLocked"],
    })
    // Hyprland options each category may change, by prefix (RegExps don't survive a `var` property)
    readonly property var allowedHyprland: ({
        "theme": ["decoration:", "general:border_size"],
        "wallpaperAnimations": ["general:gaps_", "animations:enabled", "misc:animate_"],
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

    // Applies the chosen categories of a preset (all it has when `categories` is empty)
    function apply(id, categories = []) {
        const preset = root.find(id);
        if (!preset) {
            console.warn("[Presets] Unknown preset", id);
            return;
        }
        const chosen = (categories.length > 0 ? categories : root.categoriesOf(preset)).filter(category => preset[category]);
        if (chosen.length === 0) return;
        root.applying = true;
        root.pending = { "preset": preset, "categories": chosen };
        backupProc.running = true; // Continues in finishApply() once the backup is written
    }

    property var pending: null

    // Counts applies, so a download that finishes after another look was applied doesn't switch back to its own
    property int applyCount: 0

    function finishApply() {
        const preset = root.pending.preset;
        const chosen = root.pending.categories;
        root.pending = null;
        root.applyCount++;

        // Shell settings. Every key is written explicitly: keys missing from the file would keep their old value.
        let patch = {};
        for (const category of chosen) root.mergeInto(patch, root.filterConfig(preset[category].config, root.allowedPaths[category]));
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
            HyprlandSettings.setMany(hyprland);
        }

        // Colors: one run of switchwall once the config is written, with the new wallpaper if any
        const modeArgs = chosen.includes("theme") ? [...(["dark", "light"].includes(preset.theme.mode) ? ["--mode", preset.theme.mode] : []),
            ...root.accentArgs(preset)] : [];
        const remote = chosen.includes("wallpaperAnimations") && root.isRemote(preset.wallpaperAnimations.wallpaper);
        const wallpaper = chosen.includes("wallpaperAnimations") ? root.wallpaperFile(preset) : "";
        const daily = chosen.includes("wallpaperAnimations") && (preset.wallpaperAnimations.wallpaper ?? "").startsWith("daily:");
        const shader = chosen.includes("wallpaperAnimations") && (preset.wallpaperAnimations.wallpaper ?? "").startsWith("shader:");
        if (shader) {
            // Drawn by the shell; its still frame becomes the wallpaper picture for colors and previews
            ShaderWallpaper.activate(preset.wallpaperAnimations.wallpaper.slice(7), modeArgs);
        } else if (remote) {
            // Downloaded once into ~/Pictures/Wallpapers/Presets (videos: ~/Videos/…), then colors are made from it
            downloadProc.start(root.applyCount, root.remoteWallpaperPath(preset), modeArgs,
                [Quickshell.shellPath("scripts/colors/random/download_wallpaper.sh"), preset.wallpaperAnimations.wallpaper,
                root.remoteWallpaperPath(preset), "--meta", JSON.stringify(preset.credits ?? {}), "--title", Translation.tr(preset.name),
                ...root.loopArgs(preset)]);
        } else if (wallpaper.length > 0 || chosen.includes("theme")) {
            themeTimer.args = [...(wallpaper.length > 0 ? ["--image", wallpaper] : ["--noswitch"]), ...modeArgs];
            themeTimer.restart();
        }
        if (daily) {
            Config.options.background.daily.source = preset.wallpaperAnimations.wallpaper.slice(6);
            Config.options.background.daily.enable = true;
            WallpaperOfTheDay.run();
        } else if (wallpaper.length > 0 || remote || shader) {
            Config.options.background.daily.enable = false; // A look with its own picture keeps it
        }
        root.applying = false;
        root.hasBackup = true;
        root.applied(preset.id);
    }

    Process {
        id: downloadProc
        property int applyCount: 0
        property string dest: ""
        property var modeArgs: []
        property var queued: null

        // A download still running for an earlier look is stopped; this one starts once it has exited
        function start(applyCount, dest, modeArgs, command) {
            const next = { "applyCount": applyCount, "dest": dest, "modeArgs": modeArgs, "command": command };
            if (downloadProc.running) {
                downloadProc.queued = next;
                downloadProc.running = false;
                return;
            }
            downloadProc.run(next);
        }
        function run(next) {
            downloadProc.applyCount = next.applyCount;
            downloadProc.dest = next.dest;
            downloadProc.modeArgs = next.modeArgs;
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
            root.load(); // The card can now play the downloaded video
            if (downloadProc.applyCount !== root.applyCount) return; // Another look was applied meanwhile
            // Without the picture (offline, blocked) the rest of the theme still applies
            themeTimer.args = [...(exitCode === 0 ? ["--image", downloadProc.dest] : ["--noswitch"]), ...downloadProc.modeArgs];
            themeTimer.restart();
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
        interval: 400 // After Config has written the palette type that switchwall reads
        onTriggered: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, ...args])
    }

    // Puts back what the last apply changed
    function undo() {
        if (!root.hasBackup) return;
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
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\n\u001e\n");
                if (parts.length < 3) return;
                let config = {};
                try {
                    config = JSON.parse(parts[0]);
                    let patch = {};
                    for (const category of root.categoryIds) root.mergeInto(patch, root.filterConfig(config, root.allowedPaths[category]));
                    Config.applyPatch(patch);
                    HyprlandSettings.replaceOverrides(JSON.parse(parts[1]));
                } catch (e) {
                    console.warn("[Presets] Couldn't restore the backup:", e);
                    return;
                }
                const [wallpaper, mode] = parts[2].trim().split("\n");
                const accent = config.appearance?.palette?.accentColor ?? "";
                // The picture of an animated wallpaper is its still frame; without --keep-shader switchwall would stop the animation
                const shader = (config.background?.shaderWallpaper?.name ?? "").length > 0;
                themeTimer.args = [...(wallpaper ? ["--image", wallpaper] : ["--noswitch"]), ...(shader && wallpaper ? ["--keep-shader"] : []),
                    ...(mode ? ["--mode", mode] : []), ...root.accentArgs({ "theme": { "accent": accent } })];
                themeTimer.restart();
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
