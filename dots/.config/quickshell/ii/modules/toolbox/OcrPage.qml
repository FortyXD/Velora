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
 * Recognizes text in an image or a PDF with tesseract, or in a part of the screen.
 */
ContentPage {
    id: page

    property var caps: ({})
    readonly property string workDir: "/tmp/quickshell/toolbox"
    property string file: ""
    property string language: "eng+rus"
    property string result: ""
    property string usedLanguage: ""
    property string error: ""
    property string searchablePdf: ""
    property int percent: -1

    function addPaths(paths) {
        if (paths.length === 0) return;
        page.file = decodeURIComponent(FileUtils.trimFileProtocol(`${paths[0]}`));
        page.recognize();
    }

    function recognize() {
        if (page.file.length === 0) return;
        page.result = "";
        page.error = "";
        page.searchablePdf = "";
        job.start(["ocr", page.file, "--lang", page.language]);
    }

    function makePdf() {
        if (page.file.length === 0) return;
        pdfJob.start(["ocr", page.file, "--lang", page.language, "--pdf"]);
    }

    function revealInFiles(path) {
        Quickshell.execDetached(["dbus-send", "--session", "--dest=org.freedesktop.FileManager1", "--type=method_call",
            "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems", `array:string:file://${path}`, "string:"]);
    }

    ToolboxJob {
        id: job
        onEvent: data => {
            if (data.event === "progress") page.percent = data.percent;
            else if (data.event === "done") {
                page.result = data.text;
                page.usedLanguage = data.language;
                page.percent = -1;
                if (data.text.length === 0) page.error = Translation.tr("No text found");
            } else if (data.event === "error") {
                page.error = data.message;
                page.percent = -1;
            }
        }
    }

    ToolboxJob {
        id: pdfJob
        onEvent: data => {
            if (data.event === "done") page.searchablePdf = data.output;
            else if (data.event === "error") page.error = data.message;
        }
    }

    Process {
        id: grabProc
        onExited: exitCode => {
            if (exitCode !== 0) return;
            page.file = `${page.workDir}/ocr.png`;
            page.recognize();
        }
    }
    Process {
        id: pickProc
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) page.addPaths([path]);
            }
        }
    }
    Process {
        id: saveProc
        property string content: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) Quickshell.execDetached(["bash", "-c", 'printf "%s\\n" "$2" > "$1"', "_", path, saveProc.content]);
            }
        }
    }

    ContentSection {
        icon: "document_scanner"
        title: Translation.tr("Picture or PDF")
        description: Translation.tr("Drop a file here, pick one, or select text on the screen")

        DropArea {
            Layout.fillWidth: true
            implicitHeight: 110
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
                anchors.centerIn: parent
                spacing: 8
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: page.file.length > 0 ? page.file.split("/").pop() : Translation.tr("Drop an image or a PDF")
                    color: Appearance.colors.colOnLayer2
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    DialogButton {
                        buttonText: Translation.tr("Choose file")
                        enabled: !!page.caps["kdialog"]
                        onClicked: {
                            pickProc.command = ["kdialog", "--getopenfilename", Directories.pictures, "image/png image/jpeg image/webp image/tiff application/pdf"];
                            pickProc.running = true;
                        }
                    }
                    DialogButton {
                        buttonText: Translation.tr("From the screen")
                        enabled: !!page.caps["grim"] && !!page.caps["slurp"]
                        onClicked: {
                            grabProc.command = ["bash", "-c", 'mkdir -p "$1" && area=$(slurp) && grim -g "$area" "$1/ocr.png"', "_", page.workDir];
                            grabProc.running = true;
                        }
                    }
                    DialogButton {
                        buttonText: Translation.tr("From the clipboard")
                        onClicked: {
                            grabProc.command = ["bash", "-c", 'mkdir -p "$1" && wl-paste --type image/png > "$1/ocr.png"', "_", page.workDir];
                            grabProc.running = true;
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Language")
            ConfigSelectionArray {
                currentValue: page.language
                onSelected: newValue => {
                    page.language = newValue;
                    page.recognize();
                }
                options: [
                    { "displayName": Translation.tr("Russian and English"), "value": "eng+rus" },
                    { "displayName": Translation.tr("Russian"), "value": "rus" },
                    { "displayName": Translation.tr("English"), "value": "eng" }
                ]
            }
        }
        StyledText {
            visible: !page.caps["tesseract"]
            text: Translation.tr("Needs tesseract: sudo pacman -S tesseract tesseract-data-eng tesseract-data-rus")
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            visible: page.usedLanguage.length > 0 && page.language.includes("rus") && !page.usedLanguage.includes("rus")
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("Russian isn't installed for tesseract, so only English was read. Install it with: sudo pacman -S tesseract-data-rus")
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    ContentSection {
        visible: job.running || page.result.length > 0 || page.error.length > 0
        icon: "text_fields"
        title: Translation.tr("Text")

        StyledProgressBar {
            visible: job.running && page.percent > 0
            Layout.fillWidth: true
            value: page.percent / 100
        }
        StyledIndeterminateProgressBar {
            visible: job.running && page.percent <= 0
            Layout.fillWidth: true
        }
        StyledText {
            visible: page.error.length > 0
            text: page.error
            color: Appearance.colors.colError
        }
        Rectangle {
            visible: page.result.length > 0
            Layout.fillWidth: true
            implicitHeight: Math.min(resultArea.implicitHeight + 20, 420)
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            StyledFlickable {
                anchors.fill: parent
                anchors.margins: 10
                contentHeight: resultArea.implicitHeight
                clip: true
                TextEdit {
                    id: resultArea
                    width: parent.width
                    text: page.result
                    readOnly: false
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    color: Appearance.colors.colOnLayer2
                    selectionColor: Appearance.colors.colPrimaryContainer
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
        RowLayout {
            visible: page.result.length > 0
            spacing: 6
            DialogButton {
                buttonText: Translation.tr("Copy")
                onClicked: Quickshell.clipboardText = resultArea.text
            }
            DialogButton {
                buttonText: Translation.tr("Save as text…")
                enabled: !!page.caps["kdialog"]
                onClicked: {
                    saveProc.content = resultArea.text;
                    saveProc.command = ["kdialog", "--getsavefilename", `${Directories.documents}/text.txt`, "text/plain"];
                    saveProc.running = true;
                }
            }
            DialogButton {
                buttonText: Translation.tr("Make a searchable PDF")
                enabled: !pdfJob.running
                onClicked: page.makePdf()
            }
            DialogButton {
                visible: page.searchablePdf.length > 0
                buttonText: Translation.tr("Show the PDF")
                onClicked: page.revealInFiles(page.searchablePdf)
            }
        }
    }
}
