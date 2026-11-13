import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    readonly property string credential: AiConnections.keyId(providerId, endpoint.value.trim())
    property string currentPage: "models"
    property string deletingId: ""
    property string editingId: ""
    property alias editorItem: editor
    readonly property bool editorOpen: root.currentPage === "connection"
    readonly property bool hasKey: !!KeyringStorage.keyringData?.apiKeys?.[credential]
    default property alias localContent: localContent.data
    property bool pageShown: true
    readonly property var provider: AiConnections.providers.find(p => p.id === providerId)
                                    ?? AiConnections.providers[0]
    property string providerId: "openai"
    property string removingKey: ""

    signal editorClosed
    signal editorRequested
    signal pageRequested(string key)

    function closeEditor() {
        apiKey.clear();
        root.editorClosed();
    }
    function openEditor(record) {
        AiConnections.problem = "";
        AiConnections.notice = "";
        editingId = record ? AiConnections.recordId(record) : "";
        providerId = record?.providerId || (AiConnections.providers.some(p => p.id === record?.key_id) ? record.key_id :
                                                                                                         record ? "custom" :
                                                                                                                  "openai");
        displayName.value = record?.name ?? "";
        model.value = record?.model ?? "";
        endpoint.value = record?.endpoint ?? "";
        apiKey.clear();
        AiConnections.ensureKeyring();
        root.editorRequested();
        Qt.callLater(() => model.textField.forceActiveFocus());
    }
    function save() {
        AiConnections.saveConnection(providerId, displayName.value, model.value, endpoint.value, apiKey.text,
                                     editingId);
        apiKey.clear();
    }

    Layout.fillWidth: true

    Component.onCompleted: if (pageShown)
                               AiConnections.ensureKeyring()
    onCurrentPageChanged: {
        apiKey.clear();
        root.removingKey = "";
        root.deletingId = "";
    }
    onPageShownChanged: {
        if (pageShown)
            AiConnections.ensureKeyring();
        else
            apiKey.clear();
    }

    Connections {
        function onSaved(id) {
            root.editingId = "";
            apiKey.clear();
            root.editorClosed();
        }

        target: AiConnections
    }

    SettingsTabPage {
        anchors.fill: parent
        current: root.currentPage
        enabled: shown
        key: "models"

        onRevealRequested: key => root.pageRequested(key)

        SettingsScrollPane {
            anchors.fill: parent

            ColumnLayout {
                id: localContent

                Layout.fillWidth: true
                spacing: 18
            }

            ContentSection {
                description: Translation.tr(
                                 "API keys are stored in your system keyring. Adding a connection does not send a request.")
                icon: "key"
                title: Translation.tr("AI connections")

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: Translation.tr("Your providers")
                    }

                    RippleButtonWithIcon {
                        enabled: !AiConnections.saving
                        mainText: Translation.tr("Add connection")
                        materialIcon: "add"
                        objectName: "settingsAddAiConnection"

                        onClicked: {
                            forceActiveFocus();
                            root.openEditor(null);
                        }
                    }
                }

                Repeater {
                    model: AiConnections.records

                    delegate: ColumnLayout {
                        id: row

                        readonly property string connectionId: AiConnections.recordId(modelData)
                        readonly property bool forActions: Config.options.assistant.model === modelData.model
                                                           && Config.options.assistant.endpoint
                                                           === modelData.endpoint
                        readonly property bool forChat: Ai.currentModelId === connectionId
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true

                            ConfigNavRow {
                                buttonIcon: "cloud"
                                description: (KeyringStorage.keyringData?.apiKeys?.[row.modelData.key_id]
                                              ? Translation.tr("Key saved") : Translation.tr(
                                                    "Needs an API key")) + (row.forChat ? " · "
                                                                                          + Translation.tr(
                                                                                              "Chat") : "") + (
                                                 row.forActions ? " · " + Translation.tr("Desktop actions") :
                                                                  "")
                                enabled: !AiConnections.saving
                                objectName: "aiConnectionRow"
                                title: row.modelData.name || row.modelData.model

                                onClicked: {
                                    forceActiveFocus();
                                    root.openEditor(row.modelData);
                                }
                            }

                            ChoiceDropdown {
                                Accessible.name: Translation.tr("Connection actions")
                                Layout.rightMargin: 8
                                displayIcon: "more_horiz"
                                displayText: ""
                                enabled: !AiConnections.saving
                                maximumWidth: 80
                                minimumWidth: 80
                                objectName: "aiConnectionMenu"
                                options: [...(Ai.modelAllowed(Ai.models[row.connectionId]) && !Ai.generating
                                              ? [
                                                    {
                                                        value: "chat",
                                                        displayName: Translation.tr("Use for chat"),
                                                        icon: "chat"
                                                    }
                                                ] : []), ...(Ai.modelAllowed(Ai.models[row.connectionId]) &&
                                                             !Assistant.busy ? [
                                                                                   {
                                                                                       value: "actions",
                                                                                       displayName:
                                                                                       Translation.tr(
                                                                                           "Use for actions"),
                                                                                       icon: "touch_app"
                                                                                   }
                                                                               ] : []),
                                    {
                                        value: "remove",
                                        displayName: Translation.tr("Remove"),
                                        icon: "delete"
                                    }
                                ]

                                onSelected: value => {
                                    if (value === "chat")
                                        Ai.setModel(row.connectionId, false);
                                    else if (value === "actions")
                                        AiConnections.useForAssistant(row.connectionId);
                                    else
                                        root.deletingId = row.connectionId;
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: 12
                            visible: root.deletingId === row.connectionId

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Remove this connection? Saved chats will remain.")
                                wrapMode: Text.Wrap
                            }

                            RippleButtonWithIcon {
                                mainText: Translation.tr("Remove")
                                materialIcon: "delete"
                                objectName: "confirmRemoveAiConnection"

                                onClicked: {
                                    const id = row.connectionId;
                                    root.deletingId = "";
                                    AiConnections.remove(id);
                                }
                            }

                            RippleButtonWithIcon {
                                mainText: Translation.tr("Cancel")
                                materialIcon: "close"

                                onClicked: root.deletingId = ""
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Add a provider to use cloud models in the chat.")
                    visible: !AiConnections.records.length
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    color: Appearance.colors.colSubtext
                    text: AiConnections.notice
                    visible: !!AiConnections.notice
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    SettingsTabPage {
        anchors.fill: parent
        current: root.currentPage
        enabled: shown
        key: "connection"

        onRevealRequested: key => root.editorRequested()

        SettingsScrollPane {
            anchors.fill: parent

            ContentSection {
                id: editor

                function settingsReveal() {
                    if (root.editorOpen)
                        return false;
                    root.editorRequested();
                    return true;
                }

                icon: "add_link"
                objectName: "aiConnectionEditor"
                title: root.editingId ? Translation.tr("Edit connection") : Translation.tr("Add connection")

                ConfigComboRow {
                    currentValue: root.providerId
                    icon: "cloud"
                    objectName: "aiProviderChoice"
                    options: AiConnections.providers.map(p => ({
                        value: p.id,
                        displayName: p.id === "custom" ? Translation.tr("Other compatible API") : p.name
                    }))
                    text: Translation.tr("Provider")

                    onSelected: value => {
                        root.providerId = value;
                        apiKey.clear();
                        root.removingKey = "";
                    }
                }

                ConfigTextRow {
                    id: model

                    description: Translation.tr("Copy the model ID from your provider's model catalogue.")
                    icon: "neurology"
                    label: Translation.tr("Model ID")
                    objectName: "aiConnectionModel"
                    placeholderText: Translation.tr("Model ID")
                    wrapMode: TextEdit.NoWrap
                }

                ConfigExpander {
                    title: Translation.tr("More options")

                    ConfigTextRow {
                        id: displayName

                        label: Translation.tr("Display name (optional)")
                        objectName: "aiConnectionName"
                        placeholderText: Translation.tr("Provider and model name")
                        wrapMode: TextEdit.NoWrap
                    }
                }

                ConfigTextRow {
                    id: endpoint

                    label: Translation.tr("Chat Completions URL")
                    objectName: "aiConnectionEndpoint"
                    placeholderText: "https://example.com/v1/chat/completions"
                    visible: root.providerId === "custom"
                    wrapMode: TextEdit.NoWrap
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 8

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("API key")
                    }

                    ToolbarTextField {
                        id: apiKey

                        Layout.fillHeight: false
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        echoMode: TextInput.Password
                        objectName: "aiConnectionKey"
                        placeholderText: root.hasKey ? Translation.tr("Key saved · leave empty to keep it") :
                                                       Translation.tr("Paste API key")

                        onAccepted: root.save()
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        RippleButtonWithIcon {
                            mainText: Translation.tr("Get an API key")
                            materialIcon: "open_in_new"
                            visible: !!root.provider.keyUrl

                            onClicked: Qt.openUrlExternally(root.provider.keyUrl)
                        }

                        RippleButtonWithIcon {
                            mainText: Translation.tr("Model catalogue")
                            materialIcon: "neurology"
                            visible: !!root.provider.modelsUrl

                            onClicked: Qt.openUrlExternally(root.provider.modelsUrl)
                        }
                    }

                    ConfigExpander {
                        title: Translation.tr("Key management")
                        visible: root.hasKey

                        RippleButtonWithIcon {
                            mainText: Translation.tr("Remove key")
                            materialIcon: "key_off"
                            visible: root.hasKey

                            onClicked: root.removingKey = root.credential
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: !!root.removingKey

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Remove the shared key for this provider?")
                                wrapMode: Text.Wrap
                            }

                            RippleButtonWithIcon {
                                mainText: Translation.tr("Remove")
                                materialIcon: "delete"

                                onClicked: {
                                    AiConnections.removeKey(root.removingKey);
                                    root.removingKey = "";
                                }
                            }

                            RippleButtonWithIcon {
                                mainText: Translation.tr("Cancel")
                                materialIcon: "close"

                                onClicked: root.removingKey = ""
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Cloud connections are disabled by your AI access setting.")
                        visible: Config.options.policies.ai !== 1
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colError
                        text: AiConnections.problem
                        visible: !!AiConnections.problem
                        wrapMode: Text.Wrap
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        RippleButtonWithIcon {
                            enabled: !AiConnections.saving && !!model.value.trim() && KeyringStorage.loaded
                            mainText: AiConnections.saving ? Translation.tr("Saving…") : Translation.tr(
                                                                 "Save connection")
                            materialIcon: "check"
                            objectName: "saveAiConnection"

                            onClicked: root.save()
                        }

                        RippleButtonWithIcon {
                            enabled: !AiConnections.saving
                            mainText: Translation.tr("Cancel")
                            materialIcon: "close"

                            onClicked: root.closeEditor()
                        }

                        RippleButtonWithIcon {
                            enabled: !KeyringStorage.fetching
                            mainText: Translation.tr("Unlock keyring")
                            materialIcon: "lock_open"
                            visible: !KeyringStorage.loaded

                            onClicked: AiConnections.ensureKeyring()
                        }
                    }
                }
            }
        }
    }
}
