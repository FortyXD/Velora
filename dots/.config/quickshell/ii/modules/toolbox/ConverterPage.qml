import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Converts images, video, audio, documents and PDFs, and packs or unpacks archives.
 * Files come from drag and drop, the file picker, Dolphin's menu or the command line.
 */
ContentPage {
    id: page

    property var caps: ({}) // Installed tools, from `velora-helper toolbox-caps`
    property list<var> files: [] // { path, name, kind, size, duration, status, percent, output, message }
    property bool running: job.running
    property string outDir: "" // Empty: next to each file
    property var queue: [] // Remaining { kind, target, paths } groups of a run
    property var chosenTargets: ({}) // kind → target
    property string packFormat: ""

    // Options
    property int imageQuality: 85
    property string imageResize: ""
    property bool stripMetadata: true
    property bool mergeImagesToPdf: false
    property int videoCrf: 23
    property int videoHeight: 0
    property int videoFps: 0
    property string trimStart: ""
    property string trimEnd: ""
    property real targetSize: 0
    property bool removeAudio: false
    property string audioBitrate: ""
    property int pdfDpi: 150

    readonly property var kinds: [...new Set(files.map(file => file.kind))]
    readonly property var targetsByKind: ({
        "image": [["png", "PNG"], ["jpg", "JPG"], ["webp", "WebP"], ["avif", "AVIF"], ["heic", "HEIC"], ["ico", "ICO"], ["bmp", "BMP"], ["tiff", "TIFF"], ["gif", "GIF"], ["pdf", "PDF"]],
        "video": [["mp4", "MP4"], ["webm", "WebM"], ["mkv", "MKV"], ["gif", "GIF"], ["mp3", "MP3"], ["opus", "Opus"], ["flac", "FLAC"], ["m4a", "M4A"]],
        "audio": [["mp3", "MP3"], ["opus", "Opus"], ["ogg", "OGG"], ["flac", "FLAC"], ["wav", "WAV"], ["m4a", "M4A"]],
        "document": [["pdf", "PDF"], ["docx", "DOCX"], ["odt", "ODT"], ["html", "HTML"], ["md", "Markdown"], ["txt", "TXT"], ["epub", "EPUB"]],
        "pdf": [["png", Translation.tr("PNG pages")], ["jpg", Translation.tr("JPG pages")], ["txt", Translation.tr("Text")], ["docx", "DOCX"], ["pdf-merge", Translation.tr("Merge into one")], ["pdf-compress", Translation.tr("Compress")]],
        "archive": [["extract", Translation.tr("Extract")]],
    })
    readonly property var kindInfo: ({
        "image": { "name": Translation.tr("Images"), "icon": "image" },
        "video": { "name": Translation.tr("Video"), "icon": "movie" },
        "audio": { "name": Translation.tr("Audio"), "icon": "music_note" },
        "document": { "name": Translation.tr("Documents"), "icon": "description" },
        "pdf": { "name": "PDF", "icon": "picture_as_pdf" },
        "archive": { "name": Translation.tr("Archives"), "icon": "folder_zip" },
        "folder": { "name": Translation.tr("Folders"), "icon": "folder" },
        "other": { "name": Translation.tr("Other files"), "icon": "draft" },
    })

    // Why a target can't be used right now, or "" if it can
    function missingTool(kind, target) {
        const has = tool => !!page.caps[tool];
        if (kind === "image") return has("magick") ? "" : "ImageMagick";
        if (kind === "video" || kind === "audio") return has("ffmpeg") ? "" : "ffmpeg";
        if (kind === "pdf") {
            if (target === "png" || target === "jpg") return has("pdftoppm") ? "" : "poppler";
            if (target === "txt") return has("pdftoppm") ? "" : "poppler";
            if (target === "docx") return has("soffice") || has("libreoffice") ? "" : "LibreOffice";
            if (target === "pdf-merge") return has("qpdf") || has("gs") ? "" : "qpdf";
            if (target === "pdf-compress") return has("gs") ? "" : "Ghostscript";
        }
        if (kind === "document") return has("pandoc") || has("soffice") || has("libreoffice") ? "" : "pandoc";
        if (kind === "archive") return has("7z") || has("bsdtar") ? "" : "7zip";
        return "";
    }

    function sizeText(bytes) {
        if (!(bytes > 0)) return "";
        if (bytes < 1048576) return Translation.tr("%1 KB").arg(Math.max(1, Math.round(bytes / 1024)));
        return Translation.tr("%1 MB").arg((bytes / 1048576).toFixed(1));
    }

    function addPaths(paths) {
        const clean = paths.map(path => decodeURIComponent(FileUtils.trimFileProtocol(`${path}`)).trim())
            .filter(path => path.length > 0 && !page.files.some(file => file.path === path));
        if (clean.length === 0) return;
        detectProc.command = [Quickshell.shellPath("scripts/helper"), "toolbox-detect", ...clean];
        detectProc.running = true;
    }

    function setFile(index, patch) {
        let files = page.files.slice();
        files[index] = Object.assign({}, files[index], patch);
        page.files = files;
    }

    function targetFor(kind) {
        return page.chosenTargets[kind] ?? (page.targetsByKind[kind]?.[0]?.[0] ?? "");
    }

    function optionArgs(kind) {
        let args = [];
        if (page.outDir.length > 0) args.push("--out-dir", page.outDir);
        if (kind === "image") {
            args.push("--quality", `${page.imageQuality}`);
            if (page.imageResize.length > 0) args.push("--resize", page.imageResize);
            if (page.stripMetadata) args.push("--strip");
            if (page.mergeImagesToPdf) args.push("--merge");
        } else if (kind === "video" || kind === "audio") {
            args.push("--crf", `${page.videoCrf}`);
            if (page.videoHeight > 0) args.push("--height", `${page.videoHeight}`);
            if (page.videoFps > 0) args.push("--fps", `${page.videoFps}`);
            if (page.trimStart.trim().length > 0) args.push("--start", page.trimStart.trim());
            if (page.trimEnd.trim().length > 0) args.push("--end", page.trimEnd.trim());
            if (page.targetSize > 0) args.push("--target-size", `${page.targetSize}`);
            if (page.removeAudio) args.push("--no-audio");
            if (page.audioBitrate.length > 0) args.push("--bitrate", page.audioBitrate);
        } else if (kind === "pdf") {
            args.push("--dpi", `${page.pdfDpi}`);
        }
        return args;
    }

    function startConversion() {
        let groups = [];
        for (const kind of page.kinds) {
            if (!page.targetsByKind[kind]) continue;
            const target = page.targetFor(kind);
            if (page.missingTool(kind, target).length > 0) continue;
            const paths = page.files.filter(file => file.kind === kind && file.status !== "done").map(file => file.path);
            if (paths.length > 0) groups.push({ "kind": kind, "target": target, "paths": paths });
        }
        page.queue = groups;
        page.runNext();
    }

    function startPacking(format) {
        const paths = page.files.map(file => file.path);
        if (paths.length === 0) return;
        page.queue = [{ "kind": "pack", "target": format, "paths": paths }];
        page.runNext();
    }

    function runNext() {
        if (page.queue.length === 0) return;
        const group = page.queue[0];
        page.queue = page.queue.slice(1);
        job.group = group;
        job.start(["convert", "--to", group.target, ...page.optionArgs(group.kind), ...group.paths]);
    }

    function indexOfPath(path) {
        return page.files.findIndex(file => file.path === path);
    }

    function revealInFiles(path) {
        Quickshell.execDetached(["dbus-send", "--session", "--dest=org.freedesktop.FileManager1", "--type=method_call",
            "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems", `array:string:file://${path}`, "string:"]);
    }

    ToolboxJob {
        id: job
        property var group: null
        onEvent: data => {
            const index = page.indexOfPath(data.file ?? "");
            const all = job.group?.kind === "pack" || job.group?.target === "pdf-merge" || (job.group?.target === "pdf" && page.mergeImagesToPdf && job.group?.kind === "image");
            const targets = all ? job.group.paths.map(path => page.indexOfPath(path)) : [index];
            for (const i of targets) {
                if (i < 0) continue;
                if (data.event === "start") page.setFile(i, { "status": "working", "percent": -1, "message": "" });
                else if (data.event === "progress") page.setFile(i, { "status": "working", "percent": data.percent });
                else if (data.event === "done") page.setFile(i, { "status": "done", "output": data.output, "percent": 100 });
                else if (data.event === "error") page.setFile(i, { "status": "error", "message": data.message });
            }
        }
        onFinishedAll: {
            // A cancelled run leaves files marked as working
            page.files = page.files.map(file => file.status === "working" ? Object.assign({}, file, { "status": "waiting" }) : file);
            page.runNext();
        }
    }

    Process {
        id: detectProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const found = JSON.parse(text).map(file => Object.assign({ "status": "waiting", "percent": -1, "output": "", "message": "" }, file));
                    page.files = [...page.files, ...found];
                } catch (e) {
                    console.warn("[Toolbox] detect failed:", e);
                }
            }
        }
    }

    Process {
        id: pickProc
        property bool folder: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(line => line.trim().length > 0);
                if (pickProc.folder) {
                    if (lines.length > 0) page.outDir = lines[0];
                } else {
                    page.addPaths(lines);
                }
            }
        }
    }

    function pickFiles() {
        pickProc.folder = false;
        pickProc.command = ["kdialog", "--title", Translation.tr("Choose files to convert"), "--getopenfilename", Directories.home, "--multiple", "--separate-output"];
        pickProc.running = true;
    }

    function pickFolder() {
        pickProc.folder = true;
        pickProc.command = ["kdialog", "--title", Translation.tr("Where to save"), "--getexistingdirectory", page.outDir.length > 0 ? page.outDir : Directories.home];
        pickProc.running = true;
    }

    component ChoiceRow: ContentSubsection {
        id: choiceRow
        required property var options
        property var currentValue
        signal chosen(var value)
        ConfigSelectionArray {
            currentValue: choiceRow.currentValue
            options: choiceRow.options
            onSelected: newValue => choiceRow.chosen(newValue)
        }
    }

    ContentSection {
        icon: "transform"
        title: Translation.tr("Files")
        description: Translation.tr("Drop files here from the file manager, or pick them")

        DropArea {
            Layout.fillWidth: true
            implicitHeight: dropColumn.implicitHeight + 32
            onDropped: drop => {
                if (drop.hasUrls) page.addPaths(drop.urls.map(url => `${url}`));
            }

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: parent.containsDrag ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                border.width: 2
                border.color: parent.containsDrag ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
            }

            ColumnLayout {
                id: dropColumn
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "upload_file"
                    iconSize: 36
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Drop files to convert")
                    color: Appearance.colors.colOnLayer2
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    DialogButton {
                        buttonText: Translation.tr("Choose files")
                        enabled: !!page.caps["kdialog"]
                        onClicked: page.pickFiles()
                    }
                    DialogButton {
                        visible: page.files.length > 0
                        buttonText: Translation.tr("Clear the list")
                        enabled: !page.running
                        onClicked: page.files = []
                    }
                }
            }
        }

        Repeater {
            model: page.files
            delegate: RowLayout {
                id: fileRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    text: page.kindInfo[fileRow.modelData.kind]?.icon ?? "draft"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: fileRow.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: fileRow.modelData.status === "error" ? fileRow.modelData.message
                            : fileRow.modelData.status === "done" ? Translation.tr("Saved: %1").arg(fileRow.modelData.output.split("/").pop())
                            : ["other", "folder"].includes(fileRow.modelData.kind) ? Translation.tr("Can only go into an archive")
                            : [page.sizeText(fileRow.modelData.size),
                               fileRow.modelData.duration > 0 ? `${Math.round(fileRow.modelData.duration)} s` : ""].filter(part => part).join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: fileRow.modelData.status === "error" ? Appearance.colors.colError : Appearance.colors.colSubtext
                    }
                    StyledProgressBar {
                        Layout.fillWidth: true
                        visible: fileRow.modelData.status === "working" && fileRow.modelData.percent >= 0
                        value: Math.max(0, fileRow.modelData.percent) / 100
                    }
                    StyledIndeterminateProgressBar {
                        Layout.fillWidth: true
                        visible: fileRow.modelData.status === "working" && fileRow.modelData.percent < 0
                    }
                }
                MaterialSymbol {
                    visible: fileRow.modelData.status === "done"
                    text: "check_circle"
                    iconSize: 20
                    fill: 1
                    color: Appearance.colors.colPrimary
                }
                DialogButton {
                    visible: fileRow.modelData.status === "done"
                    buttonText: Translation.tr("Show")
                    onClicked: page.revealInFiles(fileRow.modelData.output)
                }
                RippleButton {
                    visible: !page.running
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: page.files = page.files.filter((_, i) => i !== fileRow.index)
                    contentItem: MaterialSymbol {
                        text: "close"
                        iconSize: 18
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }

    ContentSection {
        visible: page.files.length > 0
        icon: "output"
        title: Translation.tr("Convert to")
        description: Translation.tr("Each kind of file gets its own format")

        Repeater {
            model: page.kinds.filter(kind => page.targetsByKind[kind])
            delegate: ContentSubsection {
                id: kindBlock
                required property string modelData
                title: page.kindInfo[modelData].name
                ConfigSelectionArray {
                    currentValue: page.targetFor(kindBlock.modelData)
                    options: page.targetsByKind[kindBlock.modelData].map(entry => ({
                        "displayName": entry[1] + (page.missingTool(kindBlock.modelData, entry[0]).length > 0 ? " ✕" : ""),
                        "value": entry[0]
                    }))
                    onSelected: newValue => {
                        let chosen = Object.assign({}, page.chosenTargets);
                        chosen[kindBlock.modelData] = newValue;
                        page.chosenTargets = chosen;
                    }
                }
                StyledText {
                    readonly property string missing: page.missingTool(kindBlock.modelData, page.targetFor(kindBlock.modelData))
                    visible: missing.length > 0
                    text: Translation.tr("Needs %1, which isn't installed").arg(missing)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                }
            }
        }

        // Options for the kinds in the list
        ContentSubsection {
            visible: page.kinds.includes("image")
            title: Translation.tr("Image size")
            ConfigSelectionArray {
                currentValue: page.imageResize
                onSelected: newValue => page.imageResize = newValue
                options: [
                    { "displayName": Translation.tr("Original"), "value": "" },
                    { "displayName": "50%", "value": "50%" },
                    { "displayName": Translation.tr("Up to 3840 px"), "value": "3840x3840>" },
                    { "displayName": Translation.tr("Up to 1920 px"), "value": "1920x1920>" },
                    { "displayName": Translation.tr("Up to 1280 px"), "value": "1280x1280>" }
                ]
            }
        }
        ConfigSlider {
            visible: page.kinds.includes("image")
            buttonIcon: "high_quality"
            text: Translation.tr("Image quality")
            from: 30
            to: 100
            usePercentTooltip: false
            valueText: `${Math.round(value)}`
            value: page.imageQuality
            onMoved: page.imageQuality = Math.round(value)
        }
        ConfigRow {
            uniform: true
            visible: page.kinds.includes("image")
            ConfigSwitch {
                buttonIcon: "privacy_tip"
                text: Translation.tr("Remove metadata")
                description: Translation.tr("Camera, place and time")
                checked: page.stripMetadata
                onCheckedChanged: page.stripMetadata = checked
            }
            ConfigSwitch {
                buttonIcon: "picture_as_pdf"
                text: Translation.tr("One PDF from all images")
                checked: page.mergeImagesToPdf
                onCheckedChanged: page.mergeImagesToPdf = checked
            }
        }

        ContentSubsection {
            visible: page.kinds.includes("video")
            title: Translation.tr("Video quality")
            ConfigSelectionArray {
                currentValue: page.videoCrf
                onSelected: newValue => page.videoCrf = newValue
                options: [
                    { "displayName": Translation.tr("High"), "value": 18 },
                    { "displayName": Translation.tr("Balanced"), "value": 23 },
                    { "displayName": Translation.tr("Small file"), "value": 28 }
                ]
            }
        }
        ContentSubsection {
            visible: page.kinds.includes("video")
            title: Translation.tr("Resolution and frame rate")
            Flow {
                Layout.fillWidth: true
                spacing: 8
                ConfigSelectionArray {
                    currentValue: page.videoHeight
                    onSelected: newValue => page.videoHeight = newValue
                    options: [
                        { "displayName": Translation.tr("Original"), "value": 0 },
                        { "displayName": "1080p", "value": 1080 },
                        { "displayName": "720p", "value": 720 },
                        { "displayName": "480p", "value": 480 }
                    ]
                }
                ConfigSelectionArray {
                    currentValue: page.videoFps
                    onSelected: newValue => page.videoFps = newValue
                    options: [
                        { "displayName": Translation.tr("Original fps"), "value": 0 },
                        { "displayName": "60", "value": 60 },
                        { "displayName": "30", "value": 30 },
                        { "displayName": "24", "value": 24 }
                    ]
                }
            }
        }
        ConfigRow {
            uniform: true
            visible: page.kinds.includes("video") || page.kinds.includes("audio")
            ConfigTextRow {
                icon: "start"
                label: Translation.tr("Start at")
                placeholderText: "0:00"
                value: page.trimStart
                onEditingFinished: page.trimStart = value
            }
            ConfigTextRow {
                icon: "last_page"
                label: Translation.tr("End at")
                placeholderText: Translation.tr("the end")
                value: page.trimEnd
                onEditingFinished: page.trimEnd = value
            }
        }
        ConfigSpinBox {
            visible: page.kinds.includes("video")
            icon: "compress"
            text: Translation.tr("Fit into (MB, 0 = off)")
            from: 0
            to: 4000
            stepSize: 1
            value: page.targetSize
            onValueChanged: page.targetSize = value
        }
        ConfigSwitch {
            visible: page.kinds.includes("video")
            buttonIcon: "volume_off"
            text: Translation.tr("Remove sound")
            checked: page.removeAudio
            onCheckedChanged: page.removeAudio = checked
        }
        ContentSubsection {
            visible: page.kinds.includes("audio") || page.kinds.includes("video")
            title: Translation.tr("Audio bitrate")
            ConfigSelectionArray {
                currentValue: page.audioBitrate
                onSelected: newValue => page.audioBitrate = newValue
                options: [
                    { "displayName": Translation.tr("Automatic"), "value": "" },
                    { "displayName": "320k", "value": "320k" },
                    { "displayName": "192k", "value": "192k" },
                    { "displayName": "128k", "value": "128k" },
                    { "displayName": "96k", "value": "96k" }
                ]
            }
        }
        ContentSubsection {
            visible: page.kinds.includes("pdf")
            title: Translation.tr("Page images")
            ConfigSelectionArray {
                currentValue: page.pdfDpi
                onSelected: newValue => page.pdfDpi = newValue
                options: [
                    { "displayName": "100 dpi", "value": 100 },
                    { "displayName": "150 dpi", "value": 150 },
                    { "displayName": "300 dpi", "value": 300 }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Save to")
            RowLayout {
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: page.outDir.length > 0 ? page.outDir : Translation.tr("Next to each file")
                    color: Appearance.colors.colOnLayer1
                }
                DialogButton {
                    buttonText: Translation.tr("Choose folder")
                    enabled: !!page.caps["kdialog"]
                    onClicked: page.pickFolder()
                }
                DialogButton {
                    visible: page.outDir.length > 0
                    buttonText: Translation.tr("Next to files")
                    onClicked: page.outDir = ""
                }
            }
        }

        RowLayout {
            spacing: 8
            RippleButton {
                implicitHeight: 40
                leftPadding: 20
                rightPadding: 20
                enabled: !page.running
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: page.startConversion()
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: "transform"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: Translation.tr("Convert")
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
            DialogButton {
                visible: page.running
                buttonText: Translation.tr("Cancel")
                onClicked: {
                    page.queue = [];
                    job.cancel();
                }
            }
        }
    }

    ContentSection {
        visible: page.files.length > 0
        icon: "folder_zip"
        title: Translation.tr("Pack into an archive")
        description: Translation.tr("All files in the list, into one archive next to the first")

        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [["zip", "ZIP"], ["7z", "7z"], ["tar.gz", "tar.gz"], ["tar.zst", "tar.zst"]]
                delegate: DialogButton {
                    required property var modelData
                    buttonText: modelData[1]
                    enabled: !page.running && (modelData[0] === "7z" ? !!page.caps["7z"] : (!!page.caps["7z"] || !!page.caps["bsdtar"]))
                    onClicked: page.startPacking(modelData[0])
                }
            }
        }
    }
}
