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
 * Makes QR codes from text and reads them from the screen, an image file or the clipboard.
 */
ContentPage {
    id: page

    property var caps: ({})
    readonly property string workDir: "/tmp/quickshell/toolbox"
    property string text: ""
    property string imagePath: ""
    property int imageVersion: 0
    property string scanned: ""
    property string scanError: ""
    readonly property bool scannedIsLink: /^https?:\/\//i.test(scanned.trim())
    readonly property var wifi: {
        // WIFI:T:WPA;S:name;P:password;; (fields in any order, \ escapes)
        const match = scanned.trim().match(/^WIFI:(.*)$/i);
        if (!match) return null;
        let fields = {};
        for (const part of match[1].split(/(?<!\\);/)) {
            const pair = part.match(/^([TSPH]):(.*)$/i);
            if (pair) fields[pair[1].toUpperCase()] = pair[2].replace(/\\([\\;,:"])/g, "$1");
        }
        return fields.S ? fields : null;
    }

    function generate() {
        if (page.text.trim().length === 0) return;
        makeJob.start(["qr-encode", page.text, "--out", `${page.workDir}/qr.png`, "--size", "12"]);
    }

    // Files from the Dolphin menu or a drop are scanned for codes
    function addPaths(paths) {
        if (paths.length > 0) page.scanFile(decodeURIComponent(FileUtils.trimFileProtocol(`${paths[0]}`)));
    }

    function scanFile(path) {
        page.scanned = "";
        page.scanError = "";
        scanJob.start(["qr-scan", path]);
    }

    ToolboxJob {
        id: makeJob
        onEvent: data => {
            if (data.event === "done") {
                page.imagePath = data.output;
                page.imageVersion += 1;
            }
        }
    }

    ToolboxJob {
        id: scanJob
        onEvent: data => {
            if (data.event === "done") page.scanned = data.output;
            else if (data.event === "error") page.scanError = Translation.tr("No QR code found");
        }
    }

    // Grabbing an area of the screen, a picked file or the clipboard image into a file to scan
    Process {
        id: grabProc
        onExited: exitCode => {
            if (exitCode === 0) page.scanFile(`${page.workDir}/scan.png`);
        }
    }
    Process {
        id: pickProc
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) page.scanFile(path);
            }
        }
    }
    Process {
        id: saveProc
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) Quickshell.execDetached(["cp", "--", page.imagePath, path]);
            }
        }
    }

    ContentSection {
        icon: "qr_code_2"
        title: Translation.tr("Make a QR code")
        description: Translation.tr("From a link, text or Wi-Fi details")

        ConfigTextRow {
            id: textField
            icon: "edit_note"
            label: Translation.tr("Text or link")
            value: page.text
            onEditingFinished: {
                page.text = value;
                page.generate();
            }
        }
        RowLayout {
            spacing: 6
            DialogButton {
                buttonText: Translation.tr("Use the clipboard")
                onClicked: {
                    page.text = Quickshell.clipboardText;
                    textField.value = page.text;
                    page.generate();
                }
            }
            DialogButton {
                buttonText: Translation.tr("Make")
                enabled: page.text.trim().length > 0 && !!page.caps["qrencode"]
                onClicked: page.generate()
            }
        }
        StyledText {
            visible: !page.caps["qrencode"]
            text: Translation.tr("Needs qrencode: sudo pacman -S qrencode")
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        RowLayout {
            visible: page.imagePath.length > 0
            spacing: 16
            Rectangle {
                implicitWidth: 220
                implicitHeight: 220
                radius: Appearance.rounding.normal
                color: "white"
                Image {
                    anchors.fill: parent
                    anchors.margins: 8
                    source: page.imagePath.length > 0 ? `file://${page.imagePath}?v=${page.imageVersion}` : ""
                    cache: false
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                }
            }
            ColumnLayout {
                spacing: 6
                DialogButton {
                    buttonText: Translation.tr("Copy the image")
                    onClicked: Quickshell.execDetached(["bash", "-c", 'wl-copy --type image/png < "$1"', "_", page.imagePath])
                }
                DialogButton {
                    buttonText: Translation.tr("Save as…")
                    enabled: !!page.caps["kdialog"]
                    onClicked: {
                        saveProc.command = ["kdialog", "--getsavefilename", `${Directories.pictures}/qr.png`, "image/png"];
                        saveProc.running = true;
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "qr_code_scanner"
        title: Translation.tr("Read a QR code")
        description: Translation.tr("Select it on the screen, or take it from an image")

        RowLayout {
            spacing: 6
            DialogButton {
                buttonText: Translation.tr("From the screen")
                enabled: !!page.caps["zbarimg"] && !!page.caps["grim"] && !!page.caps["slurp"]
                onClicked: {
                    grabProc.command = ["bash", "-c", 'mkdir -p "$1" && area=$(slurp) && grim -g "$area" "$1/scan.png"', "_", page.workDir];
                    grabProc.running = true;
                }
            }
            DialogButton {
                buttonText: Translation.tr("From a file")
                enabled: !!page.caps["zbarimg"] && !!page.caps["kdialog"]
                onClicked: {
                    pickProc.command = ["kdialog", "--getopenfilename", Directories.pictures, "image/png image/jpeg image/webp image/bmp"];
                    pickProc.running = true;
                }
            }
            DialogButton {
                buttonText: Translation.tr("From the clipboard")
                enabled: !!page.caps["zbarimg"]
                onClicked: {
                    grabProc.command = ["bash", "-c", 'mkdir -p "$1" && wl-paste --type image/png > "$1/scan.png"', "_", page.workDir];
                    grabProc.running = true;
                }
            }
        }
        StyledText {
            visible: !page.caps["zbarimg"]
            text: Translation.tr("Needs zbar: sudo pacman -S zbar")
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            visible: page.scanError.length > 0
            text: page.scanError
            color: Appearance.colors.colError
        }

        ColumnLayout {
            visible: page.scanned.length > 0
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: scannedText.implicitHeight + 20
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                StyledText {
                    id: scannedText
                    anchors {
                        fill: parent
                        margins: 10
                    }
                    wrapMode: Text.WrapAnywhere
                    text: page.wifi ? Translation.tr("Wi-Fi network “%1”").arg(page.wifi.S) : page.scanned
                    color: Appearance.colors.colOnLayer2
                }
            }
            RowLayout {
                spacing: 6
                DialogButton {
                    buttonText: Translation.tr("Copy")
                    onClicked: Quickshell.clipboardText = page.wifi ? (page.wifi.P ?? "") : page.scanned
                }
                DialogButton {
                    visible: page.scannedIsLink
                    buttonText: Translation.tr("Open the link")
                    onClicked: Qt.openUrlExternally(page.scanned.trim())
                }
                DialogButton {
                    visible: page.wifi !== null
                    buttonText: Translation.tr("Connect")
                    onClicked: Network.joinNetwork(page.wifi.S, page.wifi.P ?? "")
                }
            }
        }
    }
}
