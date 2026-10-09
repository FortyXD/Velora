pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * Pinned and running apps for the dock and the taskbar, plus launching them.
 * Window classes often differ from desktop entry ids, so lookups go through
 * several fallbacks before giving up.
 */
Singleton {
    id: root

    // Reverse-DNS parts that never name an app on their own
    readonly property list<string> genericIdParts: ["com", "org", "net", "io", "app", "dev", "desktop", "github", "gitlab", "www"]
    readonly property int launchTimeout: 10000

    // appId -> { since, windows }: apps that were launched but have not opened a new window yet
    property var launchingApps: ({})

    property int entriesRevision: 0
    property var entryCache: ({})

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.entryCache = {};
            root.entriesRevision++;
        }
    }

    function isPinned(appId) {
        const key = appId.toLowerCase();
        return (Config.options.dock.pinnedApps ?? []).some(id => id.toLowerCase() === key);
    }

    function togglePin(appId) {
        const key = appId.toLowerCase();
        if (root.isPinned(appId)) {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.filter(id => id.toLowerCase() !== key);
            const commands = Object.assign({}, Config.options.dock.pinnedAppCommands);
            if (commands[key]) {
                delete commands[key];
                Config.options.dock.pinnedAppCommands = commands;
            }
        } else {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.concat([appId]);
            root.rememberLaunchCommand(appId);
        }
    }

    property var apps: {
        root.entriesRevision; // Regroup windows once desktop entries are loaded
        const pinnedApps = Config.options?.dock.pinnedApps ?? [];
        const ignoredRegexes = (Config.options?.dock.ignoredAppRegexes ?? []).map(pattern => new RegExp(pattern, "i"));

        const pinned = new Map();
        const pinnedByEntry = new Map();
        for (const pinnedId of pinnedApps) {
            const key = pinnedId.toLowerCase();
            if (pinned.has(key)) continue;
            pinned.set(key, { appId: key, pinned: true, toplevels: [] });
            const entry = root.desktopEntryFor(pinnedId);
            if (entry && !pinnedByEntry.has(entry.id)) pinnedByEntry.set(entry.id, key);
        }

        const running = new Map();
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (ignoredRegexes.some(re => re.test(toplevel.appId))) continue;
            let key = toplevel.appId.toLowerCase();
            if (!pinned.has(key)) {
                // A window whose class differs from the pinned desktop id still belongs to the pinned icon
                const entry = root.desktopEntryFor(toplevel.appId);
                if (entry && pinnedByEntry.has(entry.id)) key = pinnedByEntry.get(entry.id);
            }
            const app = pinned.get(key) ?? running.get(key);
            if (app) app.toplevels.push(toplevel);
            else running.set(key, { appId: key, pinned: false, toplevels: [toplevel] });
        }

        // Plain objects let ScriptModel match entries by appId and keep their delegates
        const values = [...pinned.values()];
        if (values.length > 0 && running.size > 0) values.push({ appId: "SEPARATOR", pinned: false, toplevels: [] });
        return values.concat([...running.values()]);
    }

    onAppsChanged: {
        const launching = root.launchingApps;
        let changed = false;
        for (const app of root.apps) {
            const state = launching[app.appId];
            if (state && app.toplevels.length > state.windows) {
                delete launching[app.appId];
                changed = true;
            }
        }
        if (changed) root.launchingApps = Object.assign({}, launching);
    }

    // Desktop entry lookup

    function desktopEntryFor(appId) {
        if (!appId || appId === "SEPARATOR") return null;
        const key = appId.toLowerCase();
        if (key in root.entryCache) return root.entryCache[key];
        const entry = root.findDesktopEntry(appId);
        root.entryCache[key] = entry;
        return entry;
    }

    function idCandidates(appId) {
        const substitution = AppSearch.substitutions[appId] ?? AppSearch.substitutions[appId.toLowerCase()];
        const parts = appId.split(/[.\-_\s]+/)
            .filter(part => part.length >= 3 && !root.genericIdParts.includes(part.toLowerCase()))
            .reverse();
        return [...new Set([substitution, ...parts].filter(candidate => !!candidate))];
    }

    function findDesktopEntry(appId) {
        const direct = DesktopEntries.heuristicLookup(appId);
        if (direct) return direct;

        const candidates = root.idCandidates(appId);
        for (const candidate of candidates) {
            const entry = DesktopEntries.heuristicLookup(candidate);
            if (entry) return entry;
        }

        // Match the executable or the display name against the window class
        const wanted = [appId, ...candidates].map(name => name.toLowerCase());
        const entries = DesktopEntries.applications.values.filter(entry => !entry.noDisplay);
        const byExec = entries.find(entry => {
            const executable = (entry.command[0] ?? "").split("/").pop().toLowerCase();
            return executable.length > 0 && wanted.includes(executable);
        });
        if (byExec) return byExec;
        return entries.find(entry => wanted.includes(entry.name.replace(/\s+/g, "").toLowerCase())) ?? null;
    }

    function displayName(appId) {
        const entry = root.desktopEntryFor(appId);
        if (entry?.name) return entry.name;
        const candidate = root.idCandidates(appId)[0] ?? appId;
        return StringUtils.toTitleCase(candidate.replace(/[-_]+/g, " "));
    }

    function iconFor(appId) {
        const entry = root.desktopEntryFor(appId);
        if (entry && AppSearch.iconExists(entry.icon)) return entry.icon;
        return AppSearch.guessIcon(appId);
    }

    // Launching

    function isLaunching(appId) {
        return !!root.launchingApps[appId.toLowerCase()];
    }

    function markLaunching(appId, windowCount) {
        const key = appId.toLowerCase();
        root.launchingApps = Object.assign({}, root.launchingApps, {
            [key]: { since: Date.now(), windows: windowCount ?? 0 }
        });
    }

    function launch(appId, windowCount) {
        const entry = root.desktopEntryFor(appId);
        const savedCommand = Config.options.dock.pinnedAppCommands?.[appId.toLowerCase()];
        if (entry && entry.command.length > 0) {
            if (entry.runInTerminal) {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(entry.command.join(" "))}'`]);
            } else {
                entry.execute();
            }
        } else if (savedCommand?.length > 0) {
            Quickshell.execDetached(savedCommand);
        } else {
            // Last resort: an executable named like the app, otherwise tell the user
            const finder = executableFinder.createObject(root, {
                appId: appId,
                windowCount: windowCount ?? 0,
                candidates: [appId, ...root.idCandidates(appId)],
            });
            finder.running = true;
            return;
        }
        root.markLaunching(appId, windowCount);
    }

    Component {
        id: executableFinder
        Process {
            id: finderProc
            property string appId
            property int windowCount
            property list<string> candidates
            command: ["sh", "-c", 'for c do command -v "$c" && exit 0; done; exit 1', "sh", ...finderProc.candidates]
            stdout: StdioCollector {
                id: finderOutput
            }
            onExited: (exitCode, exitStatus) => {
                const executable = finderOutput.text.trim().split("\n")[0];
                if (exitCode === 0 && executable.length > 0) {
                    Quickshell.execDetached([executable]);
                    root.markLaunching(finderProc.appId, finderProc.windowCount);
                } else {
                    Quickshell.execDetached(["notify-send", "-a", "Shell",
                        Translation.tr("Couldn't open %1").arg(root.displayName(finderProc.appId)),
                        Translation.tr("No app or command was found for it. Open it once and pin it again from the dock.")]);
                }
                finderProc.destroy();
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: Object.keys(root.launchingApps).length > 0
        onTriggered: {
            const now = Date.now();
            const launching = Object.assign({}, root.launchingApps);
            for (const key of Object.keys(launching)) {
                if (now - launching[key].since > root.launchTimeout) delete launching[key];
            }
            root.launchingApps = launching;
        }
    }

    // Apps without a desktop entry are relaunched with the command line of their running process

    function rememberLaunchCommand(appId) {
        const entry = root.desktopEntryFor(appId);
        if (entry && entry.command.length > 0) return;
        const key = appId.toLowerCase();
        const toplevel = ToplevelManager.toplevels.values.find(t => t.appId.toLowerCase() === key);
        const pid = HyprlandData.clientForToplevel(toplevel)?.pid;
        if (!pid) return;
        const reader = commandReader.createObject(root, { appKey: key, pid: pid });
        reader.running = true;
    }

    Component {
        id: commandReader
        Process {
            id: readerProc
            property string appKey
            property int pid
            // AppImages run from a temporary mount, so prefer the image itself
            command: ["sh", "-c", 'image=$(tr "\\0" "\\n" < "/proc/$1/environ" | sed -n "s/^APPIMAGE=//p"); if [ -n "$image" ]; then printf "%s\\n" "$image"; else tr "\\0" "\\n" < "/proc/$1/cmdline"; fi', "sh", `${readerProc.pid}`]
            stdout: StdioCollector {
                id: readerOutput
            }
            onExited: (exitCode, exitStatus) => {
                const args = readerOutput.text.split("\n").filter(arg => arg.length > 0);
                if (exitCode === 0 && args.length > 0 && root.isPinned(readerProc.appKey)) {
                    Config.options.dock.pinnedAppCommands = Object.assign({}, Config.options.dock.pinnedAppCommands, {
                        [readerProc.appKey]: args
                    });
                }
                readerProc.destroy();
            }
        }
    }
}
