pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The setup assistant's steps and choices. Every move is saved at once (~/.local/state/velora/onboarding.json),
 * so a crash or a logout picks up where it stopped. Before the first change, the files it can touch are
 * copied aside, and "Undo all changes" puts them back. QS_ONBOARDING_DRYRUN=1 logs what would be done
 * instead of doing it.
 *
 * Changes go through the running shell (`qs -c ii ipc call …`), so they arrive with its transitions.
 */
QtObject {
    id: root

    readonly property bool dryRun: Quickshell.env("QS_ONBOARDING_DRYRUN") === "1"
    readonly property string stateDir: `${FileUtils.trimFileProtocol(Directories.home)}/.local/state/velora`
    // A dry run keeps its own progress, so trying it out leaves the real setup untouched
    readonly property string statePath: `${root.stateDir}/onboarding${root.dryRun ? "-dryrun" : ""}.json`
    readonly property string backupDir: `${root.stateDir}/onboarding-backup`
    readonly property string configDir: FileUtils.trimFileProtocol(Directories.config)

    // Shown in this order; the network step only without a connection
    readonly property var allSteps: [
        { "id": "hello", "title": "" },
        { "id": "language", "title": Translation.tr("Language") },
        { "id": "display", "title": Translation.tr("Screen") },
        { "id": "network", "title": Translation.tr("Network") },
        { "id": "layout", "title": Translation.tr("Desktop") },
        { "id": "appearance", "title": Translation.tr("Look") },
        { "id": "extras", "title": Translation.tr("Extras") },
        { "id": "install", "title": Translation.tr("Installing") },
        { "id": "done", "title": Translation.tr("Ready") },
    ]
    property bool online: true
    // The install step only with something picked (known as soon as a resumed setup is read, so the
    // step it was on stays the same), or once it ran
    readonly property bool hasExtras: (root.choices.components ?? []).length + (root.choices.apps ?? []).length > 0
        || root.installState !== "idle"
    readonly property var steps: root.allSteps.filter(step => (step.id !== "network" || !root.online) && (step.id !== "install" || root.hasExtras))
    property int index: 0
    property int direction: 1 // 1 forward, -1 back: pages slide accordingly
    readonly property string step: root.steps[root.index]?.id ?? "hello"
    readonly property bool first: root.index === 0
    readonly property bool last: root.step === "done"
    property bool loaded: false
    property bool initializingTheme: false
    property bool backupReady: root.dryRun
    readonly property bool ready: root.loaded && !root.initializingTheme
    // Reopening setup keeps the current palette until a wallpaper is explicitly selected.
    property bool preservePalette: false
    // Installing: leaving now would stop it
    readonly property bool busy: ["checking", "running"].includes(root.installState)
    readonly property bool passwordOpen: ["password", "checking", "wrongPassword"].includes(root.installState)
    readonly property bool navigationLocked: root.busy || root.passwordOpen

    property var choices: ({
        "language": Config.options.language.ui,
        "look": "velora",
        "windows": "tiling",
        "theme": "", // Light or dark once picked; until then the wallpaper's own
        "wallpaper": "autumn",
        "components": [],
        "apps": [],
    })
    readonly property string shownTheme: root.choices.theme || (Appearance.m3colors.darkmode ? "dark" : "light")
    // What's on the desktop already, so a step applies its default once, when it's first shown
    property string appliedLook: ""
    property string appliedWallpaper: ""
    property bool displayChecked: false

    // The picture on the desktop now (a video's still frame)
    readonly property string currentPicture: FileUtils.isVideoPath(Config.options.background.wallpaperPath)
        ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath

    signal finished(bool tour)
    property bool closing: false // On the way out: the other screens let go too
    onFinished: root.closing = true

    function choose(key, value) {
        let next = Object.assign({}, root.choices);
        next[key] = value;
        root.choices = next;
        root.save();
    }

    function go(stepId) {
        const target = root.steps.findIndex(step => step.id === stepId);
        if (target < 0 || target === root.index || root.navigationLocked) return;
        if (target > root.index) root.acceptStep();
        root.direction = target > root.index ? 1 : -1;
        root.index = target;
        root.save();
    }
    function next() {
        if (root.index >= root.steps.length - 1 || root.navigationLocked) return;
        root.acceptStep();
        root.direction = 1;
        root.index++;
        root.save();
    }

    function acceptStep() {
        // Moving forward confirms the display preview just as the page's Keep button does.
        if (root.step === "display" && !root.dryRun && HyprlandMonitors.confirming) HyprlandMonitors.keep();
    }
    function back() {
        if (root.index <= 0 || root.navigationLocked) return;
        root.direction = -1;
        root.index--;
        root.save();
    }

    // ~/.local/state/velora/onboarding.json
    function save(extra = {}) {
        if (!root.loaded) return;
        const state = Object.assign({ "version": 1, "completed": false, "skipped": false, "step": root.step, "choices": root.choices,
            "startedAt": root.startedAt, "preservePalette": root.preservePalette, "displayChecked": root.displayChecked }, extra);
        stateFile.setText(JSON.stringify(state, null, 2) + "\n");
    }
    property string startedAt: new Date().toISOString()

    // Runs a command, or only logs it in a dry run
    function run(command) {
        if (root.dryRun) {
            console.info("[Onboarding] Would run:", JSON.stringify(command));
            return;
        }
        Quickshell.execDetached(command);
    }
    function shell(target, method, ...args) {
        root.run(["qs", "-c", "ii", "ipc", "call", target, method, ...args.map(String)]);
    }
    function setConfig(path, value) {
        if (root.dryRun) {
            console.info("[Onboarding] Would set", path, "=", JSON.stringify(value));
            return;
        }
        Config.setNestedValue(path, value);
    }

    // The three looks are presets for the bar, the dock and motion. Their colors aren't their own: every
    // look takes the theme of the chosen wallpaper (Autumn tree at first), so they differ only in layout
    readonly property var lookPresets: ({ "velora": "synthwave", "horizon": "pastel", "vertical": "autumn" })
    function applyLook(look) {
        root.choose("look", look);
        root.appliedLook = look;
        root.applyPreset("look", root.lookPresets[look] ?? "synthwave",
            root.preservePalette ? "bar,dockWidgets,motion" : "bar,theme,dockWidgets,motion", root.choices.wallpaper, root.choices.theme);
    }
    function applyWindows(mode) {
        root.choose("windows", mode);
        root.shell("windowMode", "set", mode);
    }
    // Light or dark: the wallpaper's theme again, in that mode (the picture is downloaded already)
    function applyTheme(mode) {
        root.choose("theme", mode);
        if (root.preservePalette) {
            root.applyPreset("theme", root.lookPresets[root.choices.look], "theme", "current", mode);
        } else {
            root.appliedWallpaper = root.choices.wallpaper;
            root.applyPreset("theme", root.choices.wallpaper, "wallpaperAnimations,theme", "", mode);
        }
    }
    function applyWallpaper(presetId) {
        root.preservePalette = false;
        root.choose("wallpaper", presetId);
        root.appliedWallpaper = presetId;
        root.applyPreset("wallpaper", presetId, "wallpaperAnimations,theme", "", root.choices.theme);
    }

    // What the shell is applying now ("look", "wallpaper" or "theme") and which preset, until it says it's
    // done: the picture downloaded, the colors made and the desktop updated. Asked every moment, given up after
    // two minutes. An older shell falls back to applyWith until it is reloaded.
    property string applying: ""
    property string applyingId: ""
    property int applyNumber: -1 // The shell's number for it
    property int applyRequest: 0 // Ours, so only the latest answer counts
    function applyPreset(kind, id, categories, themeFrom = "", mode = "") {
        if (root.dryRun) {
            console.info("[Onboarding] Would apply", id, categories, "with the theme of", themeFrom || id, mode);
            return;
        }
        root.applying = kind;
        root.applyingId = id;
        root.applyNumber = -1;
        root.busyPoll.stop();
        root.applyTimeout.restart();
        root.applyJob.createObject(root, { "request": ++root.applyRequest,
            "fallback": ["qs", "-c", "ii", "ipc", "call", "presets", "applyWith", id, categories, themeFrom, mode],
            "command": ["qs", "-c", "ii", "ipc", "call", "presets", "applyForOnboarding", id, categories, themeFrom, mode] });
    }
    function applyDone() {
        root.applying = "";
        root.applyingId = "";
        root.applyNumber = -1;
        root.busyPoll.stop();
        root.applyTimeout.stop();
        if (root.initializingTheme) {
            MaterialThemeLoader.reapplyTheme(true);
            root.initializingTheme = false;
        }
    }
    property Component applyJob: Component {
        Process {
            id: job
            required property int request
            required property var fallback
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    const number = parseInt(text.trim());
                    if (job.request === root.applyRequest) {
                        if (isNaN(number)) {
                            Quickshell.execDetached(job.fallback);
                            root.applyDone();
                        } else {
                            root.applyNumber = number;
                            root.busyPoll.restart();
                        }
                    }
                    job.destroy();
                }
            }
        }
    }
    property Timer busyPoll: Timer {
        interval: 400
        onTriggered: {
            root.busyCheck.number = root.applyNumber;
            root.busyCheck.running = true;
        }
    }
    property Process busyCheck: Process {
        property int number: -1
        command: ["qs", "-c", "ii", "ipc", "call", "presets", "busy", String(root.busyCheck.number)]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.busyCheck.number !== root.applyNumber) return;
                if (text.trim() === "true") root.busyPoll.restart();
                else root.applyDone();
            }
        }
    }
    property Timer applyTimeout: Timer {
        interval: 120000
        onTriggered: root.applyDone()
    }
    function applyLanguage(code) {
        root.choose("language", code);
        root.setConfig("language.ui", code);
    }

    // Every screen shows its name for a moment (Screens step)
    property bool identifying: false
    function identify() {
        root.identifying = true;
        root.identifyTimer.restart();
    }
    property Timer identifyTimer: Timer {
        interval: 2600
        onTriggered: root.identifying = false
    }

    // Leaves with recommended choices for what wasn't asked yet, and a reminder in Settings
    function skip() {
        if (root.navigationLocked) return;
        root.save({ "skipped": true });
        root.finished(false);
    }

    function finish(tour) {
        if (root.navigationLocked) return;
        root.shell("windowMode", "set", root.choices.windows === "floating" ? "floating" : "tiling");
        root.save({ "completed": true, "completedAt": new Date().toISOString() });
        root.finished(tour);
    }

    // Extras: Velora's optional parts (dependencies/arch.toml, through `velora components --json`) and a
    // few popular apps (defaults/onboarding/apps.json), with what of them is missing
    property var components: []
    property bool componentsLoaded: false
    property var apps: []
    property var missingApps: []
    property bool appsChecked: false
    readonly property bool extrasReady: root.componentsLoaded && root.appsChecked
    function loadExtras() {
        root.componentsProc.running = true;
        if (root.apps.length > 0) root.appsProc.running = true;
    }
    property Process componentsProc: Process {
        command: [FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/maintenance/velora.sh")), "components", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.components = JSON.parse(text).filter(item => !item.required);
                } catch (error) {
                    console.warn("[Onboarding] Couldn't list components:", error);
                }
                root.componentsLoaded = true;
            }
        }
    }
    property FileView appsFile: FileView {
        path: Quickshell.shellPath("defaults/onboarding/apps.json")
        onLoaded: {
            root.apps = JSON.parse(root.appsFile.text());
            root.appsProc.command = ["pacman", "-T", "--", ...root.apps.map(app => app.package)];
            root.appsProc.running = true;
        }
    }
    // pacman -T prints what isn't installed
    property Process appsProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.missingApps = text.split("\n").map(line => line.trim()).filter(line => line.length > 0);
                root.appsChecked = true;
            }
        }
    }

    // Names, descriptions and icons of the components offered
    readonly property var componentInfo: ({
        "applications": [Translation.tr("Everyday apps"), Translation.tr("A file manager, terminals and command-line helpers"), "folder_open"],
        "toolbox": [Translation.tr("Tools"), Translation.tr("Convert files, download videos, QR codes, text from images"), "construction"],
        "appearance": [Translation.tr("Themes and fonts"), Translation.tr("Other apps in Velora's colors and fonts"), "palette"],
        "live-wallpapers": [Translation.tr("Live wallpapers"), Translation.tr("Videos as wallpapers"), "movie"],
    })
    function itemName(item) {
        return item.kind === "component" ? (root.componentInfo[item.id]?.[0] ?? item.id) : (root.apps.find(app => app.package === item.id)?.name ?? item.id);
    }

    // What's picked and still missing, each with its packages from the repositories and from the AUR
    // (a `velora` without that split gets AUR parts through the AUR helper, which installs both)
    readonly property var installItems: [
        ...root.components.filter(item => (root.choices.components ?? []).includes(item.id) && !item.installed).map(item => ({
            "id": item.id, "kind": "component",
            "repo": item.missingRepo ?? (item.aur ? [] : (item.missingNames ?? [])),
            "aur": item.missingAur ?? (item.aur ? (item.missingNames ?? []) : []),
        })),
        ...root.apps.filter(app => (root.choices.apps ?? []).includes(app.package) && root.missingApps.includes(app.package))
            .map(app => ({ "id": app.package, "kind": "app", "repo": [app.package], "aur": [] })),
    ]

    // Installing them, right here (scripts/maintenance/install_extras.py): the password is asked once,
    // checked, and handed to sudo, so no terminal waits for it
    property string installState: "idle" // idle | password (asked) | checking | wrongPassword | running | done | failed
    property string installPhase: "" // password | repo | aur | record
    property string installLine: "" // The tools' latest line
    property var installLog: []
    property int installExit: 0
    // Exit codes of install_extras.py, said in words
    readonly property string installError: root.installExit === 4 ? Translation.tr("No AUR helper (yay or paru) is installed. Run 'velora deps' in a terminal.")
        : root.installExit === 5 ? Translation.tr("This account isn't allowed to install system packages.")
        : Translation.tr("Something went wrong while installing. The output below says what.")
    property var installing: [] // installItems as they were when it started
    function askPassword() {
        if (root.busy || !root.extrasReady || root.installItems.length === 0) return;
        root.installState = "password";
    }
    // The password dialog closed without a password
    function cancelPassword() {
        if (["password", "wrongPassword"].includes(root.installState)) root.installState = "idle";
    }
    function install(password) {
        if (!["password", "wrongPassword"].includes(root.installState) || password.length === 0) return;
        root.installing = root.installItems;
        const unique = list => [...new Set(list)];
        const repo = unique(root.installing.reduce((packages, item) => packages.concat(item.repo), []));
        const aur = unique(root.installing.reduce((packages, item) => packages.concat(item.aur), []));
        const components = root.installing.filter(item => item.kind === "component").map(item => item.id);
        root.installLog = [];
        root.installLine = "";
        root.installPhase = "password";
        root.installState = "checking";
        root.installer.command = ["python3", FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/maintenance/install_extras.py")),
            ...(root.dryRun ? ["--dry-run"] : []), "--repo", repo.join(","), "--aur", aur.join(","), "--components", components.join(",")];
        root.pendingPassword = password;
        root.installer.stdinEnabled = true;
        root.installer.running = true;
    }
    property string pendingPassword: ""
    function appendInstallLine(line) {
        root.installLine = line;
        root.installLog = [...root.installLog.slice(-199), line];
    }
    property Process installer: Process {
        stdinEnabled: true
        onStarted: {
            root.installer.write(root.pendingPassword + "\n");
            root.pendingPassword = "";
            root.installer.stdinEnabled = false;
        }
        onRunningChanged: if (!running) Qt.callLater(() => {
            // A failed exec does not emit exited. Do not leave the dialog checking forever.
            if (root.busy && !root.installer.running) {
                root.pendingPassword = "";
                root.installExit = 1;
                root.installState = "failed";
            }
        })
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("::phase ")) {
                    root.installPhase = line.slice(8).trim();
                    if (root.installPhase !== "password") root.installState = "running";
                    return;
                }
                root.appendInstallLine(line);
            }
        }
        stderr: SplitParser {
            onRead: line => root.appendInstallLine(line)
        }
        onExited: (exitCode, exitStatus) => {
            root.pendingPassword = "";
            if (exitStatus !== 0) exitCode = 1;
            root.installExit = exitCode;
            root.installState = exitCode === 0 ? "done" : exitCode === 3 ? "wrongPassword" : "failed";
            // What's there now: badges on the Extras step, and nothing left to install
            if (exitCode !== 3) root.loadExtras();
        }
    }

    // Everything back as it was before the assistant started
    function undoAll() {
        root.run(["bash", "-c", 'cp -f -- "$1/config.json" "$2/illogical-impulse/config.json"; '
            + 'cp -f -- "$1/shell_settings.json" "$2/hypr/custom/shell_settings.json" 2>/dev/null; '
            + 'cp -f -- "$1/monitors.json" "$2/hypr/custom/monitors.json" 2>/dev/null; '
            + 'qs -c ii ipc call presets reload; hyprctl reload', "_", root.backupDir, root.configDir]);
    }

    property Process backup: Process {
        // Only once: a resumed assistant keeps the copy from before its first run
        command: ["bash", "-c", '[ -d "$1" ] && exit 0; mkdir -p "$1" && cp -f -- "$2/illogical-impulse/config.json" "$1/" '
            + '&& { cp -f -- "$2/hypr/custom/shell_settings.json" "$1/" 2>/dev/null; cp -f -- "$2/hypr/custom/monitors.json" "$1/" 2>/dev/null; true; }',
            "_", root.backupDir, root.configDir]
        onRunningChanged: if (!running) {
            root.backupReady = true;
            root.prepareInitialTheme();
        }
    }

    function prepareInitialTheme() {
        if (root.initializingTheme && root.backupReady && root.applying === "") root.applyPreset("theme", "autumn", "theme");
    }

    property FileView stateFile: FileView {
        path: root.statePath
        printErrors: false
        onLoaded: {
            try {
                const state = JSON.parse(root.stateFile.text());
                if (!state.completed && !state.skipped && state.choices) {
                    root.preservePalette = state.preservePalette ?? false;
                    root.displayChecked = state.displayChecked === true;
                    root.choices = Object.assign({}, root.choices, state.choices);
                    const resumed = root.steps.findIndex(step => step.id === state.step);
                    if (resumed > 0) root.index = resumed;
                } else if (state.completed || state.skipped) {
                    root.preservePalette = true;
                    root.appliedLook = root.choices.look;
                }
            } catch (error) {}
            root.loaded = true;
        }
        onLoadFailed: {
            // Generate Autumn's palette before the first frame, without downloading a wallpaper.
            root.initializingTheme = !root.dryRun;
            root.prepareInitialTheme();
            root.loaded = true;
        }
    }

    // Offline at the start: the network step is shown
    property Process connectivity: Process {
        running: true
        command: ["nmcli", "-t", "networking", "connectivity"]
        stdout: StdioCollector {
            onStreamFinished: root.online = !["none", "limited", "portal"].includes(text.trim()) || text.trim() === ""
        }
    }

    Component.onCompleted: {
        if (!root.dryRun) root.backup.running = true;
        root.componentsProc.running = true;
    }
}
