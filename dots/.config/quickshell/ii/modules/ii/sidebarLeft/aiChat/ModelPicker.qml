import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Searchable model list: local Ollama models (smallest first), then cloud models.
 * Type to filter, Up/Down to move, Enter to pick, Esc to close.
 */
Rectangle {
    id: root
    signal closed()

    property string query: ""
    property int selectedIndex: 0
    readonly property bool localOnly: Config.options.policies.ai === 2
    readonly property var entries: {
        const q = root.query.trim().toLowerCase();
        const matches = Ai.modelList
            .filter(id => Ai.models[id])
            .filter(id => {
                const model = Ai.models[id];
                return q.length === 0 || [model.name, model.model, id].some(text => (text ?? "").toLowerCase().includes(q));
            });
        const local = matches.filter(id => Ai.models[id].local).sort((a, b) => Ai.models[a].size - Ai.models[b].size);
        const cloud = matches.filter(id => !Ai.models[id].local);
        return [...local, ...cloud];
    }

    function formatSize(bytes) {
        return bytes > 0 ? `${(bytes / 1e9).toFixed(1)} GB` : "";
    }

    function selectable(id) {
        return Ai.models[id].local || !root.localOnly;
    }

    function choose(id) {
        if (!id || !root.selectable(id)) return;
        Ai.setModel(id, false);
        root.closed();
    }

    function focusSearch() {
        searchField.text = "";
        searchField.forceActiveFocus();
    }

    onEntriesChanged: root.selectedIndex = Math.min(root.selectedIndex, Math.max(0, root.entries.length - 1))

    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    ColumnLayout {
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false // Nested layouts fill height by default
            spacing: 4

            ToolbarTextField {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 36
                placeholderText: Translation.tr("Search models")
                onTextChanged: {
                    root.query = text;
                    root.selectedIndex = 0;
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Down) {
                        root.selectedIndex = Math.min(root.entries.length - 1, root.selectedIndex + 1);
                        modelList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                        modelList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.choose(root.entries[root.selectedIndex]);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.closed();
                        event.accepted = true;
                    }
                }
            }

            RippleButton { // Rescan installed Ollama models
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                onClicked: Ai.refreshLists()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "refresh"
                    color: Appearance.colors.colOnLayer2
                }
                StyledToolTip {
                    text: Translation.tr("Rescan local models")
                }
            }
        }

        StyledListView {
            id: modelList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            popin: false
            model: root.entries

            delegate: Item {
                id: entry
                required property string modelData
                required property int index
                readonly property var model: Ai.models[entry.modelData]
                readonly property bool firstOfGroup: entry.index === 0
                    || (Ai.models[root.entries[entry.index - 1]]?.local ?? false) !== (entry.model?.local ?? false)
                width: ListView.view.width
                implicitHeight: (firstOfGroup ? groupLabel.implicitHeight + 6 : 0) + row.implicitHeight

                StyledText {
                    id: groupLabel
                    visible: entry.firstOfGroup
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: entry.model?.local ? Translation.tr("Local (Ollama)")
                        : (root.localOnly ? Translation.tr("Cloud (disabled: local-only policy)") : Translation.tr("Cloud"))
                }

                RippleButton {
                    id: row
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: rowLayout.implicitHeight + 12
                    leftPadding: 10
                    rightPadding: 10
                    buttonRadius: Appearance.rounding.small
                    enabled: root.selectable(entry.modelData)
                    toggled: entry.modelData === Ai.currentModelId
                    colBackground: entry.index === root.selectedIndex ? Appearance.colors.colLayer2Hover : "transparent"
                    onClicked: root.choose(entry.modelData)
                    onHoveredChanged: if (hovered) root.selectedIndex = entry.index

                    contentItem: RowLayout {
                        id: rowLayout
                        spacing: 10
                        opacity: row.enabled ? 1 : 0.5

                        CustomIcon {
                            Layout.alignment: Qt.AlignVCenter
                            width: Appearance.font.pixelSize.large
                            height: Appearance.font.pixelSize.large
                            source: entry.model?.icon ?? ""
                            colorize: true
                            color: row.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: row.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                text: entry.model?.name ?? entry.modelData
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: row.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                text: entry.model?.local ? entry.model.model
                                    : (entry.model?.requires_key && !(Ai.apiKeys[entry.model.key_id]?.length > 0) ? Translation.tr("Needs an API key") : (entry.model?.model ?? ""))
                            }
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            visible: text.length > 0
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: row.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                            text: root.formatSize(entry.model?.size ?? 0)
                        }
                    }
                }
            }
        }

        StyledText {
            visible: root.entries.length === 0
            Layout.fillWidth: true
            Layout.margins: 8
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Ai.modelList.length === 0
                ? Translation.tr("No models found. Install one with `ollama pull qwen3.5`, then press refresh.")
                : Translation.tr("No model matches “%1”").arg(root.query)
        }
    }
}
