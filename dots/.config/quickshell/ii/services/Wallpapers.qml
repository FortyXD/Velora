import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Provides a list of wallpapers and an "apply" action that calls the existing
 * switchwall.sh script. Pretty much a limited file browsing service.
 */
Singleton {
    id: root

    property alias directory: folderModel.folder
    readonly property string effectiveDirectory: FileUtils.trimFileProtocol(folderModel.folder.toString())
    property url defaultFolder: Qt.resolvedUrl(`${Directories.pictures}/Wallpapers`)
    property alias folderModel: folderModel // Expose for direct binding when needed
    property string searchQuery: ""
    readonly property list<string> extensions: [
        "jpg", "jpeg", "png", "webp", "avif", "bmp", "svg",
        "mp4", "webm", "mkv", "mov", "avi" // Live wallpapers (LiveWallpaper.qml)
    ]
    property list<string> wallpapers: [] // List of absolute file paths (without file://)
    readonly property bool thumbnailGenerationRunning: thumbgenProc.running
    property real thumbnailGenerationProgress: 0

    signal changed()
    signal thumbnailGenerated(directory: string)
    signal thumbnailGeneratedFile(filePath: string)

    // The shell records confirmed changes from every picker, preset and IPC client.
    // Settings also watches this file so opening a preview never records a choice.
    property bool trackingHistory: false
    property bool historyReady: false
    readonly property var currentWallpaper: {
        if (!Config.ready) return null;
        const path = FileUtils.localPath(Config.options.background.wallpaperPath);
        if (ShaderWallpaper.active) {
            const shader = ShaderWallpaper.name;
            const poster = path === ShaderWallpaper.framePath(shader) ? path : ShaderWallpaper.posterPath(shader);
            return {key: "shader:" + shader, shader, path: "", poster,
                colors: Array.from(Config.options.background.shaderWallpaper.colors)};
        }
        if (!path) return null;
        const thumbnail = FileUtils.localPath(Config.options.background.thumbnailPath);
        return {key: path, path, poster: FileUtils.wallpaperPicture(path, thumbnail)};
    }
    readonly property var recentWallpapers: {
        const saved = historyData.entries.filter(entry => entry && typeof entry.key === "string"
            && (entry.path || ShaderWallpaper.shader(entry.shader)));
        const current = currentWallpaper;
        if (!current) return saved;
        const previous = saved.find(entry => entry.key === current.key);
        const entry = !current.poster && previous?.poster ? Object.assign({}, current, {poster: previous.poster}) : current;
        return [entry, ...saved.filter(item => item.key !== entry.key)].slice(0, 8);
    }

    function load() {
        trackingHistory = true;
        Qt.callLater(recordCurrent);
    }
    function refreshHistory() {
        historyFile.reload();
    }
    function recordCurrent() {
        if (!trackingHistory || !historyReady || !currentWallpaper) return;
        const entry = recentWallpapers[0], last = historyData.entries[0];
        if (last?.key === entry.key && last.poster === entry.poster
            && JSON.stringify(last.colors) === JSON.stringify(entry.colors)) return;
        historyData.entries = recentWallpapers;
        historyFile.writeAdapter();
    }
    onCurrentWallpaperChanged: if (trackingHistory) Qt.callLater(recordCurrent)

    FileView {
        id: historyFile
        path: FileUtils.trimFileProtocol(Directories.state) + "/recent-wallpapers.json"
        watchChanges: true
        blockWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.historyReady = true;
            if (root.trackingHistory) Qt.callLater(root.recordCurrent);
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.historyReady = true;
                if (root.trackingHistory) Qt.callLater(root.recordCurrent);
            }
        }
        adapter: JsonAdapter {
            id: historyData
            property list<var> entries: []
        }
    }

    // Executions
    Process {
        id: applyProc
    }
    
    function openFallbackPicker(darkMode = Appearance.m3colors.darkmode) {
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", darkMode ? "dark" : "light"]);
    }

    function apply(path, darkMode = Appearance.m3colors.darkmode) {
        if (!path || path.length === 0) return;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", darkMode ? "dark" : "light", "--image", path]);
        root.changed()
    }

    Process {
        id: selectProc
        property string filePath: ""
        property bool darkMode: Appearance.m3colors.darkmode
        function select(filePath, darkMode = Appearance.m3colors.darkmode) {
            selectProc.filePath = filePath
            selectProc.darkMode = darkMode
            selectProc.exec(["test", "-d", FileUtils.trimFileProtocol(filePath)])
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                setDirectory(selectProc.filePath);
                return;
            }
            root.apply(selectProc.filePath, selectProc.darkMode);
        }
    }

    function select(filePath, darkMode = Appearance.m3colors.darkmode) {
        selectProc.select(filePath, darkMode);
    }

    function randomFromCurrentFolder(darkMode = Appearance.m3colors.darkmode) {
        const files = filesInCurrentFolder();
        if (files.length) apply(files[Math.floor(Math.random() * files.length)], darkMode);
    }

    function filesInCurrentFolder() {
        const files = [];
        for (let index = 0; index < folderModel.count; ++index) {
            if (!folderModel.isFolder(index)) files.push(folderModel.get(index, "filePath"));
        }
        return files;
    }

    Process {
        id: validateDirProc
        property string nicePath: ""
        function setDirectoryIfValid(path) {
            validateDirProc.nicePath = FileUtils.trimFileProtocol(path).replace(/\/+$/, "")
            if (/^\/*$/.test(validateDirProc.nicePath)) validateDirProc.nicePath = "/";
            validateDirProc.exec([
                "bash", "-c",
                `if [ -d "${validateDirProc.nicePath}" ]; then echo dir; elif [ -f "${validateDirProc.nicePath}" ]; then echo file; else echo invalid; fi`
            ])
        }
        stdout: StdioCollector {
            onStreamFinished: {
                    root.directory = Qt.resolvedUrl(validateDirProc.nicePath)
                const result = text.trim()
                if (result === "dir") {
                } else if (result === "file") {
                    root.directory = Qt.resolvedUrl(FileUtils.parentDirectory(validateDirProc.nicePath))
                } else {
                    // Ignore
                }
            }
        }
    }
    function setDirectory(path) {
        validateDirProc.setDirectoryIfValid(path)
    }
    function navigateUp() {
        folderModel.navigateUp()
    }
    function navigateBack() {
        folderModel.navigateBack()
    }
    function navigateForward() {
        folderModel.navigateForward()
    }

    // Folder model
    FolderListModelWithHistory {
        id: folderModel
        folder: Qt.resolvedUrl(root.defaultFolder)
        caseSensitive: false
        nameFilters: root.extensions.map(ext => `*${searchQuery.split(" ").filter(s => s.length > 0).map(s => `*${s}*`)}*.${ext}`)
        showDirs: true
        showDotAndDotDot: false
        showOnlyReadable: true
        sortField: FolderListModel.Time
        sortReversed: false
        onCountChanged: {
            root.wallpapers = []
            for (let i = 0; i < folderModel.count; i++) {
                const path = folderModel.get(i, "filePath") || FileUtils.trimFileProtocol(folderModel.get(i, "fileURL"))
                if (path && path.length) root.wallpapers.push(path)
            }
        }
    }

    // Thumbnail generation
    function generateThumbnail(size: string) {
        if (!["normal", "large", "x-large", "xx-large"].includes(size)) throw new Error("Invalid thumbnail size");
        thumbgenProc.directory = root.directory
        thumbgenProc.running = false
        thumbgenProc.command = [Quickshell.shellPath("scripts/helper"), "thumbnails", "--size", size, "--directory", FileUtils.trimFileProtocol(root.directory)]
        // console.log("[Wallpapers] Updating thumbnails with command ", thumbgenProc.command.join(" "))
        root.thumbnailGenerationProgress = 0
        thumbgenProc.running = true
    }
    Process {
        id: thumbgenProc
        property string directory
        stdout: SplitParser {
            onRead: data => {
                // print("thumb gen proc:", data)
                let match = data.match(/PROGRESS (\d+)\/(\d+)/)
                if (match) {
                    const completed = parseInt(match[1])
                    const total = parseInt(match[2])
                    root.thumbnailGenerationProgress = completed / total
                }
                match = data.match(/FILE (.+)/)
                if (match) {
                    const filePath = match[1]
                    root.thumbnailGeneratedFile(filePath)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // print("[Wallpapers] Thumbnail generation completed with exit code", exitCode)
            root.thumbnailGenerated(thumbgenProc.directory)
        }
    }

    IpcHandler {
        target: "wallpapers"

        function apply(path: string): void {
            root.apply(path);
        }
    }
}
