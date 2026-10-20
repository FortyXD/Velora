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
 * Picks colors from the screen, shows them in other notations, keeps a history and
 * makes palettes from pictures.
 */
ContentPage {
    id: page

    property var caps: ({})
    property string current: "#7C83B9"
    property list<string> history: []
    property list<string> palette: []
    property string paletteSource: ""
    readonly property string historyPath: FileUtils.trimFileProtocol(`${Directories.state}/user/color_history.json`)
    readonly property var formats: page.notations(page.current)

    function addPaths(paths) {
        if (paths.length === 0) return;
        page.makePalette(decodeURIComponent(FileUtils.trimFileProtocol(`${paths[0]}`)));
    }

    function makePalette(path) {
        page.paletteSource = path;
        page.palette = [];
        paletteJob.start(["palette", path, "--colors", "8"]);
    }

    function setColor(text) {
        const color = page.parseColor(text);
        if (color) page.current = color;
        return color !== null;
    }

    // Accepts #RGB, #RRGGBB, rgb(…) and bare hex
    function parseColor(text) {
        const value = `${text}`.trim();
        let match = value.match(/^#?([0-9a-f]{6})$/i);
        if (match) return `#${match[1].toUpperCase()}`;
        match = value.match(/^#?([0-9a-f])([0-9a-f])([0-9a-f])$/i);
        if (match) return `#${match[1]}${match[1]}${match[2]}${match[2]}${match[3]}${match[3]}`.toUpperCase();
        match = value.match(/^rgba?\(\s*(\d{1,3})[\s,]+(\d{1,3})[\s,]+(\d{1,3})/i);
        if (match) return page.toHex([match[1], match[2], match[3]].map(Number));
        return null;
    }

    function toHex(rgb) {
        return "#" + rgb.map(channel => Math.max(0, Math.min(255, Math.round(channel))).toString(16).padStart(2, "0")).join("").toUpperCase();
    }

    function notations(hex) {
        const rgb = [1, 3, 5].map(start => parseInt(hex.substr(start, 2), 16));
        const [r, g, b] = rgb.map(channel => channel / 255);

        const max = Math.max(r, g, b), min = Math.min(r, g, b);
        const lightness = (max + min) / 2;
        const delta = max - min;
        const saturation = delta === 0 ? 0 : delta / (1 - Math.abs(2 * lightness - 1));
        let hue = 0;
        if (delta !== 0) {
            if (max === r) hue = 60 * (((g - b) / delta) % 6);
            else if (max === g) hue = 60 * ((b - r) / delta + 2);
            else hue = 60 * ((r - g) / delta + 4);
        }
        if (hue < 0) hue += 360;

        // OKLCH: sRGB → linear → LMS → OKLab → polar
        const linear = [r, g, b].map(c => c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
        const l = Math.cbrt(0.4122214708 * linear[0] + 0.5363325363 * linear[1] + 0.0514459929 * linear[2]);
        const m = Math.cbrt(0.2119034982 * linear[0] + 0.6806995451 * linear[1] + 0.1073969566 * linear[2]);
        const s = Math.cbrt(0.0883024619 * linear[0] + 0.2817188376 * linear[1] + 0.6299787005 * linear[2]);
        const okL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
        const okA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
        const okB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
        const chroma = Math.sqrt(okA * okA + okB * okB);
        let okHue = Math.atan2(okB, okA) * 180 / Math.PI;
        if (okHue < 0) okHue += 360;

        return [
            { "name": "HEX", "value": hex },
            { "name": "RGB", "value": `rgb(${rgb.join(", ")})` },
            { "name": "HSL", "value": `hsl(${Math.round(hue)}, ${Math.round(saturation * 100)}%, ${Math.round(lightness * 100)}%)` },
            { "name": "OKLCH", "value": `oklch(${(okL * 100).toFixed(1)}% ${chroma.toFixed(3)} ${okHue.toFixed(1)})` },
            { "name": "Qt", "value": `Qt.rgba(${[r, g, b].map(c => c.toFixed(3)).join(", ")}, 1)` },
        ];
    }

    ToolboxJob {
        id: paletteJob
        onEvent: data => {
            if (data.event === "done") page.palette = data.colors;
        }
    }

    FileView {
        path: page.historyPath
        watchChanges: true
        printErrors: false // There's no history until the first pick
        onFileChanged: reload()
        onLoaded: {
            try {
                page.history = JSON.parse(text()).filter(color => /^#[0-9A-F]{6}$/i.test(color));
            } catch (e) {
                page.history = [];
            }
        }
        onLoadFailed: page.history = []
    }

    Process {
        id: pickProc
        command: ["bash", Quickshell.shellPath("scripts/colors/pick-color.sh")]
        stdout: StdioCollector {
            onStreamFinished: page.setColor(text)
        }
    }
    Process {
        id: pickFileProc
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) page.makePalette(path);
            }
        }
    }

    component Swatch: RippleButton {
        id: swatch
        required property string color
        property bool selected: page.current === swatch.color
        implicitWidth: 44
        implicitHeight: 44
        buttonRadius: Appearance.rounding.small
        colBackground: swatch.color
        colBackgroundHover: ColorUtils.mix(swatch.color, Appearance.colors.colOnLayer1, 0.85)
        colRipple: ColorUtils.mix(swatch.color, Appearance.colors.colOnLayer1, 0.7)
        onClicked: page.current = swatch.color
        StyledToolTip {
            text: swatch.color
        }
        Rectangle {
            anchors.fill: parent
            radius: swatch.buttonRadius
            color: "transparent"
            border.width: swatch.selected ? 3 : 1
            border.color: swatch.selected ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
        }
    }

    ContentSection {
        icon: "colorize"
        title: Translation.tr("Color")
        description: Translation.tr("Pick one on the screen or type it in")

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Rectangle {
                implicitWidth: 140
                implicitHeight: 140
                radius: Appearance.rounding.normal
                color: page.current
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "colorize"
                    iconSize: 32
                    color: ColorUtils.isDark(page.current) ? "white" : "black"
                    opacity: pickArea.containsMouse ? 0.9 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
                MouseArea {
                    id: pickArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pickProc.running = true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: page.formats
                    delegate: RowLayout {
                        id: formatRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        StyledText {
                            Layout.preferredWidth: 56
                            text: formatRow.modelData.name
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: formatRow.modelData.value
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            onClicked: Quickshell.clipboardText = formatRow.modelData.value
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "content_copy"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledToolTip {
                                text: Translation.tr("Copy")
                            }
                        }
                    }
                }
            }
        }

        ConfigTextRow {
            id: colorField
            icon: "tag"
            label: Translation.tr("Color code")
            placeholderText: "#7C83B9 · rgb(124, 131, 185)"
            monospace: true
            onEditingFinished: {
                if (page.setColor(value)) value = "";
            }
        }

        RowLayout {
            spacing: 6
            DialogButton {
                buttonText: Translation.tr("Pick on the screen")
                enabled: !!page.caps["hyprpicker"] && !pickProc.running
                onClicked: pickProc.running = true
            }
            DialogButton {
                buttonText: Translation.tr("Make it the accent")
                onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--color", page.current, "--noswitch"])
            }
            DialogButton {
                buttonText: Translation.tr("Back to wallpaper colors")
                onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--color", "clear", "--noswitch"])
            }
        }
        StyledText {
            visible: !page.caps["hyprpicker"]
            text: Translation.tr("Needs hyprpicker: sudo pacman -S hyprpicker")
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    ContentSection {
        icon: "history"
        title: Translation.tr("Recent colors")
        description: page.history.length > 0 ? Translation.tr("Colors picked with the eyedropper, here or with Super+Shift+C")
            : Translation.tr("Colors you pick on the screen show up here")

        Flow {
            visible: page.history.length > 0
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: page.history
                delegate: Swatch {
                    required property string modelData
                    color: modelData
                }
            }
        }
        DialogButton {
            visible: page.history.length > 0
            buttonText: Translation.tr("Clear history")
            onClicked: Quickshell.execDetached(["bash", "-c", 'echo "[]" > "$1"', "_", page.historyPath])
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Palette from a picture")
        description: Translation.tr("Drop an image here, pick one, or use the wallpaper")

        DropArea {
            Layout.fillWidth: true
            implicitHeight: paletteColumn.implicitHeight + 32
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
                id: paletteColumn
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 10
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: page.paletteSource.length > 0 ? page.paletteSource.split("/").pop() : Translation.tr("Drop a picture")
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: parent.width
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    DialogButton {
                        buttonText: Translation.tr("Choose file")
                        enabled: !!page.caps["kdialog"]
                        onClicked: {
                            pickFileProc.command = ["kdialog", "--getopenfilename", Directories.pictures, "image/png image/jpeg image/webp image/avif image/gif"];
                            pickFileProc.running = true;
                        }
                    }
                    DialogButton {
                        buttonText: Translation.tr("Use the wallpaper")
                        enabled: Config.options.background.wallpaperPath.length > 0
                        onClicked: page.makePalette(Config.options.background.wallpaperPath)
                    }
                }
                StyledIndeterminateProgressBar {
                    visible: paletteJob.running
                    Layout.fillWidth: true
                }
                Flow {
                    visible: page.palette.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    Repeater {
                        model: page.palette
                        delegate: Swatch {
                            required property string modelData
                            color: modelData
                            implicitWidth: 56
                            implicitHeight: 56
                        }
                    }
                }
                DialogButton {
                    visible: page.palette.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    buttonText: Translation.tr("Copy all as HEX")
                    onClicked: Quickshell.clipboardText = page.palette.join(" ")
                }
            }
        }
    }
}
