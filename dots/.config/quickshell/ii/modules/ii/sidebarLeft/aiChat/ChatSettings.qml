import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Popup {
    id: root
    signal searchRequested()
    property real maximumMenuHeight: 560
    padding: 16
    height: Math.min(menuBody.implicitHeight + 32, 560, Math.max(220, maximumMenuHeight))
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
    contentItem: ScrollView {
        id: scroll
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            id: menuBody
            width: scroll.availableWidth
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                StyledText { Layout.fillWidth: true; text: Translation.tr("Chat options"); font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold }
                ChatIconButton { symbol: "close"; tooltip: Translation.tr("Close"); onClicked: root.close() }
            }
            RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "search"; mainText: Translation.tr("Find in conversation"); onClicked: { root.close(); root.searchRequested(); } }
            ConfigSwitch {
                text: Translation.tr("Show reasoning")
                description: Translation.tr("Expand the model's reasoning when available")
                buttonIcon: "neurology"
                checked: Config.options.sidebar.ai.showThoughts
                autoToggle: false
                onClicked: Config.options.sidebar.ai.showThoughts = !checked
            }
            ConfigSwitch {
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
            RippleButtonWithIcon {
                objectName: "chatFreeMemory"
                Layout.fillWidth: true; visible: SidebarChat.localModel; enabled: !SidebarChat.busy
                materialIcon: "memory"; mainText: Translation.tr("Free memory")
                onClicked: SidebarChat.releaseMemory()
            }
            StyledText {
                Layout.fillWidth: true; visible: SidebarChat.localModel && !!LocalAiRuntime.memoryStatus
                text: LocalAiRuntime.memoryStatus; wrapMode: Text.Wrap; color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            ConfigSwitch {
                visible: SidebarChat.mode === "assistant"
                text: Translation.tr("Extended task"); buttonIcon: "checklist"
                checked: Assistant.extended; enabled: !SidebarChat.busy; autoToggle: false
                onClicked: Assistant.extended = !checked
            }
            ConfigSwitch {
                visible: SidebarChat.mode === "assistant" && !!Assistant.profile.strong_model
                text: Translation.tr("Stronger model"); buttonIcon: "bolt"
                checked: Assistant.useStrong; enabled: !SidebarChat.busy; autoToggle: false
                onClicked: Assistant.useStrong = !checked
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true; materialIcon: "settings"; mainText: Translation.tr("Open settings")
                onClicked: { root.close(); Quickshell.execDetached(["env", "QS_SETTINGS_PAGE=ai", "QS_SETTINGS_SECTION=", "QS_SETTINGS_SEARCH=", "qs", "-p", Quickshell.shellPath("settings.qml")]); }
            }
        }
    }
    onClosed: apiKey.clear()
}
