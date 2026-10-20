//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// The Folis toolbox: file converter, video downloader, QR codes, text recognition and colors.
// Open it with scripts/toolbox/open.sh [tab] [files…] (one window; later calls go to it over IPC).

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.toolbox

ApplicationWindow {
    id: root

    readonly property var tabs: [
        { "key": "converter", "icon": "transform", "name": Translation.tr("Converter"), "description": Translation.tr("Images, video, audio, documents and archives") },
        { "key": "downloader", "icon": "download", "name": Translation.tr("Downloads"), "description": Translation.tr("Video and music from links") },
        { "key": "qr", "icon": "qr_code_2", "name": Translation.tr("QR codes"), "description": Translation.tr("Make and read QR codes") },
        { "key": "ocr", "icon": "document_scanner", "name": Translation.tr("Text from images"), "description": Translation.tr("Recognize text in pictures and PDFs") },
        { "key": "colors", "icon": "palette", "name": Translation.tr("Colors"), "description": Translation.tr("Pick colors, convert them and make palettes") },
    ]
    property string currentTab: "converter"
    property list<string> openedTabs: ["converter"] // Pages keep their state once opened
    onCurrentTabChanged: if (!openedTabs.includes(currentTab)) openedTabs = [...openedTabs, currentTab]
    property var caps: ({})

    function tabIndex(key) {
        return Math.max(0, root.tabs.findIndex(tab => tab.key === key));
    }

    // Opens a tab and hands it files (paths or file:// URLs)
    function open(tab, files) {
        if (tab && root.tabs.some(entry => entry.key === tab)) root.currentTab = tab;
        const list = (files ?? []).filter(file => `${file}`.trim().length > 0);
        if (list.length === 0) return;
        const page = pageRepeater.itemAt(root.tabIndex(root.currentTab))?.item;
        if (page?.addPaths) page.addPaths(list);
        else pendingFiles = list;
    }
    property var pendingFiles: []

    visible: true
    onClosing: Qt.quit()
    title: "Folis Toolbox" // Matched by a Hyprland window rule
    minimumWidth: 720
    minimumHeight: 480
    width: 1000
    height: 720
    color: Appearance.m3colors.m3background

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        capsProc.running = true;
        const tab = Quickshell.env("TOOLBOX_TAB") ?? "";
        const files = (Quickshell.env("TOOLBOX_FILES") ?? "").split("\n");
        root.open(tab.length > 0 ? tab : "converter", files);
    }

    Process {
        id: capsProc
        command: ["/usr/bin/python3", "-I", Quickshell.shellPath("scripts/toolbox/folis_toolbox.py"), "caps"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.caps = JSON.parse(text);
                } catch (e) {
                    console.warn("[Toolbox] caps failed:", e);
                }
            }
        }
    }

    IpcHandler {
        target: "toolbox"

        // files: newline-separated
        function open(tab: string, files: string): void {
            root.open(tab, files.split("\n"));
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            const focusItem = root.activeFocusItem;
            if (focusItem && focusItem.cursorPosition !== undefined) contentPane.forceActiveFocus();
            else root.close();
        }
    }
    Shortcut {
        sequences: ["Ctrl+PgDown", "Ctrl+Tab"]
        onActivated: root.currentTab = root.tabs[(root.tabIndex(root.currentTab) + 1) % root.tabs.length].key
    }
    Shortcut {
        sequences: ["Ctrl+PgUp", "Ctrl+Shift+Tab", "Ctrl+Backtab"]
        onActivated: root.currentTab = root.tabs[(root.tabIndex(root.currentTab) - 1 + root.tabs.length) % root.tabs.length].key
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        ColumnLayout { // Tabs
            Layout.fillHeight: true
            Layout.fillWidth: false // Layouts fill by default and would squeeze the page
            Layout.preferredWidth: 220
            spacing: 4

            RowLayout {
                Layout.margins: 12
                spacing: 10
                MaterialSymbol {
                    text: "construction"
                    iconSize: 26
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: Translation.tr("Toolbox")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer0
                }
            }

            Repeater {
                model: root.tabs
                delegate: RippleButton {
                    id: tabButton
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 52
                    buttonRadius: Appearance.rounding.full
                    toggled: root.currentTab === modelData.key
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    onClicked: root.currentTab = modelData.key
                    contentItem: RowLayout {
                        spacing: 12
                        MaterialSymbol {
                            Layout.leftMargin: 8
                            text: tabButton.modelData.icon
                            iconSize: 22
                            fill: tabButton.toggled ? 1 : 0
                            color: tabButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: tabButton.modelData.name
                            color: tabButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                        }
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }

        Rectangle { // Page
            id: contentPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.windowRounding
            color: Appearance.colors.colLayer1
            focus: true
            clip: true

            Repeater {
                id: pageRepeater
                model: root.tabs
                delegate: Loader {
                    id: pageLoader
                    required property var modelData
                    required property int index
                    anchors.fill: parent
                    active: root.openedTabs.includes(modelData.key)
                    visible: root.currentTab === modelData.key
                    source: `modules/toolbox/${{
                        "converter": "ConverterPage", "downloader": "DownloaderPage", "qr": "QrPage",
                        "ocr": "OcrPage", "colors": "ColorsPage"
                    }[modelData.key]}.qml`
                    onLoaded: {
                        item.caps = Qt.binding(() => root.caps);
                        if (item.heroTitle !== undefined) {
                            item.heroIcon = pageLoader.modelData.icon;
                            item.heroTitle = pageLoader.modelData.name;
                            item.heroDescription = pageLoader.modelData.description;
                        }
                        if (root.pendingFiles.length > 0 && item.addPaths && root.currentTab === pageLoader.modelData.key) {
                            item.addPaths(root.pendingFiles);
                            root.pendingFiles = [];
                        }
                    }
                }
            }
        }
    }
}
