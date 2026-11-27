import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Popup {
    id: root
    signal searchRequested()
    property real maximumMenuHeight: 560
    readonly property real optionHeight: {
        let height = 48;
        for (const item of menuBody.children) {
            if (item.settingsSearchable) height = Math.max(height, item.implicitHeight);
        }
        return Math.ceil(height);
    }
    padding: 12
    height: Math.max(0, Math.min(maximumMenuHeight, 560,
        header.implicitHeight + body.spacing + menuBody.implicitHeight + topPadding + bottomPadding))
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Appearance.scaledDuration(160) }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: Appearance.scaledDuration(180); easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Appearance.scaledDuration(110) }
    }
    background: Rectangle {
        color: Appearance.colors.colLayer2Base
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }
    contentItem: ColumnLayout {
        id: body
        spacing: 8
        RowLayout {
            id: header
            Layout.fillWidth: true
            Layout.leftMargin: 8
            StyledText { Layout.fillWidth: true; text: Translation.tr("Chat options"); font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold }
            ChatIconButton { symbol: "close"; tooltip: Translation.tr("Close"); onClicked: root.close() }
        }
        StyledFlickable {
            id: scroll
            objectName: "chatOptionsScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            contentWidth: width
            contentHeight: menuBody.implicitHeight
            ColumnLayout {
                id: menuBody
                width: Math.max(0, scroll.width - 10)
                spacing: 4
                ConfigNavRow {
                    objectName: "chatFindAction"
                    Layout.preferredHeight: root.optionHeight
                    buttonIcon: "search"
                    title: Translation.tr("Find in conversation")
                    onClicked: { root.close(); root.searchRequested(); }
                }
                ConfigSwitch {
                    Layout.preferredHeight: root.optionHeight
                    id: fileAccessSwitch
                    objectName: "chatFileAccess"
                    text: Translation.tr("File access")
                    buttonIcon: "folder_open"
                    checked: SidebarChat.fileAccessEnabled
                    enabled: !SidebarChat.busy
                    autoToggle: false
                    onClicked: SidebarChat.setFileAccess(!checked)
                }
                ConfigSwitch {
                    Layout.preferredHeight: root.optionHeight
                    objectName: "chatCodeExecution"
                    text: Translation.tr("Run commands and code")
                    description: Translation.tr("Review each command or script before it runs")
                    buttonIcon: "terminal"
                    checked: SidebarChat.commandAccessEnabled
                    enabled: !SidebarChat.busy
                    autoToggle: false
                    onClicked: SidebarChat.setCommandAccess(!checked)
                }
                ConfigNavRow {
                    Layout.preferredHeight: root.optionHeight
                    objectName: "chatChooseFiles"
                    Layout.fillWidth: true
                    buttonIcon: "attach_file"; title: Translation.tr("Choose files")
                    enabled: !SidebarChat.busy && SidebarChat.attachmentLimit > 0
                    onClicked: { root.close(); fileDialog.open(); }
                }
                ConfigNavRow {
                    Layout.preferredHeight: root.optionHeight
                    objectName: "chatRunScript"
                    Layout.fillWidth: true
                    buttonIcon: "code"; title: Translation.tr("Run a script file…")
                    enabled: !SidebarChat.busy && SidebarChat.commandAccessEnabled && fileAccessSwitch.checked
                    onClicked: { root.close(); scriptDialog.open(); }
                }
                ConfigSwitch {
                    Layout.preferredHeight: root.optionHeight
                    text: Translation.tr("Show reasoning")
                    description: Translation.tr("Expand the model's reasoning when available")
                    buttonIcon: "neurology"
                    checked: Config.options.sidebar.ai.showThoughts
                    autoToggle: false
                    onClicked: Config.options.sidebar.ai.showThoughts = !checked
                }
                ConfigSwitch {
                    Layout.preferredHeight: root.optionHeight
                    visible: SidebarChat.mode === "chat" && Ai.currentModelIsLocal
                    text: Translation.tr("GPU acceleration")
                    description: Translation.tr("On external power; CPU on battery")
                    buttonIcon: "memory"
                    checked: Config.options.ai.localGpu
                    enabled: !SidebarChat.busy
                    autoToggle: false
                    onClicked: { Config.options.ai.localGpu = !checked; LocalAiRuntime.stop(); }
                }
                ColumnLayout {
                    visible: SidebarChat.mode === "chat"
                    Layout.fillWidth: true
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { Layout.fillWidth: true; text: Translation.tr("Creativity"); color: Appearance.colors.colSubtext }
                        StyledText { text: Ai.temperature.toFixed(1); color: Appearance.colors.colSubtext }
                    }
                    StyledSlider {
                        Layout.fillWidth: true; enabled: !SidebarChat.busy
                        from: 0; to: Ai.getModel()?.api_format === "gemini" ? 2 : 1
                        defaultValue: 0.5
                        stepSize: 0.1; value: Ai.temperature
                        usePercentTooltip: false; tooltipContent: value.toFixed(1)
                        onMoved: Ai.setTemperature(value)
                    }
                    StyledText { visible: !Ai.currentModelIsLocal; text: Translation.tr("Tools"); color: Appearance.colors.colSubtext }
                    StyledComboBox {
                        visible: !Ai.currentModelIsLocal
                        Layout.fillWidth: true; enabled: !SidebarChat.busy
                        model: Ai.availableTools.map(value => ({value, label:value === "none" ? Translation.tr("No tools") : value === "search" ? Translation.tr("Web search") : Translation.tr("Desktop actions")}))
                        textRole: "label"
                        currentIndex: Math.max(0, Ai.availableTools.indexOf(Ai.currentTool))
                        onActivated: index => Ai.setTool(Ai.availableTools[index])
                    }
                    StyledText { visible: Ai.promptFiles.length > 0; text: Translation.tr("Prompt template"); color: Appearance.colors.colSubtext }
                    StyledComboBox {
                        visible: Ai.promptFiles.length > 0
                        Layout.fillWidth: true; enabled: !SidebarChat.busy
                        model: Ai.promptFiles.map(path => ({path, label:path.split("/").pop().replace(/\.(md|txt)$/, "")}))
                        textRole: "label"
                        currentIndex: -1
                        displayText: currentIndex < 0 ? Translation.tr("Choose a template…") : currentText
                        onActivated: index => Ai.loadPrompt(Ai.promptFiles[index])
                    }
                    RowLayout {
                        visible: Ai.getModel()?.requires_key ?? false
                        Layout.fillWidth: true
                        ToolbarTextField { id: apiKey; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: Translation.tr("Paste API key"); onAccepted: { Ai.setApiKey(text); text = ""; } }
                        ChatIconButton { symbol: "key"; tooltip: Translation.tr("Save API key"); enabled: !!apiKey.text.trim() && !SidebarChat.busy; onClicked: { Ai.setApiKey(apiKey.text); apiKey.clear(); } }
                    }
                }
                ConfigNavRow {
                    Layout.preferredHeight: root.optionHeight
                    objectName: "chatFreeMemory"
                    Layout.fillWidth: true; visible: SidebarChat.localModel; enabled: !SidebarChat.busy
                    buttonIcon: "memory"; title: Translation.tr("Unload model")
                    onClicked: SidebarChat.releaseMemory()
                }
                StyledText {
                    Layout.fillWidth: true; visible: SidebarChat.localModel && !!LocalAiRuntime.memoryStatus
                    text: LocalAiRuntime.memoryStatus; wrapMode: Text.Wrap; color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                ConfigSwitch {
                    Layout.preferredHeight: root.optionHeight
                    visible: SidebarChat.mode === "assistant"
                    text: Translation.tr("Extended task"); buttonIcon: "checklist"
                    checked: Assistant.extended; enabled: !SidebarChat.busy; autoToggle: false
                    onClicked: Assistant.extended = !checked
                }
                ConfigSwitch {
                    Layout.preferredHeight: root.optionHeight
                    visible: SidebarChat.mode === "assistant" && !!Assistant.profile.strong_model
                    text: Translation.tr("Stronger model"); buttonIcon: "bolt"
                    checked: Assistant.useStrong; enabled: !SidebarChat.busy; autoToggle: false
                    onClicked: Assistant.useStrong = !checked
                }
                ConfigNavRow {
                    Layout.preferredHeight: root.optionHeight
                    objectName: "chatOpenSettings"; buttonIcon: "settings"; title: Translation.tr("Open settings")
                    onClicked: { root.close(); Quickshell.execDetached(["env", "QS_SETTINGS_PAGE=ai", "QS_SETTINGS_SECTION=", "QS_SETTINGS_SEARCH=", "qs", "-p", Quickshell.shellPath("settings.qml")]); }
                }
            }
        }
    }
    onAboutToShow: { scroll.cancelFlick(); scroll.contentY = 0; }
    onClosed: apiKey.clear()
    FileDialog {
        id: fileDialog
        title: Translation.tr("Attach files")
        fileMode: SidebarChat.attachmentLimit === 1 ? FileDialog.OpenFile : FileDialog.OpenFiles
        onAccepted: SidebarChat.attach(selectedFiles)
    }
    FileDialog {
        id: scriptDialog
        title: Translation.tr("Run a script file…")
        nameFilters: [Translation.tr("Scripts (*.py *.sh *.bash *.js *.mjs *.cjs)")]
        onAccepted: {
            const url = String(selectedFile);
            if (!url.startsWith("file:///")) return;
            const path = decodeURIComponent(url.slice(7));
            Assistant.submitTool("terminal_run", {script_path:path}, Translation.tr("Run script %1").arg(path), "sidebar");
        }
    }
}
