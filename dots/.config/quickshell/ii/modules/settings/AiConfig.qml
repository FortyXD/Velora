import QtQuick
import QtQuick.Dialogs
import qs.modules.common.functions
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.modules.settings.preview

SettingsDetailPage {
    id: root

    readonly property var chatModel: Ai.models[Ai.currentModelId] ?? null
    readonly property bool effectiveLocal: Assistant.enabled ? Config.options.assistant.provider === "ollama" :
                                                               !!root.chatModel?.local
    readonly property string effectiveModel: Assistant.enabled ? (Assistant.useStrong
                                                                  ? Assistant.profile.strong_model :
                                                                    Assistant.profile.model) : (root.chatModel
                                                                                                ?.name || root.chatModel
                                                                                                ?.model
                                                                                                || Translation.tr(
                                                                                                    "Choose a model"))
    readonly property int localCount: Ai.modelList.filter(id => Ai.models[id]?.local).length
    readonly property var modelOptions: Ai.modelList.filter(id => Ai.modelAllowed(Ai.models[id])).map(id => ({
        value: id,
        displayName: Ai.models[id].name || Ai.models[id].model,
        description: Ai.models[id].local ? Translation.tr("On this computer") : Translation.tr("Cloud")
    }))

    FolderDialog {
        id: trustedFolder
        onAccepted: {
            const path = FileUtils.trimFileProtocol(decodeURIComponent(selectedFolder.toString()));
            const roots = Config.options.assistant.trustedReadFolders;
            if (path.length > 1 && !roots.includes(path)) Config.options.assistant.trustedReadFolders = [...roots, path];
        }
    }

    // Ready-made system prompts: the shell's own and ones in ~/.config/velora/ai/prompts
    property var promptFiles: []

    fitToWindow: true
    maxContentWidth: 940
    sectionParents: ({
                         connection: "models",
                         "assistant-model": "models"
                     })
    sectionTitles: ({
                        access: Translation.tr("File access"),
                        models: Translation.tr("Models & connections"),
                        chat: Translation.tr("Chat"),
                        assistant: Translation.tr("Desktop actions"),
                        "assistant-model": Translation.tr("Model for actions"),
                        connection: providers.editingId ? Translation.tr("Edit connection") : Translation.tr(
                                                              "Add connection")
                    })

    Component.onCompleted: {
        if (root.pageShown)
            Ai.refreshLists();
        if (Quickshell.env("QS_AI_ADD_CONNECTION") === "1")
            Qt.callLater(() => providers.openEditor(null));
    }
    onPageShownChanged: if (root.pageShown)
                            Ai.refreshLists()

    Process {
        id: promptList

        command: ["bash", "-c", `for dir in '${Directories.defaultAiPrompts}' '${Directories.userAiPrompts
            }'; do ls -1 "$dir"/*.md "$dir"/*.txt 2>/dev/null; done`]
        running: root.pageShown

        stdout: StdioCollector {
            onStreamFinished: root.promptFiles = text.split("\n").filter(line => line.length > 0)
        }
    }

    FileView {
        id: promptFile

        onLoaded: {
            Config.options.ai.systemPrompt = promptFile.text();
            promptField.value = Config.options.ai.systemPrompt;
        }
    }

    Item {
        Layout.fillHeight: true
        Layout.fillWidth: true

        SettingsTabPage {
            anchors.fill: parent
            current: root.tab
            enabled: shown
            key: "overview"

            onRevealRequested: key => root.tab = key

            SettingsScrollPane {
                anchors.fill: parent
                objectName: "aiOverviewScroll"

                AiPreview {
                    modelName: root.effectiveModel
                    modelSource: root.effectiveLocal ? Translation.tr("On this computer") : Translation.tr(
                                                           "Cloud")

                    onSectionRequested: section => root.tab = section
                }

                ContentSection {
                    ConfigComboRow {
                        currentValue: Config.options.policies.ai
                        icon: "neurology"
                        maximumWidth: 220
                        objectName: "aiAccessPolicy"
                        options: [
                            {
                                displayName: Translation.tr("Off"),
                                icon: "block",
                                value: 0
                            },
                            {
                                displayName: Translation.tr("Local only"),
                                icon: "computer",
                                value: 2
                            },
                            {
                                displayName: Translation.tr("Local and cloud"),
                                icon: "cloud",
                                value: 1
                            }
                        ]
                        text: Translation.tr("AI access")

                        onSelected: value => Config.options.policies.ai = value
                    }

                    ConfigNavRow {
                        buttonIcon: "folder_open"
                        title: Translation.tr("File access")
                        description: Translation.tr("Local search and trusted folders")
                        onClicked: root.tab = "access"
                    }

                    ConfigNavRow {
                        buttonIcon: "chat"
                        description: root.effectiveModel
                        objectName: "aiChatSummary"
                        title: Translation.tr("Chat")

                        onClicked: {
                            forceActiveFocus();
                            root.tab = "chat";
                        }
                    }

                    ConfigNavRow {
                        buttonIcon: "touch_app"
                        description: Assistant.enabled ? Config.options.assistant.model : Translation.tr(
                                                             "Off")
                        objectName: "aiActionsSummary"
                        title: Translation.tr("Desktop actions")

                        onClicked: {
                            forceActiveFocus();
                            root.tab = "assistant";
                        }
                    }

                    ConfigNavRow {
                        buttonIcon: "neurology"
                        description: Translation.tr("%1 local · %2 cloud connections").arg(
                                         root.localCount).arg(AiConnections.records.length)
                        objectName: "aiModelsSummary"
                        title: Translation.tr("Models & connections")

                        onClicked: {
                            forceActiveFocus();
                            root.tab = "models";
                        }
                    }
                }
            }
        }

        SettingsTabPage {
            anchors.fill: parent
            current: root.tab
            enabled: shown
            key: "access"
            onRevealRequested: key => root.tab = key
            SettingsScrollPane {
                anchors.fill: parent
                ContentSection {
                    title: Translation.tr("Local search")

                    ConfigSwitch {
                        objectName: "aiAutoLocalSearch"
                        autoToggle: false
                        buttonIcon: "search"
                        text: Translation.tr("Allow local searches without asking")
                        description: Translation.tr("Find apps, windows and files locally. A file you name in your message can be read when it is the only match.")
                        checked: Config.options.assistant.autoLocalSearch
                        onClicked: Config.options.assistant.autoLocalSearch = !checked
                    }
                }
                ContentSection {
                    title: Translation.tr("Trusted folders for local chats")
                    ConfigNavRow {
                        buttonIcon: "folder_open"
                        title: Translation.tr("Trust a folder for local reads")
                        description: Translation.tr("Local chats can read files in the folders listed here.")
                        onClicked: trustedFolder.open()
                    }
                    Repeater {
                        model: Config.options.assistant.trustedReadFolders
                        delegate: ConfigNavRow {
                            required property string modelData
                            title: modelData
                            buttonIcon: "folder"
                            trailingIcon: "close"
                            onClicked: Config.options.assistant.trustedReadFolders = Config.options.assistant.trustedReadFolders.filter(path => path !== modelData)
                        }
                    }

                }
            }
        }

        AiProviderSettings {
            id: providers

            anchors.fill: parent
            currentPage: root.tab
            enabled: z === 1
            pageShown: root.pageShown && (root.tab === "models" || root.tab === "connection")
            z: root.tab === "models" || root.tab === "connection" ? 1 : 0

            onEditorClosed: if (root.tab === "connection")
                                root.navigateBack()
            onEditorRequested: root.tab = "connection"
            onPageRequested: key => root.tab = key

            ContentSection {
                description: Translation.tr(
                                 "Installed models run on this computer. Selecting one does not load it into memory.")
                icon: "computer"
                title: Translation.tr("Local models")

                ConfigComboRow {
                    currentValue: root.chatModel?.local ? Ai.currentModelId : ""
                    enabled: Config.options.policies.ai !== 0 && !Ai.generating && !Assistant.enabled
                    icon: "chat"
                    objectName: "aiLocalChatModel"
                    options: root.modelOptions.filter(item => Ai.models[item.value]?.local)
                    placeholderText: Translation.tr("Choose a model…")
                    text: Translation.tr("Model for chat")

                    onSelected: value => Ai.setModel(value, false)
                }

                ConfigNavRow {
                    buttonIcon: "memory"
                    description: Config.options.assistant.model
                    objectName: "aiLocalModelDetails"
                    title: Translation.tr("Model for actions")

                    onClicked: {
                        forceActiveFocus();
                        root.tab = "assistant-model";
                    }
                }

                ConfigComboRow {
                    icon: "memory"
                    text: Translation.tr("Conversation context")
                    currentValue: Config.options.assistant.contextTokens
                    options: [0, 4096, 8192, 16384, 32768].map(n => ({value:n, displayName:n ? String(n) : Translation.tr("Automatic")}))
                    onSelected: value => Config.options.assistant.contextTokens = value
                }
                ConfigComboRow {
                    icon: "memory"
                    text: Translation.tr("Unload the local model")
                    currentValue: Config.options.ai.modelIdleSeconds < 0 ? "auto" : Config.options.ai.modelIdleSeconds === 0 ? "now" : "custom"
                    options: [
                        {value:"auto", displayName:Translation.tr("Auto · 30 min on battery, 60 min on AC")},
                        {value:"now", displayName:Translation.tr("After each response")},
                        {value:"custom", displayName:Translation.tr("After a set number of minutes")}
                    ]
                    onSelected: value => {
                        if (value !== currentValue) Config.options.ai.modelIdleSeconds = value === "auto" ? -1 : value === "now" ? 0 : 900;
                    }
                }
                ConfigSwitch {
                    objectName: "aiPreloadOnLogin"
                    autoToggle: false
                    buttonIcon: "speed"
                    text: Translation.tr("Prepare the local assistant after login")
                    description: Translation.tr("Load the CPU model on external power when enough memory is free.")
                    checked: Config.options.assistant.preloadOnLogin
                    onClicked: Config.options.assistant.preloadOnLogin = !checked
                }
                ConfigTextRow {
                    visible: Config.options.ai.modelIdleSeconds > 0
                    label: Translation.tr("Minutes of inactivity")
                    icon: "timer"
                    inline: true
                    inlineFieldWidth: 96
                    wrapMode: TextEdit.NoWrap
                    value: String(Math.max(1, Math.ceil(Config.options.ai.modelIdleSeconds / 60)))
                    onEditingFinished: {
                        const minutes = Number(value);
                        if (Number.isInteger(minutes) && minutes >= 1 && minutes <= 1440) Config.options.ai.modelIdleSeconds = minutes * 60;
                        value = Qt.binding(() => String(Math.max(1, Math.ceil(Config.options.ai.modelIdleSeconds / 60))));
                    }
                }
                ConfigExpander {
                    title: Translation.tr("More options")

                    ConfigNavRow {
                        buttonIcon: "refresh"
                        title: Translation.tr("Rescan local models")
                        trailingIcon: "refresh"

                        onClicked: Ai.refreshLists()
                    }
                }
            }
        }

        SettingsTabPage {
            anchors.fill: parent
            current: root.tab
            enabled: shown
            key: "chat"

            onRevealRequested: key => root.tab = key

            SettingsScrollPane {
                anchors.fill: parent

                ContentSection {
                    description: Assistant.enabled ? Translation.tr(
                                                         "Desktop actions currently handles your sidebar chat. Ordinary chat settings below are saved but inactive.") :
                                                     Translation.tr(
                                                         "These instructions apply to ordinary sidebar chat.")
                    icon: "chat"
                    title: Translation.tr("Sidebar chat")

                    ConfigNavRow {
                        buttonIcon: "neurology"
                        description: root.effectiveModel
                        objectName: "aiActiveChatModel"
                        title: Translation.tr("Model for chat")
                        visible: Assistant.enabled

                        onClicked: {
                            forceActiveFocus();
                            root.tab = "assistant-model";
                        }
                    }

                    ConfigComboRow {
                        currentValue: Ai.currentModelId ?? ""
                        enabled: Config.options.policies.ai !== 0 && !Ai.generating
                        icon: "neurology"
                        objectName: "aiChatModel"
                        options: root.modelOptions
                        placeholderText: Translation.tr("Choose a model…")
                        text: Translation.tr("Model for chat")
                        visible: !Assistant.enabled

                        onSelected: value => Ai.setModel(value, false)
                    }

                    ConfigNavRow {
                        buttonIcon: "add_link"
                        title: Translation.tr("Add connection")

                        onClicked: {
                            providers.openEditor(null);
                        }
                    }

                    ConfigSwitch {
                        autoToggle: false
                        buttonIcon: "neurology"
                        checked: Config.options.sidebar.ai.showThoughts
                        description: Translation.tr("Expand the model's reasoning when available")
                        text: Translation.tr("Show reasoning")

                        onClicked: Config.options.sidebar.ai.showThoughts = !checked
                    }

                    ConfigExpander {
                        enabled: !Assistant.enabled
                        title: Translation.tr("Performance")

                        ConfigSwitch {
                            autoToggle: false
                            buttonIcon: "memory"
                            checked: Config.options.ai.localGpu
                            description: Translation.tr("On external power; CPU on battery")
                            text: Translation.tr("GPU acceleration")

                            onClicked: Config.options.ai.localGpu = !checked
                        }
                    }
                }

                ContentSection {
                    description: Translation.tr("These instructions apply to ordinary sidebar chat.")
                    enabled: !Assistant.enabled
                    icon: "neurology"
                    title: Translation.tr("Chat instructions")

                    ConfigComboRow {
                        description: Translation.tr("Replaces the system prompt below")
                        enabled: Config.options.policies.ai !== 0
                        icon: "library_books"
                        options: root.promptFiles.map(path => ({
                            displayName: path.split("/").pop().replace(/\.(md|txt)$/, "").replace(/[-_]/g,
                                                                                                  " "),
                            value: path,
                            description: path.startsWith(Directories.userAiPrompts) ? Translation.tr("Yours") :
                                                                                      ""
                        }))
                        placeholderText: Translation.tr("Load a preset…")
                        text: Translation.tr("Prompt presets")
                        visible: root.promptFiles.length > 0

                        onSelected: value => {
                            promptFile.path = "";
                            promptFile.path = value;
                        }
                    }

                    ConfigTextRow {
                        id: promptField

                        description: Translation.tr("Instructions the assistant gets before every chat")
                        enabled: Config.options.policies.ai !== 0
                        fieldMinimumHeight: 96
                        icon: "edit_note"
                        label: Translation.tr("System prompt")
                        placeholderText: Translation.tr("System prompt")
                        value: Config.options.ai.systemPrompt

                        onValueChanged: {
                            const text = value;
                            Qt.callLater(() => {
                                Config.options.ai.systemPrompt = text;
                            });
                        }
                    }
                }
            }
        }

        AssistantSettings {
            anchors.fill: parent
            currentPage: root.tab
            enabled: z === 1
            pageShown: root.pageShown && (root.tab === "assistant" || root.tab === "assistant-model")
            z: root.tab === "assistant" || root.tab === "assistant-model" ? 1 : 0

            onAddConnectionRequested: providers.openEditor(null)
            onPageRequested: key => root.tab = key
        }
    }
}
