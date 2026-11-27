import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.apps

SettingsPanePopup {
    id: root
    width: Math.min(460, Math.max(0, (parent?.width ?? 500) - 40))
    height: Math.min(520, Math.max(0, (parent?.height ?? 560) - 40))
    padding: 16

    property string title: ""
    property string description: ""
    property string fileName: ""
    property list<string> excludedIds: []
    property var entries: DesktopEntries.applications.values
    property string currentId: ""
    property bool sorted: true
    property var entryDetail: entry => ""
    property var groupForEntry: null
    signal picked(var entry)

    readonly property var apps: {
        if (!visible) return [];
        const query = searchField.text.trim().toLowerCase();
        const excluded = root.excludedIds.map(id => id.toLowerCase());
        const filtered = root.entries.filter(entry => !entry.noDisplay && !excluded.includes(entry.id.toLowerCase())
            && (!query || [entry.name, entry.id, root.entryDetail(entry)].join(" ").toLowerCase().includes(query)));
        return root.sorted ? filtered.sort((a, b) => a.name.localeCompare(b.name)) : filtered;
    }

    function choose(index) {
        const entry = root.apps[index];
        if (!entry) return;
        root.picked(entry);
        root.close();
    }
    function moveSelection(delta) {
        choices.currentIndex = Math.max(0, Math.min(root.apps.length - 1, choices.currentIndex + delta));
        choices.positionViewAtIndex(choices.currentIndex, ListView.Contain);
    }
    onAboutToShow: searchField.clear()
    onOpened: {
        choices.currentIndex = Math.max(0, root.apps.findIndex(entry => entry.id === root.currentId));
        choices.positionViewAtIndex(choices.currentIndex, ListView.Contain);
        searchField.forceActiveFocus();
    }

    background: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }
    contentItem: ColumnLayout {
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: root.title
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
            }
            SettingsAction {
                implicitWidth: 32
                implicitHeight: 32
                text: Translation.tr("Close")
                onClicked: root.close()
                contentItem: MaterialSymbol { text: "close"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: !!root.fileName || !!root.description
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                visible: !!root.fileName
                spacing: 6
                MaterialSymbol { text: "draft"; iconSize: 17; color: Appearance.colors.colPrimary }
                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.fileName
                    textFormat: Text.PlainText
                    maximumLineCount: 1
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: !!root.description
                text: root.description
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallie
            }
        }
        AppSearchField {
            id: searchField
            objectName: "appPickerSearch"
            Layout.fillWidth: true
            placeholderText: Translation.tr("Search apps")
            onTextChanged: choices.currentIndex = 0
            Keys.onDownPressed: root.moveSelection(1)
            Keys.onUpPressed: root.moveSelection(-1)
            onAccepted: root.choose(choices.currentIndex)
            Keys.onEscapePressed: root.close()
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            StyledListView {
                id: choices
                anchors.fill: parent
                clip: true
                spacing: 2
                model: root.apps
                animateAppearance: false
                Keys.onReturnPressed: root.choose(currentIndex)
                Keys.onEnterPressed: root.choose(currentIndex)
                delegate: Column {
                    id: choice
                    required property var modelData
                    required property int index
                    readonly property string heading: {
                        if (!root.groupForEntry || searchField.text.trim()) return "";
                        const group = root.groupForEntry(modelData);
                        return index > 0 && group === root.groupForEntry(root.apps[index - 1]) ? "" : group;
                    }
                    width: ListView.view.width
                    StyledText {
                        visible: !!choice.heading
                        width: parent.width
                        leftPadding: 6
                        topPadding: 4
                        bottomPadding: 4
                        text: choice.heading
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                    }
                    SettingsAction {
                        id: row
                        readonly property string detail: root.entryDetail(choice.modelData)
                        readonly property bool chosen: choice.modelData.id === root.currentId
                        objectName: "picker-" + choice.modelData.id
                        width: choice.width
                        implicitHeight: detail ? 52 : 44
                        text: choice.modelData.name
                        Accessible.description: detail
                        Accessible.selected: chosen
                        buttonRadius: Appearance.rounding.small
                        colBackground: choice.ListView.isCurrentItem ? Appearance.colors.colSecondaryContainer : "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        onClicked: root.choose(choice.index)
                        contentItem: RowLayout {
                            spacing: 10
                            AppChoiceIcon {
                                icon: choice.modelData.icon ?? ""
                                symbol: choice.modelData.symbol ?? ""
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText { Layout.fillWidth: true; text: row.text; textFormat: Text.PlainText; elide: Text.ElideRight }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: !!row.detail
                                    text: row.detail
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            MaterialSymbol { visible: row.chosen; text: "check"; iconSize: 19; color: Appearance.colors.colPrimary }
                        }
                    }
                }
            }
            StyledText {
                anchors.centerIn: parent
                visible: root.apps.length === 0
                text: Translation.tr("No app matches your search")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
