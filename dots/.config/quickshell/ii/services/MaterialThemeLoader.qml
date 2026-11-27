pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath
    // Only the desktop shell publishes terminal colors. Settings can run in another process.
    property bool syncTerminals: false
    property string lastTerminalOptions: ""
    onSyncTerminalsChanged: if (syncTerminals) syncTerminalPalette()

    function syncTerminalPalette() {
        if (!Config.ready) return;
        let appearance;
        try { appearance = Config.savedAppearance(); } catch (error) { return; }
        const theming = appearance.wallpaperTheming;
        const options = JSON.stringify([theming?.enableTerminal ?? true, theming?.terminalGenerationProps?.forceDarkMode ?? false,
            appearance.palette?.roleOverrides ?? {}]);
        if (options === lastTerminalOptions) return;
        lastTerminalOptions = options;
        Quickshell.execDetached([Quickshell.shellPath("scripts/colors/applycolor.sh")]);
    }

    Connections {
        target: root.syncTerminals ? Config : null
        function onDiskSynced() { root.syncTerminalPalette(); }
    }

    function reapplyTheme(immediate = false) {
        themeFileView.reload();
        if (immediate) {
            // text() waits for this reload. Startup must not expose the built-in fallback palette.
            try {
                const content = themeFileView.text();
                const colors = JSON.parse(content);
                if (!colors.background || !colors.primary) return;
                root.applyColors(content);
                root.pendingColors = "";
                root.initialized = true;
            } catch (error) {}
        }
    }

    function applyColors(fileContent, duration = 0) {
        const json = JSON.parse(fileContent)
        Appearance.paletteTransitionDuration = duration
        const roles = Object.assign({}, Appearance.m3colors.generatedRoles);
        for (const key in json) {
            if (json.hasOwnProperty(key)) {
                if (roles.hasOwnProperty(key)) {
                    roles[key] = json[key];
                    continue;
                }
                // Convert snake_case to CamelCase
                const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                const m3Key = `m3${camelCaseKey}`
                Appearance.m3colors[m3Key] = json[key]
            }
        }
        Appearance.m3colors.generatedRoles = roles;
        
        Appearance.m3colors.darkmode = (Qt.color(json.background).hslLightness < 0.5)
    }

    // On first run there is no file for FileView to watch. Watch its directory
    // until the generator publishes the first palette by atomic rename.
    property bool waitingForFile: false
    readonly property string paletteDirectory: filePath.slice(0, filePath.lastIndexOf("/"))
    Process {
        id: prepareDirectory
        command: ["mkdir", "-p", "--", root.paletteDirectory]
        property bool ready: false
        onExited: code => { ready = code === 0; }
    }
    Loader {
        active: root.waitingForFile && prepareDirectory.ready
        sourceComponent: FolderListModel {
            folder: FileUtils.fileUrl(root.paletteDirectory)
            nameFilters: [root.filePath.slice(root.filePath.lastIndexOf("/") + 1)]
            showDirs: false
            onCountChanged: if (count) themeFileView.reload()
        }
    }

    property bool initialized: false
    property bool wallpaperChange: false
    property string pendingColors: ""
    property bool pendingForWallpaper: false
    property int revision: 0

    Connections {
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.wallpaperChange = true;
        }
    }
    Connections {
        target: WallpaperTransition
        function onLoadingChanged() {
            if (!WallpaperTransition.loading && root.pendingColors.length > 0) applyTimer.restart();
        }
        function onStarted(screenName, path) {
            if (!WallpaperTransition.loading && root.pendingColors.length > 0) root.flushColors();
        }
    }

    function queueColors(content) {
        // File watchers can observe an empty or partial write. Keep the previous palette.
        try {
            const colors = JSON.parse(content);
            if (!colors.background || !colors.primary) return;
        } catch (error) {
            return;
        }
        if (!root.initialized) {
            root.applyColors(content);
            root.initialized = true;
            return;
        }
        root.revision++;
        root.pendingColors = content;
        root.pendingForWallpaper = root.wallpaperChange || WallpaperTransition.changing;
        applyTimer.restart();
    }

    Timer {
        id: applyTimer
        // Coalesce writes, without guessing how long an image takes to decode. Under a preset's picture
        // of the screen the files were renamed into place whole, and the screen is waiting for them.
        interval: ThemeTransition.presetTransition && ThemeTransition.phase === "holding" ? 10 : 80
        onTriggered: root.flushColors()
    }
    function flushColors() {
        const forWallpaper = root.pendingForWallpaper || root.wallpaperChange || WallpaperTransition.changing;
        if (root.pendingColors.length === 0 || (forWallpaper && WallpaperTransition.loading)) return;
        const content = root.pendingColors;
        const revision = root.revision;
        root.pendingColors = "";
        root.wallpaperChange = false;
        // A screen capture here used to freeze the wallpaper halfway through its fade.
        if (ThemeTransition.presetTransition && ThemeTransition.phase === "holding") root.applyColors(content);
        else if (forWallpaper) root.applyColors(content, WallpaperTransition.remainingDuration(Appearance.scaledDuration(350)));
        else ThemeTransition.run(() => {
            if (revision === root.revision) root.applyColors(content, Appearance.scaledDuration(250));
        });
    }

    FileView {
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        blockLoading: true // Apply the saved palette before a new window can render its first frame.
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.waitingForFile = false;
            root.queueColors(themeFileView.text());
        }
        onLoadFailed: {
            if (root.waitingForFile || !root.paletteDirectory) return;
            root.waitingForFile = true;
            prepareDirectory.ready = false;
            prepareDirectory.running = true;
        }
    }
}
