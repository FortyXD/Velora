import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.tools

SettingsDetailPage {
    id: root
    readonly property Item popupPane: root
    sectionTitles: ({
        screenshots: Translation.tr("Screenshots"),
        "screen-recording": Translation.tr("Screen recording"),
        selection: Translation.tr("Screen selection"),
        overlay: Translation.tr("Overlay")
    })

    readonly property var recording: Config.options.screenRecord
    readonly property var snip: Config.options.screenSnip
    readonly property var selector: Config.options.regionSelector
    readonly property var audioOptions: [
        { value: "none", displayName: Translation.tr("No audio"), icon: "volume_off" },
        { value: "system", displayName: Translation.tr("System sound"), icon: "volume_up" },
        { value: "microphone", displayName: Translation.tr("Microphone only"), icon: "mic" },
        { value: "both", displayName: Translation.tr("System + microphone"), icon: "mic_external_on" }
    ]
    readonly property string audioLabel: audioOptions.find(option => option.value === recording.audio)?.displayName ?? recording.audio
    readonly property bool needsSources: pageShown && tab === "screen-recording" && recording.audio !== "none"
    property var recordingSources: []
    onNeedsSourcesChanged: if (needsSources) sourceProcess.running = true

    function sourceChoices(monitor, selected) {
        const choices = [{ value: "", displayName: Translation.tr("Follow system default"), icon: "settings_suggest" }];
        for (const source of recordingSources) {
            if (source.monitor === monitor)
                choices.push({ value: source.value, displayName: source.displayName, icon: monitor ? "speaker" : "mic" });
        }
        if (selected && !choices.some(item => item.value === selected))
            choices.push({ value: selected, displayName: Translation.tr("Unavailable device: %1").arg(selected), icon: "warning" });
        return choices;
    }
    Process {
        id: sourceProcess
        command: [Directories.recordScriptPath, "sources"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.recordingSources = JSON.parse(text); }
                catch (e) { root.recordingSources = []; }
            }
        }
    }

    function pickFolder(current, callback) {
        const path = FileUtils.trimFileProtocol(current || Directories.home).replace(/^~/, FileUtils.trimFileProtocol(Directories.home));
        folderDialog.currentFolder = "file://" + path.split("/").map(encodeURIComponent).join("/");
        folderDialog.onPicked = callback;
        folderDialog.open();
    }
    FolderDialog {
        id: folderDialog
        property var onPicked: null
        onAccepted: if (onPicked) onPicked(FileUtils.trimFileProtocol(decodeURIComponent(selectedFolder.toString())))
    }
    FileDialog {
        id: imageDialog
        nameFilters: [Translation.tr("Images (*.png *.jpg *.jpeg *.gif *.webp *.svg)"), Translation.tr("All files (*)")]
        onAccepted: Config.options.overlay.floatingImage.imageSource = FileUtils.trimFileProtocol(decodeURIComponent(selectedFile.toString()))
    }

    component CardGrid: GridLayout {
        Layout.fillWidth: true
        columns: width >= 490 ? 2 : 1
        uniformCellWidths: true
        uniformCellHeights: true
        columnSpacing: 12; rowSpacing: 10
    }
    component PreviewPair: GridLayout {
        id: pair
        required property SettingsBranch branch
        required property string scene
        required property string controlsTitle
        required property string controlsIcon
        default property alias controls: controlsSection.contentData
        Layout.fillWidth: true
        columns: width >= 590 ? 2 : 1
        uniformCellWidths: true
        columnSpacing: 16; rowSpacing: 12
        // Explicit layout children keep the default property available for the settings rows.
        children: [
            ContentSection {
                Layout.minimumWidth: 0; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop
                title: Translation.tr("Preview"); icon: "preview"; card: false
                ToolsPreview {
                    Layout.fillWidth: true
                    Layout.preferredHeight: pair.columns === 2 ? Math.max(144, controlsSection.naturalCardHeight) : 164
                    scene: pair.scene; shown: root.pageShown && pair.branch.shown; showReplay: true
                }
            },
            ContentSection {
                id: controlsSection
                Layout.minimumWidth: 0; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop
                minimumCardHeight: pair.columns === 2 ? 144 : 0
                title: pair.controlsTitle; icon: pair.controlsIcon
            }
        ]
    }
    component ToolChoice: ConfigComboRow {
        id: choice
        property bool compact: false
        Layout.minimumWidth: 0
        Layout.preferredWidth: 1
        maximumWidth: compact ? 178 : 345
        dropdown.displayIcon: compact ? "" : (choice.dropdown.currentOption?.icon ?? "")
    }

    component CaptureShortcut: ConfigNavRow {
        id: shortcut
        required property string shortcutId
        readonly property var binding: HyprlandKeybinds.bindMap[shortcutId]
        visible: !!binding
        title: Translation.tr(binding?.description ?? "")
        Accessible.name: title
        Accessible.description: binding?.disabled ? Translation.tr("Off") : binding ? KeyUtils.comboText(binding.mods, binding.key) : ""
        searchText: title + " " + Accessible.description
        onClicked: {
            const window = root.ApplicationWindow.window;
            window.openPage("shortcuts", "shortcutRow-" + shortcutId);
        }
        contentItem: RowLayout {
            spacing: 12
            ConfigIconTile { icon: shortcut.buttonIcon }
            StyledText {
                Layout.fillWidth: true; text: shortcut.title; wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer2
            }
            KeyCombo {
                visible: !!shortcut.binding && !shortcut.binding.disabled
                mods: shortcut.binding?.mods ?? []
                key: shortcut.binding?.key ?? ""
                pixelSize: Appearance.font.pixelSize.smaller
            }
            StyledText {
                visible: shortcut.binding?.disabled ?? false
                text: Translation.tr("Off"); color: Appearance.colors.colSubtext
            }
            MaterialSymbol { text: "chevron_right"; iconSize: 18; color: Appearance.colors.colSubtext }
        }
    }

    Item {
        Layout.fillWidth: true; Layout.fillHeight: true
        SettingsBranch {
            id: overview
            key: "overview"; page: root
            ContentSection {
                title: Translation.tr("Screen capture"); icon: "screenshot"; card: false
                CardGrid {
                    ToolCard {
                        branch: screenshots; scene: "screenshot"; buttonIcon: "screenshot"
                        summary: root.snip.savePath ? Translation.tr("Clipboard and folder") : Translation.tr("Clipboard only")
                    }
                    ToolCard {
                        objectName: "screen-recording" // Stable shortcut from the bar, in every language.
                        branch: recorder; scene: "recording"; buttonIcon: "videocam"
                        summary: ScreenRecorder.active ? ScreenRecorder.tooltip
                            : [root.recording.format.toUpperCase(), root.recording.fps + " FPS", root.audioLabel].join(" · ")
                    }
                }
            }
            ContentSection {
                title: Translation.tr("Desktop tools"); icon: "construction"; card: false
                CardGrid {
                    ToolCard {
                        branch: selection; scene: "selection"; buttonIcon: "select_window"; pictureHeight: 118
                        summary: Config.options.search.imageSearch.useCircleSelection ? Translation.tr("Circle to Search") : Translation.tr("Rectangular selection")
                    }
                    ToolCard {
                        branch: overlay; scene: "overlay"; buttonIcon: "layers"; pictureHeight: 118
                        summary: Translation.tr("Crosshair and floating image")
                    }
                }
            }
            ContentSection {
                title: Translation.tr("Capture shortcuts"); icon: "keyboard"
                CaptureShortcut { id: shotKeys; shortcutId: "tools.screenshot_region"; buttonIcon: "screenshot_region" }
                CaptureShortcut { id: filmKeys; shortcutId: "tools.record_region"; buttonIcon: "videocam" }
                ConfigNavRow {
                    visible: !shotKeys.binding && !filmKeys.binding
                    buttonIcon: "keyboard"; title: Translation.tr("Keyboard shortcuts")
                    onClicked: root.ApplicationWindow.window?.openPage("shortcuts")
                }
            }
        }

        SettingsBranch {
            id: screenshots
            key: "screenshots"; page: root
            PreviewPair {
                scene: "screenshot"; branch: screenshots
                controlsTitle: Translation.tr("Screenshot options"); controlsIcon: "screenshot"
                ConfigSwitch {
                    objectName: "screenshotShowCursor"
                    buttonIcon: "arrow_selector_tool"
                    text: Translation.tr("Show cursor in screenshots")
                    description: Translation.tr("Include the pointer in screen and region captures")
                    autoToggle: false
                    checked: Config.options.screenSnip.showCursor
                    onClicked: Config.options.screenSnip.showCursor = !checked
                }
                ConfigSwitch {
                    buttonIcon: "save"
                    text: Translation.tr("Save screenshots to a folder")
                    description: checked ? "" : Translation.tr("Otherwise they are only copied to the clipboard")
                    autoToggle: false
                    checked: root.snip.savePath.length > 0
                    onClicked: {
                        if (checked) Config.options.screenSnip.savePath = "";
                        else root.pickFolder(Directories.pictures, path => Config.options.screenSnip.savePath = path);
                    }
                }
            }
            ContentSection {
                ConfigNavRow {
                    visible: root.snip.savePath.length > 0
                    buttonIcon: "folder"; title: Translation.tr("Screenshot folder")
                    description: root.snip.savePath; trailingIcon: "folder_open"
                    onClicked: root.pickFolder(root.snip.savePath, path => Config.options.screenSnip.savePath = path)
                }
                SettingsBranchLink {
                    branch: selection; buttonIcon: "screenshot_region"
                    detail: Translation.tr("Guides and suggested regions")
                }
            }
        }

        SettingsBranch {
            id: recorder
            key: "screen-recording"; page: root
            PreviewPair {
                branch: recorder; scene: "recording"
                controlsTitle: Translation.tr("Capture area and timing"); controlsIcon: "videocam"
                ToolChoice {
                    compact: true
                    icon: "screenshot_region"; text: Translation.tr("Capture area")
                    currentValue: root.recording.mode
                    options: [
                        { value: "region", displayName: Translation.tr("Region"), description: Translation.tr("Select an area before recording. Esc cancels."), icon: "screenshot_region" },
                        { value: "screen", displayName: Translation.tr("Focused screen"), description: Translation.tr("Record the entire active monitor."), icon: "desktop_windows" }
                    ]
                    onSelected: value => Config.options.screenRecord.mode = value
                }
                ToolChoice {
                    compact: true
                    icon: "timer"; text: Translation.tr("Start delay")
                    description: Translation.tr("The countdown follows area selection.")
                    currentValue: root.recording.delay
                    options: [
                        { value: 0, displayName: Translation.tr("No delay") },
                        { value: 3, displayName: Translation.tr("3 seconds") },
                        { value: 5, displayName: Translation.tr("5 seconds") },
                        { value: 10, displayName: Translation.tr("10 seconds") }
                    ]
                    onSelected: value => Config.options.screenRecord.delay = value
                }
            }
            ContentSection {
                visible: ScreenRecorder.active || ScreenRecorder.error.length > 0
                title: Translation.tr("Recording status"); icon: "videocam"
                ConfigNavRow {
                    visible: ScreenRecorder.active; buttonIcon: "stop_circle"
                    title: ScreenRecorder.tooltip
                    description: Translation.tr("The file is finalized before recording is reported as saved.")
                    onClicked: ScreenRecorder.stop()
                }
                ContentSubsection {
                    visible: ScreenRecorder.error.length > 0
                    title: Translation.tr("Last recording error"); description: ScreenRecorder.error
                }
            }
            ContentSection {
                title: Translation.tr("Recording audio"); icon: "audio_file"
                ToolChoice {
                    icon: "graphic_eq"; text: Translation.tr("Audio source")
                    description: Translation.tr("Recording uses the devices selected at the start.")
                    currentValue: root.recording.audio; options: root.audioOptions
                    onSelected: value => Config.options.screenRecord.audio = value
                }
                ToolChoice {
                    visible: ["system", "both"].includes(root.recording.audio)
                    icon: "speaker"; text: Translation.tr("System audio device")
                    currentValue: root.recording.systemSource
                    options: root.sourceChoices(true, root.recording.systemSource)
                    description: !sourceProcess.running && dropdown.currentOption?.icon === "warning"
                        ? Translation.tr("A disconnected selected device causes an error, never a silent fallback.") : ""
                    onSelected: value => Config.options.screenRecord.systemSource = value
                }
                ToolChoice {
                    visible: ["microphone", "both"].includes(root.recording.audio)
                    icon: "mic"; text: Translation.tr("Microphone device")
                    currentValue: root.recording.microphoneSource
                    options: root.sourceChoices(false, root.recording.microphoneSource)
                    description: !sourceProcess.running && dropdown.currentOption?.icon === "warning"
                        ? Translation.tr("A disconnected selected device causes an error, never a silent fallback.") : ""
                    onSelected: value => Config.options.screenRecord.microphoneSource = value
                }
                ConfigNavRow {
                    visible: root.recording.audio !== "none"
                    buttonIcon: "refresh"; title: Translation.tr("Refresh audio devices"); trailingIcon: ""
                    onClicked: sourceProcess.running = true
                }
            }
            ContentSection {
                title: Translation.tr("Video file"); icon: "movie"
                description: Translation.tr("Changes apply to the next recording.")
                ToolChoice {
                    icon: "speed"; text: Translation.tr("Frame rate"); currentValue: root.recording.fps
                    options: [
                        { value: 30, displayName: "30 FPS", description: Translation.tr("Lower CPU and disk use") },
                        { value: 60, displayName: "60 FPS", description: Translation.tr("Smoother motion") }
                    ]
                    onSelected: value => Config.options.screenRecord.fps = value
                }
                ToolChoice {
                    icon: "high_quality"; text: Translation.tr("Video quality"); currentValue: root.recording.quality
                    options: [
                        { value: "high", displayName: Translation.tr("High quality (CRF 18)") },
                        { value: "balanced", displayName: Translation.tr("Balanced (CRF 23)") },
                        { value: "small", displayName: Translation.tr("Smaller files (CRF 28)") }
                    ]
                    onSelected: value => Config.options.screenRecord.quality = value
                }
                ToolChoice {
                    icon: "video_file"; text: Translation.tr("Recording format"); currentValue: root.recording.format
                    options: [
                        { value: "mp4", displayName: "MP4", description: Translation.tr("Plays on most devices") },
                        { value: "mkv", displayName: "MKV", description: Translation.tr("More resilient if recording is interrupted") }
                    ]
                    onSelected: value => Config.options.screenRecord.format = value
                }
                ConfigNavRow {
                    buttonIcon: "folder"; title: Translation.tr("Recording folder")
                    description: ScreenRecorder.savePath; trailingIcon: "folder_open"
                    onClicked: root.pickFolder(ScreenRecorder.savePath, path => Config.options.screenRecord.savePath = path)
                }
                ConfigNavRow {
                    buttonIcon: "video_library"; title: Translation.tr("Open recordings folder"); trailingIcon: "open_in_new"
                    description: ScreenRecorder.file
                    onClicked: ScreenRecorder.openFolder()
                }
            }
        }

        SettingsBranch {
            id: selection
            key: "selection"; page: root
            PreviewPair {
                scene: "selection"; branch: selection
                controlsTitle: Translation.tr("Selection guides"); controlsIcon: "gesture"
                ToolChoice {
                    compact: true
                    icon: "image_search"; text: Translation.tr("Google Lens")
                    searchText: [text, Translation.tr("Rectangular selection"), Translation.tr("Circle to Search")].join(" ")
                    currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                    options: [
                        { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangle") },
                        { icon: "gesture", value: "circle", displayName: Translation.tr("Circle") }
                    ]
                    onSelected: value => Config.options.search.imageSearch.useCircleSelection = value === "circle"
                }
                ConfigSwitch {
                    buttonIcon: "point_scan"; text: Translation.tr("Show aim lines")
                    description: Translation.tr("For rectangular selection"); autoToggle: false
                    checked: root.selector.rect.showAimLines
                    onClicked: Config.options.regionSelector.rect.showAimLines = !checked
                }
            }
            ContentSection {
                icon: "select_window"; title: Translation.tr("Hint target regions")
                ConfigSwitch {
                    buttonIcon: "select_window"; text: Translation.tr("Window outlines"); autoToggle: false
                    checked: root.selector.targetRegions.windows
                    onClicked: Config.options.regionSelector.targetRegions.windows = !checked
                }
                ConfigSwitch {
                    buttonIcon: "dock_to_right"; text: Translation.tr("Panels and overlays"); autoToggle: false
                    checked: root.selector.targetRegions.layers
                    onClicked: Config.options.regionSelector.targetRegions.layers = !checked
                }
                ConfigSwitch {
                    buttonIcon: "image"; text: Translation.tr("Content regions"); autoToggle: false
                    description: Translation.tr("Detect images and other areas on the device.")
                    checked: root.selector.targetRegions.content
                    onClicked: Config.options.regionSelector.targetRegions.content = !checked
                }
            }
            ContentSection {
                icon: "gesture"; title: Translation.tr("Circle selection")
                ConfigSpinBox {
                    icon: "eraser_size_3"; text: Translation.tr("Stroke width")
                    value: root.selector.circle.strokeWidth; from: 1; to: 20; stepSize: 1
                    onValueChanged: Config.options.regionSelector.circle.strokeWidth = value
                }
                ConfigSpinBox {
                    icon: "screenshot_frame_2"; text: Translation.tr("Padding")
                    value: root.selector.circle.padding; from: 0; to: 100; stepSize: 5
                    onValueChanged: Config.options.regionSelector.circle.padding = value
                }
            }
        }

        SettingsBranch {
            id: overlay
            key: "overlay"; page: root
            PreviewPair {
                scene: "overlay"; branch: overlay
                controlsTitle: Translation.tr("Opening the overlay"); controlsIcon: "layers"
                ConfigSwitch {
                    buttonIcon: "animation"; text: Translation.tr("Enable opening zoom animation"); autoToggle: false
                    checked: Config.options.overlay.openingZoomAnimation
                    onClicked: Config.options.overlay.openingZoomAnimation = !checked
                }
                ConfigSwitch {
                    buttonIcon: "texture"; text: Translation.tr("Darken screen"); autoToggle: false
                    description: Translation.tr("Floating widgets opened with Super+G")
                    checked: Config.options.overlay.darkenScreen
                    onClicked: Config.options.overlay.darkenScreen = !checked
                }
            }
            ContentSection {
                title: Translation.tr("Crosshair"); icon: "center_focus_strong"
                ConfigTextRow {
                    icon: "code"; label: Translation.tr("Crosshair code"); monospace: true
                    placeholderText: Translation.tr("Crosshair code (in Valorant's format)")
                    value: Config.options.crosshair.code
                    onValueChanged: Config.options.crosshair.code = value
                }
                ConfigNavRow {
                    title: Translation.tr("Open editor"); buttonIcon: "edit"; trailingIcon: "open_in_new"
                    description: Translation.tr("Press Super+G to open the overlay and pin the crosshair")
                    onClicked: Qt.openUrlExternally("https://www.vcrdb.net/builder?c=" + encodeURIComponent(Config.options.crosshair.code))
                }
            }
            ContentSection {
                title: Translation.tr("Floating image"); icon: "image"
                ConfigTextRow {
                    label: Translation.tr("Image file or link"); icon: "link"
                    description: Translation.tr("Press Enter to apply"); wrapMode: TextEdit.NoWrap
                    value: Config.options.overlay.floatingImage.imageSource
                    onEditingFinished: Config.options.overlay.floatingImage.imageSource = value.trim()
                }
                ConfigNavRow {
                    buttonIcon: "image"; title: Translation.tr("Choose an image"); trailingIcon: "folder_open"
                    onClicked: imageDialog.open()
                }
            }
        }
    }
}
