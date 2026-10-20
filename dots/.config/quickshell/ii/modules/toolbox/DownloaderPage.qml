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
 * Downloads video or music from a link with yt-dlp.
 */
ContentPage {
    id: page

    property var caps: ({})
    readonly property bool available: !!caps["yt-dlp"]
    property string url: ""
    property string mode: "video"
    property string quality: "1080"
    property string audioFormat: "mp3"
    property bool subtitles: false
    property bool playlist: false
    property var info: null // { title, duration, uploader } or { error }
    property int percent: -1
    property string speed: ""
    property string eta: ""
    property string status: ""
    property string error: ""
    property list<var> finished: [] // Saved file paths, newest first
    readonly property string downloadDir: Config.options.toolbox.downloadDir.length > 0
        ? Config.options.toolbox.downloadDir : `${FileUtils.trimFileProtocol(Directories.videos)}/Downloads`

    // A link handed over by the launcher or open.sh
    function addPaths(paths) {
        const link = paths.map(path => `${path}`.trim()).find(path => /^https?:\/\//i.test(path));
        if (!link) return;
        page.url = link;
        urlField.value = link;
        page.lookUp();
    }

    function proxyArgs() {
        return Config.options.toolbox.proxy.trim().length > 0 ? ["--proxy", Config.options.toolbox.proxy.trim()] : [];
    }

    function lookUp() {
        if (page.url.trim().length === 0) return;
        page.info = null;
        infoJob.start(["info", page.url.trim(), ...page.proxyArgs()]);
    }

    function download() {
        if (page.url.trim().length === 0 || job.running) return;
        page.error = "";
        page.percent = 0;
        page.status = "";
        job.start(["download", page.url.trim(), "--mode", page.mode, "--quality", page.quality, "--audio-format", page.audioFormat,
            "--out-dir", page.downloadDir, ...(page.subtitles ? ["--subs"] : []), ...(page.playlist ? ["--playlist"] : []), ...page.proxyArgs()]);
    }

    function revealInFiles(path) {
        Quickshell.execDetached(["dbus-send", "--session", "--dest=org.freedesktop.FileManager1", "--type=method_call",
            "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems", `array:string:file://${path}`, "string:"]);
    }

    ToolboxJob {
        id: infoJob
        onEvent: data => {
            if (data.event === "info") page.info = data;
            else if (data.event === "error") page.info = { "error": data.message };
        }
    }

    ToolboxJob {
        id: job
        onEvent: data => {
            if (data.event === "progress") {
                page.percent = data.percent;
                page.speed = data.speed ?? "";
                page.eta = data.eta ?? "";
            } else if (data.event === "status") {
                page.status = data.message.replace(/^\[[^\]]+\]\s*/, "");
            } else if (data.event === "done") {
                page.finished = [data.output, ...page.finished];
                page.percent = -1;
            } else if (data.event === "error") {
                page.error = data.message;
                page.percent = -1;
            }
        }
        onFinishedAll: page.percent = -1
    }

    Process {
        id: pickFolder
        stdout: StdioCollector {
            onStreamFinished: {
                const folder = text.trim();
                if (folder.length > 0) Config.options.toolbox.downloadDir = folder;
            }
        }
    }

    ContentSection {
        visible: !page.available
        icon: "error"
        title: Translation.tr("yt-dlp is not installed")
        description: Translation.tr("Install it with: sudo pacman -S yt-dlp")
    }

    ContentSection {
        icon: "link"
        title: Translation.tr("Link")
        description: Translation.tr("A video, a playlist or a track from YouTube, VK, Rutube and many other sites")

        ConfigTextRow {
            id: urlField
            icon: "link"
            label: Translation.tr("Address")
            placeholderText: "https://…"
            value: page.url
            onEditingFinished: {
                page.url = value.trim();
                page.lookUp();
            }
        }
        RowLayout {
            spacing: 6
            DialogButton {
                buttonText: Translation.tr("Paste from clipboard")
                onClicked: {
                    page.url = Quickshell.clipboardText.trim();
                    urlField.value = page.url;
                    page.lookUp();
                }
            }
            DialogButton {
                buttonText: Translation.tr("Look up")
                enabled: page.available && page.url.length > 0 && !infoJob.running
                onClicked: page.lookUp()
            }
            StyledIndeterminateProgressBar {
                visible: infoJob.running
                Layout.preferredWidth: 120
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: page.info !== null
            wrapMode: Text.Wrap
            text: page.info?.error ? page.info.error
                : [page.info?.title, page.info?.uploader, page.info?.duration].filter(part => part && part !== "NA").join(" · ")
            color: page.info?.error ? Appearance.colors.colError : Appearance.colors.colOnLayer1
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("What to save")

        ContentSubsection {
            title: Translation.tr("Kind")
            ConfigSelectionArray {
                currentValue: page.mode
                onSelected: newValue => page.mode = newValue
                options: [
                    { "displayName": Translation.tr("Video"), "icon": "movie", "value": "video" },
                    { "displayName": Translation.tr("Sound only"), "icon": "music_note", "value": "audio" }
                ]
            }
        }
        ContentSubsection {
            visible: page.mode === "video"
            title: Translation.tr("Highest quality")
            ConfigSelectionArray {
                currentValue: page.quality
                onSelected: newValue => page.quality = newValue
                options: ["2160", "1440", "1080", "720", "480", "360"].map(height => ({ "displayName": `${height}p`, "value": height }))
            }
        }
        ContentSubsection {
            visible: page.mode === "audio"
            title: Translation.tr("Format")
            ConfigSelectionArray {
                currentValue: page.audioFormat
                onSelected: newValue => page.audioFormat = newValue
                options: [["mp3", "MP3"], ["opus", "Opus"], ["m4a", "M4A"], ["flac", "FLAC"]].map(entry => ({ "displayName": entry[1], "value": entry[0] }))
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "subtitles"
                text: Translation.tr("Subtitles")
                description: Translation.tr("Russian and English, built into the video")
                checked: page.subtitles
                onCheckedChanged: page.subtitles = checked
            }
            ConfigSwitch {
                buttonIcon: "playlist_play"
                text: Translation.tr("Whole playlist")
                checked: page.playlist
                onCheckedChanged: page.playlist = checked
            }
        }
        ConfigTextRow {
            icon: "vpn_lock"
            label: Translation.tr("Proxy (optional)")
            description: Translation.tr("For sites that are blocked or slowed down, e.g. socks5://127.0.0.1:1080")
            placeholderText: "socks5://127.0.0.1:1080"
            value: Config.options.toolbox.proxy
            onEditingFinished: Config.options.toolbox.proxy = value.trim()
        }
        ContentSubsection {
            title: Translation.tr("Save to")
            RowLayout {
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: page.downloadDir
                    color: Appearance.colors.colOnLayer1
                }
                DialogButton {
                    buttonText: Translation.tr("Choose folder")
                    enabled: !!page.caps["kdialog"]
                    onClicked: {
                        pickFolder.command = ["kdialog", "--getexistingdirectory", page.downloadDir];
                        pickFolder.running = true;
                    }
                }
            }
        }

        RowLayout {
            spacing: 8
            RippleButton {
                implicitHeight: 40
                leftPadding: 20
                rightPadding: 20
                enabled: page.available && page.url.length > 0 && !job.running
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: page.download()
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: "download"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: Translation.tr("Download")
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
            DialogButton {
                visible: job.running
                buttonText: Translation.tr("Cancel")
                onClicked: job.cancel()
            }
        }

        ColumnLayout {
            visible: job.running
            Layout.fillWidth: true
            spacing: 4
            StyledProgressBar {
                Layout.fillWidth: true
                value: Math.max(0, page.percent) / 100
            }
            StyledText {
                text: [page.percent >= 0 ? `${page.percent}%` : "", page.speed, page.eta ? Translation.tr("%1 left").arg(page.eta) : "", page.status]
                    .filter(part => part && part.length > 0).join(" · ")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: page.error.length > 0
            wrapMode: Text.Wrap
            text: page.error
            color: Appearance.colors.colError
        }
    }

    ContentSection {
        visible: page.finished.length > 0
        icon: "download_done"
        title: Translation.tr("Downloaded")

        Repeater {
            model: page.finished
            delegate: RowLayout {
                required property string modelData
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "check_circle"
                    iconSize: 20
                    fill: 1
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: parent.modelData.split("/").pop()
                    color: Appearance.colors.colOnLayer1
                }
                DialogButton {
                    buttonText: Translation.tr("Show")
                    onClicked: page.revealInFiles(parent.modelData)
                }
            }
        }
    }
}
