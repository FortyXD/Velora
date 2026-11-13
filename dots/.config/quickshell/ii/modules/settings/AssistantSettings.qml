import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string currentPage: "assistant"
    property var installedModels: []
    readonly property bool localInstalled: root.installedModels.some(model => {
        return model.name === Config.options.assistant.model;
    })
    property bool pageShown: true
    readonly property var savedConnection: AiConnections.records.find(m => {
        return m.model === Config.options.assistant.model && m.endpoint === Config.options.assistant.endpoint;
    })
    property string source: Config.options.assistant.provider === "ollama" ? "local" : savedConnection
                                                                             ? "saved" : "manual"

    signal addConnectionRequested
    signal pageRequested(string key)

    function chooseLocal(model) {
        Config.options.assistant.provider = "ollama";
        Config.options.assistant.endpoint = "http://127.0.0.1:11434";
        Config.options.assistant.model = model;
        Config.options.assistant.vision = false;
    }

    Layout.fillWidth: true
    objectName: "assistantSettings"

    Component.onCompleted: {
        if (pageShown)
            localModels.running = true;
    }
    onCurrentPageChanged: key.clear()
    onPageShownChanged: {
        if (pageShown)
            localModels.running = true;
        else
            key.clear();
    }

    Process {
        id: localModels

        command: ["bash", Quickshell.shellPath("scripts/ai/show-installed-ollama-models.sh")]

        stdout: SplitParser {
            onRead: line => {
                try {
                    root.installedModels = JSON.parse(line);
                } catch (_) {}
            }
        }
    }

    Connections {
        function onTaskFinished() {
            if (root.pageShown && Config.options.assistant.provider === "ollama")
                localModels.running = true;
        }

        target: Assistant
    }

    SettingsTabPage {
        anchors.fill: parent
        current: root.currentPage
        enabled: shown
        key: "assistant"

        onRevealRequested: key => {
            return root.pageRequested(key);
        }

        SettingsScrollPane {
            anchors.fill: parent

            ContentSection {
                description: Translation.tr(
                                 "The assistant can work with files and apps. It uses this model in the launcher and sidebar.")
                icon: "touch_app"
                title: Translation.tr("Desktop actions")

                ConfigSwitch {
                    autoToggle: false
                    buttonIcon: "touch_app"
                    checked: Config.options.assistant.enabled
                    description: Config.options.policies.ai === 0 ? Translation.tr(
                                                                        "Allow AI on the overview to use the assistant.") :
                                                                    Translation.tr(
                                                                        "The model starts when you send a request or check it here.")
                    enabled: Config.options.policies.ai !== 0
                    objectName: "desktopAssistantEnable"
                    text: Translation.tr("Enable the desktop assistant")

                    onClicked: Config.options.assistant.enabled = !checked
                }
            }

            ContentSection {
                ConfigNavRow {
                    buttonIcon: "neurology"
                    description: Config.options.assistant.model
                    objectName: "assistantModelDetails"
                    title: Translation.tr("Model for actions")

                    onClicked: {
                        forceActiveFocus();
                        root.pageRequested("assistant-model");
                    }
                }
            }

            ContentSection {
                icon: "restore"
                title: Translation.tr("Rollback checkpoints")
                description: Translation.tr("Checkpoints are kept until you remove them from their chat. New changes stop when storage is full.")

                ConfigSpinBox {
                    objectName: "assistantRollbackBudget"
                    text: Translation.tr("Storage limit (GiB)")
                    from: 1
                    to: 1024
                    stepSize: 1
                    value: Math.round(Config.options.assistant.rollbackBudgetBytes / 1073741824)
                    enabled: !Assistant.busy && !Assistant.preparingSubmission
                    onValueChanged: if (value >= 1) Config.options.assistant.rollbackBudgetBytes = value * 1073741824
                }
            }

            ContentSection {
                icon: "tune"
                title: Translation.tr("Capabilities & performance")

                ConfigSwitch {
                    autoToggle: false
                    checked: Config.options.assistant.vision
                    description: Translation.tr(
                                     "Required for screenshots. Ollama capability checks update this automatically.")
                    text: Translation.tr("Model supports images")

                    onClicked: Config.options.assistant.vision = !checked
                }

                ConfigExpander {
                    title: Translation.tr("Advanced model options")

                    ConfigSwitch {
                        autoToggle: false
                        checked: Config.options.assistant.gpu
                        description: Translation.tr(
                                         "CPU is supported without a GPU. Battery operation always uses CPU.")
                        text: Translation.tr("GPU acceleration on external power")

                        onClicked: Config.options.assistant.gpu = !checked
                    }

                    ConfigTextRow {
                        label: Translation.tr("Stronger model (optional)")
                        value: Config.options.assistant.strongModel

                        onEditingFinished: Config.options.assistant.strongModel = value.trim()
                    }

                    ConfigSpinBox {
                        from: 4096
                        stepSize: 4096
                        text: Translation.tr("Context tokens")
                        to: 32768
                        value: Config.options.assistant.contextTokens

                        onValueChanged: Config.options.assistant.contextTokens = value
                    }
                }
            }
        }
    }

    SettingsTabPage {
        anchors.fill: parent
        current: root.currentPage
        enabled: shown
        key: "assistant-model"

        onRevealRequested: key => {
            return root.pageRequested(key);
        }

        SettingsScrollPane {
            anchors.fill: parent

            ContentSection {
                description: Translation.tr("Current model: %1").arg(Config.options.assistant.model)
                icon: "neurology"
                title: Translation.tr("Model for actions")

                ConfigComboRow {
                    currentValue: root.source
                    icon: "neurology"
                    objectName: "assistantModelSource"
                    options: [
                        {
                            "value": "local",
                            "displayName": Translation.tr("Local model"),
                            "icon": "computer"
                        },
                        {
                            "value": "saved",
                            "displayName": Translation.tr("Saved connection"),
                            "icon": "key"
                        },
                        {
                            "value": "manual",
                            "displayName": Translation.tr("Manual setup"),
                            "icon": "tune"
                        }
                    ]
                    text: Translation.tr("Model source")

                    onSelected: value => {
                        root.source = value;
                        key.clear();
                    }
                }

                ColumnLayout {
                    function settingsReveal() {
                        if (root.source === "local")
                            return false;

                        root.source = "local";
                        return true;
                    }

                    Layout.fillWidth: true
                    spacing: 0
                    visible: root.source === "local"

                    ConfigComboRow {
                        currentValue: Config.options.assistant.provider === "ollama"
                                      ? Config.options.assistant.model : ""
                        icon: "download"
                        options: [
                            {
                                "value": "qwen3.5:2b-q4_K_M",
                                "displayName": Translation.tr("Economy · 2B") + " · ≈1.9 GB"
                            },
                            {
                                "value": "qwen3.5:4b-q4_K_M",
                                "displayName": Translation.tr("Balanced · 4B") + " · ≈3.3 GB"
                            },
                            {
                                "value": "qwen3.5:9b-q4_K_M",
                                "displayName": Translation.tr("Quality · 9B") + " · ≈6.6 GB"
                            }
                        ]
                        text: Translation.tr("Download profile")

                        onSelected: value => {
                            return root.chooseLocal(value);
                        }
                    }

                    ConfigComboRow {
                        currentValue: Config.options.assistant.provider === "ollama"
                                      ? Config.options.assistant.model : ""
                        icon: "computer"
                        options: root.installedModels.map(m => {
                            return ({
                                        "value": m.name,
                                        "displayName": m.name + " · " + (m.size / 1.07374e+09).toFixed(1)
                                                       + " GiB"

                                    });
                        })
                        text: Translation.tr("Installed models")
                        visible: root.installedModels.length > 0

                        onSelected: value => {
                            return root.chooseLocal(value);
                        }
                    }

                    ConfigTextRow {
                        description: Translation.tr("Enter an Ollama model name and press Enter.")
                        label: Translation.tr("Other local model")
                        value: Config.options.assistant.provider === "ollama"
                               ? Config.options.assistant.model : ""

                        onEditingFinished: {
                            if (value.trim())
                                root.chooseLocal(value.trim());
                        }
                    }

                    ConfigNavRow {
                        buttonIcon: "download"
                        description: Translation.tr("Opens a terminal to install Ollama support.")
                        title: Translation.tr("Install local backend")
                        trailingIcon: "open_in_new"

                        onClicked: Quickshell.execDetached(["kitty", "--hold", "velora", "deps", "--add",
                                                            "assistant"])
                    }
                }

                ColumnLayout {
                    function settingsReveal() {
                        if (root.source === "saved")
                            return false;

                        root.source = "saved";
                        return true;
                    }

                    Layout.fillWidth: true
                    spacing: 0
                    visible: root.source === "saved"

                    ConfigComboRow {
                        currentValue: root.savedConnection ? AiConnections.recordId(root.savedConnection) : ""
                        enabled: Config.options.policies.ai === 1
                        icon: "key"
                        options: AiConnections.records.map(m => {
                            return ({
                                        "value": AiConnections.recordId(m),
                                        "displayName": m.name || m.model
                                    });
                        })
                        placeholderText: Translation.tr("Choose a connection…")
                        text: Translation.tr("Saved AI connection")

                        onSelected: value => {
                            return AiConnections.useForAssistant(value);
                        }
                    }

                    ConfigNavRow {
                        buttonIcon: "add_link"
                        description: Config.options.policies.ai === 1 ? Translation.tr(
                                                                            "Use the same provider and key for chat and actions.") :
                                                                        Translation.tr(
                                                                            "Choose Local and cloud above to use cloud connections.")
                        title: Translation.tr("Add connection")

                        onClicked: root.addConnectionRequested()
                    }
                }

                ColumnLayout {
                    function settingsReveal() {
                        if (root.source === "manual")
                            return false;

                        root.source = "manual";
                        return true;
                    }

                    Layout.fillWidth: true
                    spacing: 0
                    visible: root.source === "manual"

                    ConfigComboRow {
                        currentValue: Config.options.assistant.provider
                        options: [
                            {
                                "value": "ollama",
                                "displayName": "Ollama"
                            },
                            {
                                "value": "openai",
                                "displayName": Translation.tr("Compatible API")
                            },
                            {
                                "value": "gemini",
                                "displayName": "Gemini"
                            }
                        ]
                        text: Translation.tr("Model provider")

                        onSelected: value => {
                            Config.options.assistant.provider = value;
                            Config.options.assistant.endpoint = value === "ollama" ? "http://127.0.0.1:11434" :
                                                                                     "";
                            Config.options.assistant.vision = false;
                            Config.options.assistant.keyId = "veloraAssistant";
                        }
                    }

                    ConfigTextRow {
                        label: Translation.tr("Model name")
                        value: Config.options.assistant.model

                        onEditingFinished: {
                            if (value.trim())
                                Config.options.assistant.model = value.trim();
                        }
                    }

                    ConfigTextRow {
                        description: Translation.tr(
                                         "Ollama base URL, full chat completions URL, or Gemini base URL (https://generativelanguage.googleapis.com/v1beta).")
                        label: Translation.tr("Model endpoint")
                        value: Config.options.assistant.endpoint

                        onEditingFinished: Config.options.assistant.endpoint = value.trim()
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.margins: 12
                        spacing: 8
                        visible: Config.options.assistant.provider !== "ollama"

                        ToolbarTextField {
                            id: key

                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: Translation.tr("API key (stored in the system keyring)")
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            RippleButtonWithIcon {
                                enabled: KeyringStorage.loaded && !!key.text.trim()
                                mainText: Translation.tr("Save key")
                                materialIcon: "key"

                                onClicked: {
                                    KeyringStorage.setNestedField(["apiKeys", Config.options.assistant.keyId],
                                                                  key.text.trim());
                                    key.clear();
                                }
                            }

                            RippleButtonWithIcon {
                                enabled: KeyringStorage.loaded
                                mainText: Translation.tr("Remove key")
                                materialIcon: "key_off"

                                onClicked: KeyringStorage.setNestedField(["apiKeys",
                                                                          Config.options.assistant.keyId], "")
                            }
                        }
                    }
                }
            }

            ContentSection {
                description: Assistant.enabled ? Translation.tr(
                                                     "Checking starts the selected model. Downloads can be stopped and resumed later.") :
                                                 Translation.tr(
                                                     "Enable the assistant to check or download its model.")
                icon: "download"
                title: Translation.tr("Check & download")

                Flow {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 8

                    RippleButtonWithIcon {
                        enabled: Assistant.enabled && !Assistant.busy
                        mainText: Translation.tr("Check model")
                        materialIcon: "check_circle"
                        objectName: "assistantCheckModel"
                        visible: !Assistant.busy && (Config.options.assistant.provider !== "ollama"
                                                     || root.localInstalled)

                        onClicked: Assistant.checkModel()
                    }

                    RippleButtonWithIcon {
                        enabled: Assistant.enabled && !Assistant.busy
                        mainText: Assistant.problem ? Translation.tr("Retry download") : Translation.tr(
                                                          "Download model")
                        materialIcon: "download"
                        objectName: "assistantDownloadModel"
                        visible: Config.options.assistant.provider === "ollama" && !Assistant.busy &&
                                 !root.localInstalled

                        onClicked: Assistant.downloadModel()
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Stop")
                        materialIcon: "stop"
                        objectName: "assistantStopModel"
                        visible: Assistant.busy

                        onClicked: Assistant.cancel()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 8
                    visible: Assistant.busy || !!Assistant.problem || !!Assistant.download.status

                    StyledText {
                        Layout.fillWidth: true
                        color: Assistant.problem ? Appearance.colors.colError : Appearance.colors.colSubtext
                        text: Assistant.problem || Assistant.download.status || Translation.tr(
                                  "Checking model…")
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        text: ((Assistant.download.completed ?? 0) / 1.07374e+09).toFixed(2) + " / " + ((
                                                                                                            Assistant.download.total
                                                                                                            ?? 0) / 1.07374e+09).toFixed(
                                  2) + " GiB"
                        visible: Assistant.download.total > 0
                    }

                    StyledProgressBar {
                        Layout.fillWidth: true
                        value: (Assistant.download.completed ?? 0) / Math.max(1, Assistant.download.total
                                                                              ?? 1)
                        visible: Assistant.download.total > 0
                    }

                    StyledIndeterminateProgressBar {
                        Layout.fillWidth: true
                        visible: Assistant.busy && !(Assistant.download.total > 0)
                    }
                }
            }
        }
    }
}
