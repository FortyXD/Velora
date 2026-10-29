import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    property var recordingSources: []
    function sourceChoices(monitor, selected) {
        let choices = [{ value: "", displayName: Translation.tr("Follow system default"), icon: "settings_suggest" }];
        for (const source of recordingSources) {
            if (source.monitor === monitor) choices.push({ value: source.value, displayName: source.displayName, icon: monitor ? "speaker" : "mic" });
        }
        if (selected && !choices.some(item => item.value === selected))
            choices.push({ value: selected, displayName: Translation.tr("Unavailable device: %1").arg(selected), icon: "warning" });
        return choices;
    }
    Process {
        id: sourceProcess
        command: [Directories.recordScriptPath, "sources"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.recordingSources = JSON.parse(text); }
                catch (e) { root.recordingSources = []; }
            }
        }
    }

    function folderUrl(path) {
        return path.length > 0 ? `file://${path.replace(/^~/, FileUtils.trimFileProtocol(Directories.home))}` : Directories.home;
    }

    FolderDialog {
        id: folderDialog
        property var onPicked: null
        onAccepted: if (folderDialog.onPicked) folderDialog.onPicked(FileUtils.trimFileProtocol(decodeURIComponent(selectedFolder.toString())))
    }
    function pickFolder(current, callback) {
        folderDialog.currentFolder = root.folderUrl(current);
        folderDialog.onPicked = callback;
        folderDialog.open();
    }

    FileDialog {
        id: imageDialog
        nameFilters: [Translation.tr("Images (*.png *.jpg *.jpeg *.gif *.webp *.svg)"), Translation.tr("All files (*)")]
        onAccepted: Config.options.overlay.floatingImage.imageSource = FileUtils.trimFileProtocol(decodeURIComponent(selectedFile.toString()))
    }

    ContentSection {
        icon: "screenshot_frame_2"
        title: Translation.tr("Screen selection")
        description: Translation.tr("Used for screenshots, recording a region and Google Lens")

        ContentSubsection {
            title: Translation.tr("Hint target regions")
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "select_window"
                    text: Translation.tr('Windows')
                    checked: Config.options.regionSelector.targetRegions.windows
                    onCheckedChanged: {
                        Config.options.regionSelector.targetRegions.windows = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "right_panel_open"
                    text: Translation.tr('Layers')
                    checked: Config.options.regionSelector.targetRegions.layers
                    onCheckedChanged: {
                        Config.options.regionSelector.targetRegions.layers = checked;
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "nearby"
                text: Translation.tr('Content')
                description: Translation.tr("Could be images or parts of the screen that have some containment. Might not always be accurate. This is done with an image processing algorithm run locally and no AI is used.")
                checked: Config.options.regionSelector.targetRegions.content
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.content = checked;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Google Lens")
            ConfigSelectionArray {
                currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                onSelected: newValue => {
                    Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                }
                options: [
                    { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular selection") },
                    { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "point_scan"
            text: Translation.tr("Show aim lines")
            description: Translation.tr("For rectangular selection")
            checked: Config.options.regionSelector.rect.showAimLines
            onCheckedChanged: {
                Config.options.regionSelector.rect.showAimLines = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Circle selection")
            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "eraser_size_3"
                    text: Translation.tr("Stroke width")
                    value: Config.options.regionSelector.circle.strokeWidth
                    from: 1
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.regionSelector.circle.strokeWidth = value;
                    }
                }
                ConfigSpinBox {
                    icon: "screenshot_frame_2"
                    text: Translation.tr("Padding")
                    value: Config.options.regionSelector.circle.padding
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.options.regionSelector.circle.padding = value;
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "videocam"
        title: Translation.tr("Screen recording")
        description: Translation.tr("Applies to the recording button. Explicit region, screen and sound shortcuts override only their own mode. Changes apply to the next recording.")

        ContentSubsection {
            title: Translation.tr("Capture area")
            description: Translation.tr("Screen records the focused monitor. Region lets you select an area; Esc cancels.")
            ConfigSelectionArray {
                currentValue: Config.options.screenRecord.mode
                onSelected: value => Config.options.screenRecord.mode = value
                options: [
                    { value: "region", displayName: Translation.tr("Region"), icon: "screenshot_region" },
                    { value: "screen", displayName: Translation.tr("Focused screen"), icon: "desktop_windows" }
                ]
            }
        }
        ContentSubsection {
            title: Translation.tr("Recording audio")
            description: Translation.tr("Microphone is used only when explicitly selected. System sound follows the playback device at the start; changing devices mid-recording is not supported.")
            ConfigSelectionArray {
                currentValue: Config.options.screenRecord.audio
                onSelected: value => Config.options.screenRecord.audio = value
                options: [
                    { value: "none", displayName: Translation.tr("Silent"), icon: "volume_off" },
                    { value: "system", displayName: Translation.tr("System sound"), icon: "speaker" },
                    { value: "microphone", displayName: Translation.tr("Microphone only"), icon: "mic" },
                    { value: "both", displayName: Translation.tr("System + microphone"), icon: "mic_external_on" }
                ]
            }
        }
        ContentSubsection {
            visible: ["system", "both"].includes(Config.options.screenRecord.audio)
            title: Translation.tr("System audio device")
            ConfigSelectionArray {
                currentValue: Config.options.screenRecord.systemSource
                options: root.sourceChoices(true, Config.options.screenRecord.systemSource)
                onSelected: value => Config.options.screenRecord.systemSource = value
            }
        }
        ContentSubsection {
            visible: ["microphone", "both"].includes(Config.options.screenRecord.audio)
            title: Translation.tr("Microphone device")
            ConfigSelectionArray {
                currentValue: Config.options.screenRecord.microphoneSource
                options: root.sourceChoices(false, Config.options.screenRecord.microphoneSource)
                onSelected: value => Config.options.screenRecord.microphoneSource = value
            }
        }
        ConfigNavRow {
            buttonIcon: "refresh"
            title: Translation.tr("Refresh audio devices")
            description: Translation.tr("A disconnected selected device causes an error, never a silent fallback.")
            onClicked: sourceProcess.running = true
        }
        ContentSubsection {
            title: Translation.tr("Frame rate")
            description: Translation.tr("60 FPS is smoother but uses more CPU and disk space. 30 FPS is recommended for everyday recording.")
            ConfigSelectionArray {
                currentValue: Config.options.screenRecord.fps
                onSelected: value => Config.options.screenRecord.fps = value
                options: [ { value: 30, displayName: "30 FPS" }, { value: 60, displayName: "60 FPS" } ]
            }
        }
        ContentSubsection {
            title: Translation.tr("Video quality")
            description: Translation.tr("H.264 software encoding. Higher quality means larger files; all modes use the same fast encoder preset.")
            ConfigSelectionArray {
                currentValue: Config.options.screenRecord.quality
                onSelected: value => Config.options.screenRecord.quality = value
                options: [
                    { value: "high", displayName: Translation.tr("High quality (CRF 18)") },
                    { value: "balanced", displayName: Translation.tr("Balanced (CRF 23)") },
                    { value: "small", displayName: Translation.tr("Smaller files (CRF 28)") }
                ]
            }
        }
        ContentSubsection {
            title: Translation.tr("Recording format")
            description: Translation.tr("MP4 is widely compatible. MKV is more resilient to interrupted recording. Always stop normally to finish saving.")
            ConfigSelectionArray {
                currentValue: Config.options.screenRecord.format
                onSelected: value => Config.options.screenRecord.format = value
                options: [ { value: "mp4", displayName: "MP4" }, { value: "mkv", displayName: "MKV" } ]
            }
        }
        ContentSubsection {
            title: Translation.tr("Start delay")
            description: Translation.tr("Starts after area selection. Press the recording button again to cancel the countdown.")
            ConfigSelectionArray {
                currentValue: Config.options.screenRecord.delay
                onSelected: value => Config.options.screenRecord.delay = value
                options: [
                    { value: 0, displayName: Translation.tr("No delay") },
                    { value: 3, displayName: Translation.tr("3 seconds") },
                    { value: 5, displayName: Translation.tr("5 seconds") },
                    { value: 10, displayName: Translation.tr("10 seconds") }
                ]
            }
        }
        ConfigNavRow {
            buttonIcon: "folder"
            title: Translation.tr("Recording folder")
            description: ScreenRecorder.savePath
            trailingIcon: "folder_open"
            onClicked: root.pickFolder(ScreenRecorder.savePath, path => Config.options.screenRecord.savePath = path)
        }
        ConfigNavRow {
            buttonIcon: "folder_open"
            title: Translation.tr("Open recordings folder")
            description: ScreenRecorder.file || ScreenRecorder.savePath
            onClicked: ScreenRecorder.openFolder()
        }
        ConfigNavRow {
            visible: ScreenRecorder.active
            buttonIcon: "stop_circle"
            title: ScreenRecorder.tooltip
            description: Translation.tr("The file is finalized before recording is reported as saved.")
            onClicked: ScreenRecorder.stop()
        }
        ContentSubsection {
            visible: ScreenRecorder.error.length > 0
            title: Translation.tr("Last recording error")
            description: ScreenRecorder.error
        }
    }

    ContentSection {
        icon: "file_open"
        title: Translation.tr("Save paths")
        description: Translation.tr("Where screenshots go")

        ConfigSwitch {
            buttonIcon: "screenshot"
            text: Translation.tr("Save screenshots to a folder")
            description: Translation.tr("Otherwise they are only copied to the clipboard")
            autoToggle: false
            checked: Config.options.screenSnip.savePath.length > 0
            onClicked: {
                if (checked) Config.options.screenSnip.savePath = "";
                else root.pickFolder(FileUtils.trimFileProtocol(Directories.pictures), path => Config.options.screenSnip.savePath = path);
            }
        }
        ConfigNavRow {
            visible: Config.options.screenSnip.savePath.length > 0
            buttonIcon: "folder"
            title: Translation.tr("Screenshots")
            description: Config.options.screenSnip.savePath
            trailingIcon: "folder_open"
            onClicked: root.pickFolder(Config.options.screenSnip.savePath, path => Config.options.screenSnip.savePath = path)
        }
    }

    ContentSection {
        icon: "select_window"
        title: Translation.tr("Overlay")
        description: Translation.tr("Floating widgets opened with Super+G")

        ConfigSwitch {
            buttonIcon: "high_density"
            text: Translation.tr("Enable opening zoom animation")
            checked: Config.options.overlay.openingZoomAnimation
            onCheckedChanged: {
                Config.options.overlay.openingZoomAnimation = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "texture"
            text: Translation.tr("Darken screen")
            checked: Config.options.overlay.darkenScreen
            onCheckedChanged: {
                Config.options.overlay.darkenScreen = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Crosshair")
            description: Translation.tr("Press Super+G to open the overlay and pin the crosshair")
            ConfigTextRow {
                monospace: true
                placeholderText: Translation.tr("Crosshair code (in Valorant's format)")
                value: Config.options.crosshair.code
                onValueChanged: {
                    Config.options.crosshair.code = value;
                }
            }
            RippleButtonWithIcon {
                Layout.leftMargin: 12
                Layout.bottomMargin: 6
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open editor")
                onClicked: {
                    Qt.openUrlExternally(`https://www.vcrdb.net/builder?c=${Config.options.crosshair.code}`);
                }
                StyledToolTip {
                    text: "www.vcrdb.net"
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Floating image")
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                ConfigTextRow {
                    placeholderText: Translation.tr("Image file or link")
                    description: Translation.tr("Press Enter to apply")
                    wrapMode: TextEdit.NoWrap
                    value: Config.options.overlay.floatingImage.imageSource
                    onEditingFinished: Config.options.overlay.floatingImage.imageSource = value.trim()
                }
                RippleButtonWithIcon {
                    Layout.rightMargin: 12
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    materialIcon: "image"
                    mainText: Translation.tr("Choose file")
                    onClicked: imageDialog.open()
                }
            }
        }
    }
}
