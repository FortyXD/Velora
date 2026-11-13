pragma Singleton

import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "IntentRouter.js" as IntentRouter

Singleton {
    id: root

    property string query: ""
    property int queryRevision: 0
    property string intentMode: "auto"
    readonly property bool aiEnabled: (Config.options.search.ai?.enabled ?? false) && Assistant.enabled
    onAiEnabledChanged: {
        if (!aiEnabled) {
            intentMode = "auto";
            if (Assistant.origin === "launcher" && !Assistant.actionSession) {
                Assistant.cancel();
                Assistant.panelOpen = false;
            }
        }
    }
    readonly property var intent: IntentRouter.classify(query, aiEnabled ? intentMode : "search")
    function chooseIntent(mode) {
        if (["auto", "search", "chat", "action"].includes(mode)) intentMode = mode;
    }
    function submitCommand(command, displayText, cwd) {
        const args = {command, network: false};
        if (cwd) args.cwd = cwd;
        return Assistant.submitTool("terminal_run", args, displayText ?? command, "launcher");
    }
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() { if (!GlobalStates.overviewOpen && !GlobalStates.searchOpen) Lens.cancelSearch(); }
        function onSearchOpenChanged() { if (!GlobalStates.overviewOpen && !GlobalStates.searchOpen) Lens.cancelSearch(); }
    }
    readonly property bool mathQuery: looksLikeMath(query)
    function looksLikeMath(text) {
        text = text.trim();
        if (text.startsWith(Config.options.search.prefix.math)) return true;
        return IntentRouter.isMathExpression(text);
    }
    onQueryChanged: {
        queryRevision++;
        intentMode = "auto";
        nonAppResultsTimer.stop();
        mathProc.running = false;
        mathResult = "";
        if (looksLikeMath(root.query)) nonAppResultsTimer.restart();
        const prefixes = Config.options.search.prefix;
        const special = IntentRouter.isActionQuery(root.query, prefixes.action, root.allActions.map(a => a.action))
            || [prefixes.app, prefixes.clipboard, prefixes.emojis, prefixes.math, prefixes.shellCommand, prefixes.webSearch].some(prefix => prefix && root.query.startsWith(prefix));
        Lens.search(special ? "" : root.query);
    }

    property list<var> lensResults: []
    function refreshLensResults() {
        const previous = root.lensResults;
        const byId = new Map(previous.map(entry => [entry.id, entry]));
        const kinds = {folder: "Folder", file: "File", name: "File", config: "Configuration", photo: "Photo", video: "Video", app: "App"};
        const icons = {folder: "folder", photo: "image", video: "movie", config: "settings", app: "apps"};
        const hits = Lens.enabled && Lens.query === root.query ? Lens.results : [];
        const next = hits.map(hit => {
            const id = "lens-" + hit.id;
            const entry = byId.get(id) ?? resultComp.createObject(root, {id});
            byId.delete(id);
            entry.name = hit.name;
            entry.type = Translation.tr(kinds[hit.kind] ?? "File");
            entry.comment = Lens.explanation(hit);
            entry.lensPath = hit.path;
            entry.desktopId = hit.kind === "app" ? hit.path.replace(/^app:/, "").replace(/\.desktop$/, "") : "";
            entry.preview = hit.preview ?? "";
            entry.iconName = icons[hit.kind] ?? "description";
            entry.iconType = LauncherSearchResult.IconType.Material;
            entry.verb = Translation.tr("Open");
            entry.execute = () => Lens.open(hit, false);
            for (const action of entry.actions) action.destroy();
            entry.actions = hit.kind === "app" ? [] : [resultComp.createObject(root, {
                name: Translation.tr("Show in folder"), iconName: "folder_open", iconType: LauncherSearchResult.IconType.Material,
                execute: () => Lens.open(hit, true)
            }), resultComp.createObject(root, {
                name: Translation.tr("Copy path"), iconName: "content_copy", iconType: LauncherSearchResult.IconType.Material,
                execute: () => Quickshell.clipboardText = hit.path
            })];
            return entry;
        });
        root.lensResults = next;
        for (const entry of byId.values()) {
            entry.execute = () => {};
            for (const action of entry.actions) { action.execute = () => {}; action.destroy(); }
            entry.destroy();
        }
    }

    Connections {
        target: Lens
        function onResultsChanged() { root.refreshLensResults(); }
        function onEnabledChanged() { root.refreshLensResults(); }
    }

    function ensurePrefix(prefix) {
        if ([Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch,].some(i => root.query.startsWith(i))) {
            root.query = prefix + root.query.slice(1);
        } else {
            root.query = prefix + root.query;
        }
    }

    // https://specifications.freedesktop.org/menu/latest/category-registry.html
    property list<string> mainRegisteredCategories: ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]
    property list<string> appCategories: DesktopEntries.applications.values.reduce((acc, entry) => {
        for (const category of entry.categories) {
            if (!acc.includes(category) && mainRegisteredCategories.includes(category)) {
                acc.push(category);
            }
        }
        return acc;
    }, []).sort()

    // Load user action scripts from ~/.config/illogical-impulse/actions/
    // Uses FolderListModel to auto-reload when scripts are added/removed
    property var userActionScripts: {
        const actions = [];
        for (let i = 0; i < userActionsFolder.count; i++) {
            const fileName = userActionsFolder.get(i, "fileName");
            const filePath = userActionsFolder.get(i, "filePath");
            if (fileName && filePath) {
                const actionName = fileName.replace(/\.[^/.]+$/, ""); // strip extension
                actions.push({
                    action: actionName,
                    execute: ((path) => (args) => {
                        const slash = path.lastIndexOf("/");
                        const command = "'./" + StringUtils.shellSingleQuoteEscape(path.slice(slash + 1)) + "'" + (args ? " " + args : "");
                        root.submitCommand(command, actionName + (args ? " " + args : ""), path.slice(0, slash));
                    })(FileUtils.trimFileProtocol(filePath.toString()))
                });
            }
        }
        return actions;
    }

    FolderListModel {
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    property var searchActions: [
        {
            action: "accentcolor",
            execute: args => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
            }
        },
        {
            action: "dark",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
            }
        },
        {
            action: "konachanwallpaper",
            execute: () => {
                Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);
            }
        },
        {
            action: "light",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
            }
        },
        {
            action: "preset",
            execute: args => {
                const query = args.trim().toLowerCase();
                const preset = Presets.presets.find(preset => preset.id === query
                    || preset.name.toLowerCase() === query || Translation.tr(preset.name).toLowerCase() === query)
                    ?? Presets.presets.find(preset => query.length > 0 && Translation.tr(preset.name).toLowerCase().includes(query));
                if (!preset) {
                    Quickshell.execDetached(["notify-send", Translation.tr("Presets"), Translation.tr("Usage: <tt>%1preset NAME</tt>\nPresets: %2").arg(Config.options.search.prefix.action)
                        .arg(Presets.presets.map(preset => Translation.tr(preset.name)).join(", ")), "-a", "Shell"]);
                    return;
                }
                Presets.apply(preset.id);
            }
        },
        {
            action: "toolbox",
            execute: args => {
                // A tab name opens that tab; a link goes to the downloader
                const value = args.trim();
                const tab = ["converter", "downloader", "qr", "ocr", "colors"].includes(value.toLowerCase()) ? value.toLowerCase() : "";
                const link = /^https?:\/\//i.test(value) ? value : "";
                Quickshell.execDetached([Quickshell.shellPath("scripts/helper"), "toolbox-open", link ? "downloader" : (tab || "converter"), ...(link ? [link] : [])]);
            }
        },
        {
            action: "superpaste",
            execute: args => {
                if (!/^(\d+)/.test(args.trim())) {
                    // Invalid if doesn't start with numbers
                    Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1superpaste 4i</tt> for the last 4 images\n<tt>%1superpaste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                    return;
                }
                const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                const isImage = !!syntaxMatch[2];
                Cliphist.superpaste(count, isImage);
            }
        },
        {
            action: "todo",
            execute: args => {
                Todo.addTask(args);
            }
        },
        {
            action: "wallpaper",
            execute: () => {
                Hyprland.dispatch(`hl.dsp.global("quickshell:wallpaperSelectorToggle")`)
            }
        },
        {
            action: "wipeclipboard",
            execute: () => {
                Cliphist.wipe();
            }
        },
    ]

    // Combined built-in and user actions
    property var allActions: searchActions.concat(userActionScripts)

    property string mathResult: ""
    property bool clipboardWorkSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }

    Timer {
        id: nonAppResultsTimer
        interval: Config.options.search.nonAppResultDelay
        onTriggered: {
            let expr = root.query;
            if (expr.startsWith(Config.options.search.prefix.math)) {
                expr = expr.slice(Config.options.search.prefix.math.length);
            }
            mathProc.calculateExpression(expr);
        }
    }

    Process {
        id: mathProc
        property string queryText: ""
        property list<string> baseCommand: ["qalc", "-t"]
        function calculateExpression(expression) {
            mathProc.running = false;
            mathProc.queryText = root.query;
            mathProc.command = baseCommand.concat(expression);
            mathProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                if (mathProc.queryText === root.query && root.mathQuery) root.mathResult = data;
            }
        }
    }

    property list<var> results: {
        // Search results are handled here
        ////////////////// Skip? //////////////////
        if (root.query == "")
            return [];

        ///////////// Special cases ///////////////
        if (root.query.startsWith(Config.options.search.prefix.clipboard)) {
            // Clipboard
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.clipboard);
            return Cliphist.fuzzyQuery(searchString).map((entry, index, array) => {
                const mightBlurImage = Cliphist.entryIsImage(entry) && root.clipboardWorkSafetyActive;
                let shouldBlurImage = mightBlurImage;
                if (mightBlurImage) {
                    shouldBlurImage = shouldBlurImage && (root.containsUnsafeLink(array[index - 1]) || root.containsUnsafeLink(array[index + 1]));
                }
                const type = `#${entry.match(/^\s*(\S+)/)?.[1] || ""}`;
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: StringUtils.cleanCliphistEntry(entry),
                    verb: "",
                    type: type,
                    execute: () => {
                        Cliphist.copy(entry);
                    },
                    actions: [resultComp.createObject(null, {
                            name: Translation.tr("Copy"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.copy(entry);
                            }
                        }), resultComp.createObject(null, {
                            name: Translation.tr("Delete"),
                            iconName: "delete",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.deleteEntry(entry);
                            }
                        })],
                    blurImage: shouldBlurImage
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.emojis)) {
            // Clipboard
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.emojis);
            return Emojis.fuzzyQuery(searchString).map(entry => {
                const emoji = entry.match(/^\s*(\S+)/)?.[1] || "";
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: entry.replace(/^\s*\S+\s+/, ""),
                    iconName: emoji,
                    iconType: LauncherSearchResult.IconType.Text,
                    verb: Translation.tr("Copy"),
                    type: Translation.tr("Emoji"),
                    execute: () => {
                        Quickshell.clipboardText = entry.match(/^\s*(\S+)/)?.[1];
                    }
                });
            }).filter(Boolean);
        }

        ////////////////// Init ///////////////////
        const mathResultObject = root.mathQuery && root.mathResult !== "" ? resultComp.createObject(null, {
            name: root.mathResult,
            verb: Translation.tr("Copy"),
            type: Translation.tr("Math result"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'calculate',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                Quickshell.clipboardText = root.mathResult;
            }
        }) : null;
        const appResultObjects = AppSearch.fuzzyQuery(StringUtils.cleanPrefix(root.query, Config.options.search.prefix.app)).map(entry => {
            return resultComp.createObject(null, {
                type: Translation.tr("App"),
                id: entry.id,
                name: entry.name,
                iconName: entry.icon,
                iconType: LauncherSearchResult.IconType.System,
                verb: Translation.tr("Open"),
                execute: () => {
                    if (!entry.runInTerminal)
                        entry.execute();
                    else {
                        // Probably needs more proper escaping, but this will do for now
                        Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(entry.command.join(' '))}'`]);
                    }
                },
                comment: entry.comment,
                runInTerminal: entry.runInTerminal,
                genericName: entry.genericName,
                keywords: entry.keywords,
                actions: entry.actions.map(action => {
                    return resultComp.createObject(null, {
                        name: action.name,
                        iconName: action.icon,
                        iconType: LauncherSearchResult.IconType.System,
                        execute: () => {
                            if (!action.runInTerminal)
                                action.execute();
                            else {
                                Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(action.command.join(' '))}'`]);
                            }
                        }
                    });
                })
            });
        });
        const submittedQuery = root.query;
        const submittedRevision = root.queryRevision;
        const shellPrefix = Config.options.search.prefix.shellCommand;
        const submittedCommand = StringUtils.cleanPrefix(submittedQuery, shellPrefix);
        const commandResultObject = resultComp.createObject(null, {
            id: "command:" + submittedRevision,
            name: submittedCommand,
            verb: Translation.tr("Review command"),
            type: Translation.tr("Command"),
            comment: Translation.tr("Choose a folder, review the command and approve changes"),
            keepOpen: true,
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'terminal',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                if (root.queryRevision !== submittedRevision) return;
                root.submitCommand(submittedCommand, submittedQuery);
            }
        });
        const webSearchResultObject = resultComp.createObject(null, {
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch),
            verb: Translation.tr("Search"),
            type: Translation.tr("Web search"),
            iconName: 'travel_explore',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let query = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch);
                let url = Config.options.search.engineBaseUrl + query;
                for (let site of Config.options.search.excludedSites) {
                    url += ` -site:${site}`;
                }
                Qt.openUrlExternally(url);
            }
        });
        const launcherActionObjects = root.allActions.map(action => {
            const actionString = `${Config.options.search.prefix.action}${action.action}`;
            const actionArgs = submittedQuery.split(" ").slice(1).join(" ");
            if (actionString.startsWith(root.query) || root.query === actionString || root.query.startsWith(actionString + " ")) {
                return resultComp.createObject(null, {
                    name: root.query.startsWith(actionString) ? root.query : actionString,
                    verb: Translation.tr("Run"),
                    type: Translation.tr("Action"),
                    iconName: 'settings_suggest',
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        if (root.queryRevision === submittedRevision) action.execute(actionArgs);
                    }
                });
            }
            return null;
        }).filter(Boolean);

        //////// Prioritized by prefix /////////
        let result = [];
        const startsWithNumber = /^\d/.test(root.query);
        const startsWithMathPrefix = root.query.startsWith(Config.options.search.prefix.math);
        const startsWithShellCommandPrefix = root.query.startsWith(Config.options.search.prefix.shellCommand);
        const startsWithWebSearchPrefix = root.query.startsWith(Config.options.search.prefix.webSearch);
        if (startsWithNumber || startsWithMathPrefix) {
            if (mathResultObject) result.push(mathResultObject);
        } else if (startsWithShellCommandPrefix) {
            result.push(commandResultObject);
        } else if (startsWithWebSearchPrefix) {
            result.push(webSearchResultObject);
        }

        //////////////// Apps //////////////////
        const fileResults = root.lensResults.filter(entry => entry.type !== Translation.tr("App") || !appResultObjects.some(app => app.id.replace(/\.desktop$/, "") === entry.desktopId));
        // An explicit file/config/photo intent should lead with those results,
        // even when an installed application's name loosely matches the query.
        const fileIntent = Lens.enabled && Lens.query === root.query && Lens.queryKind !== "" && Lens.queryKind !== "app";
        result = fileIntent ? result.concat(fileResults, appResultObjects) : result.concat(appResultObjects, fileResults);

        ////////// Launcher actions ////////////
        result = result.concat(launcherActionObjects);

        /// Math result, command, web search ///
        if (Config.options.search.prefix.showDefaultActionsWithoutPrefix) {
            if (!startsWithShellCommandPrefix)
                result.push(commandResultObject);
            if (!startsWithNumber && !startsWithMathPrefix && mathResultObject)
                result.push(mathResultObject);
            if (!startsWithWebSearchPrefix)
                result.push(webSearchResultObject);
        }

        if (root.aiEnabled && !startsWithShellCommandPrefix && !startsWithWebSearchPrefix && !root.mathQuery) {
            const choices = ["chat", "action"].map(mode => resultComp.createObject(null, {
                id: "assistant:" + mode + ":" + submittedRevision,
                name: mode === "chat" ? Translation.tr("Ask AI") : Translation.tr("Run a task"),
                type: mode === "chat" ? Translation.tr("Question") : Translation.tr("Task"),
                comment: mode === "chat" ? Translation.tr("Discuss without changing files") : Translation.tr("Changes require confirmation and support rollback"),
                iconName: mode === "chat" ? "chat" : "neurology", iconType: LauncherSearchResult.IconType.Material,
                keepOpen: true, verb: Translation.tr("Send"),
                execute: () => {
                    if (root.aiEnabled && root.queryRevision === submittedRevision) Assistant.submit(submittedQuery, submittedQuery, "launcher", mode);
                }
            }));
            if (root.intent.kind === "chat") result = [choices[0]].concat(result, [choices[1]]);
            else if (root.intent.kind === "action") result = [choices[1]].concat(result, [choices[0]]);
            else if (root.intent.kind === "ambiguous") {
                const searchChoice = resultComp.createObject(null, {
                    id: "intent-search:" + submittedRevision, name: Translation.tr("Find matching files and apps"),
                    type: Translation.tr("Choose intent"), iconName: "search", iconType: LauncherSearchResult.IconType.Material,
                    keepOpen: true, verb: Translation.tr("Search"),
                    execute: () => { if (root.queryRevision === submittedRevision) root.chooseIntent("search"); }
                });
                result = [searchChoice].concat(choices, result);
            } else if (root.intentMode !== "search") result = result.concat(choices);
        }
        return result;
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }
}
