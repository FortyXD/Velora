pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.waffle.looks
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.waffle.startMenu
import Quickshell
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick

RowLayout {
    id: root

    property int maxResultsPerCategory: 4
    property int resultLimit: 20
    property StartMenuContext context
    property string selectedResultKey: ""
    property int resultsRevision: -1
    property string resultsMode: "auto"
    property bool updatingResults: false
    property int currentIndex: context.currentIndex
    onCurrentIndexChanged: {
        if (!updatingResults) selectedResultKey = resultList.model[currentIndex]?.key ?? "";
        forceCurrentIndex(currentIndex);
    }
    function focusFirstItem() { forceCurrentIndex(0); }
    function forceCurrentIndex(index) {
        if (!context) return;
        context.currentIndex = index;
        resultList.currentIndex = index;
    }
    function updateResults(values) {
        if (!resultList || !context) return;
        const key = resultsRevision === LauncherSearch.queryRevision && resultsMode === LauncherSearch.intentMode ? selectedResultKey : "";
        resultsRevision = LauncherSearch.queryRevision;
        resultsMode = LauncherSearch.intentMode;
        const previous = resultList.model ?? [];
        const byKey = new Map(previous.map(entry => [entry.key, entry]));
        const categories = Array.from(new Set(values.map(entry => entry.type)));
        const next = [];
        updatingResults = true;
        for (const category of categories) {
            let count = 0;
            for (const entry of values) {
                if (entry.type !== category) continue;
                if (next.length >= resultLimit || count >= maxResultsPerCategory) break;
                const row = byKey.get(entry.key) ?? searchResultComp.createObject(root);
                byKey.delete(entry.key);
                for (const field of ["id", "key", "name", "type", "rawValue", "fontType", "iconName", "iconType", "verb", "blurImage", "actions", "desktopId", "keepOpen", "shown", "comment", "lensPath", "preview", "runInTerminal", "genericName", "keywords"])
                    row[field] = entry[field];
                row.execute = entry.execute;
                row.category = next.length === 0 ? Translation.tr("Best match") : entry.type;
                next.push(row);
                count++;
            }
        }
        resultList.model = next;
        const index = key ? next.findIndex(entry => entry.key === key) : -1;
        forceCurrentIndex(key ? index : (next.length ? 0 : -1));
        selectedResultKey = key || next[context.currentIndex]?.key || "";
        updatingResults = false;
        for (const row of byKey.values()) { row.execute = () => {}; row.destroy(); }
    }
    Component.onCompleted: updateResults(LauncherSearch.results)
    onResultLimitChanged: updateResults(LauncherSearch.results)
    onMaxResultsPerCategoryChanged: updateResults(LauncherSearch.results)

    Connections {
        target: context
        function onAccepted() {
            if (!Assistant.panelOpen) resultList.currentItem?.execute();
        }
    }

    Connections {
        target: LauncherSearch
        function onResultsChanged() { root.updateResults(LauncherSearch.results); }
    }
    LauncherSearchResult { id: emptyResult }
    AssistantPanel {
        Layout.fillWidth: true; Layout.fillHeight: false; Layout.alignment: Qt.AlignTop
        onSearchRequested: root.context.searchRequested()
    }
    ResultList {
        id: resultList
        visible: !Assistant.panelOpen
        Layout.fillHeight: true
        Layout.fillWidth: true
    }
    ResultPreview {
        visible: !Assistant.panelOpen
        Layout.preferredWidth: 386
        Layout.leftMargin: 1
        Layout.rightMargin: 1
        entry: resultList.model[resultList.currentIndex] ?? emptyResult
    }

    component ResultList: WListView {
        id: resultListView
        section {
            criteria: ViewSection.FullString
            property: "category" // This is "type" with tweaks to make it match more closely
            labelPositioning: ViewSection.InlineLabels
            delegate: Item {
                id: sectionButton
                required property string section
                implicitHeight: sectionChoiceButton.implicitHeight + resultListView.spacing
                width: ListView.view?.width
                WChoiceButton {
                    id: sectionChoiceButton
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    implicitHeight: 38
                    contentItem: WText {
                        text: sectionButton.section
                        font.pixelSize: Looks.font.pixelSize.large
                        font.weight: Looks.font.weight.strong
                    }
                    onClicked: {
                        root.context.selectCategory(sectionButton.section);
                    }
                }
            }
        }
        clip: true
        spacing: 4
        currentIndex: root.currentIndex

        objectName: "launcherResults"
        // A plain array retains section headers; rows are reused by stable key.
        model: []
        delegate: SearchResultButton {
            required property int index
            required property var modelData
            entry: modelData
            firstEntry: index === 0
            width: ListView.view?.width
            checked: resultListView.currentIndex === index
            onRequestFocus: {
                root.forceCurrentIndex(index);
            }
        }
    }

    component ResultPreview: Rectangle {
        id: resultPreview

        property LauncherSearchResult entry // LauncherSearchResult

        Layout.fillHeight: true
        color: Looks.colors.bg1
        radius: Looks.radius.large

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 13

            ColumnLayout {
                id: mainInfoColumn
                Layout.alignment: Qt.AlignHCenter
                SearchEntryIcon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 10
                    Layout.bottomMargin: 12
                    entry: resultPreview.entry
                    iconSize: 64
                }
                WText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    text: resultPreview.entry?.name || ""
                    font.pixelSize: Looks.font.pixelSize.xlarger
                }
                WText {
                    Layout.alignment: Qt.AlignHCenter
                    text: resultPreview.entry?.type || ""
                    color: Looks.colors.accentUnfocused
                    font.pixelSize: Looks.font.pixelSize.normal
                }
            }
            Rectangle {
                id: resultSeparator
                implicitHeight: 2
                Layout.topMargin: 16
                Layout.fillWidth: true
                color: Looks.colors.bg2Hover
            }
            WListView {
                id: actionsColumn
                Layout.fillHeight: true
                Layout.fillWidth: true
                clip: true
                spacing: 2
                model: {
                    const isAppEntry = resultPreview.entry.type === Translation.tr("App");
                    const appId = isAppEntry ? resultPreview.entry.id : "";
                    const pinned = isAppEntry ? (Config.options.dock.pinnedApps.includes(appId)) : false;
                    const startPinned = isAppEntry ? (Config.options.launcher.pinnedApps.includes(appId)) : false;
                    var result = [
                        searchResultComp.createObject(null, {
                            name: resultPreview.entry.verb,
                            iconName: isAppEntry ? "open_in_new" : "keyboard_return",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                resultPreview.entry.execute();
                            }
                        }),
                        ...(isAppEntry ? [
                            searchResultComp.createObject(null, {
                                name: startPinned ? Translation.tr("Unpin from Start") : Translation.tr("Pin to Start"),
                                iconName: startPinned ? "keep_off" : "keep",
                                iconType: LauncherSearchResult.IconType.Material,
                                execute: () => {
                                    LauncherApps.togglePin(appId);
                                }
                            })
                        ] : []),
                        ...(isAppEntry ? [
                            searchResultComp.createObject(null, {
                                name: pinned ? Translation.tr("Unpin from taskbar") : Translation.tr("Pin to taskbar"),
                                iconName: pinned ? "keep_off" : "keep",
                                iconType: LauncherSearchResult.IconType.Material,
                                execute: () => {
                                    TaskbarApps.togglePin(appId);
                                }
                            })
                        ] : []),
                    ];
                    result = result.concat(resultPreview.entry.actions);
                    return result;
                }
                delegate: WButton {
                    id: actionButton
                    required property var modelData
                    width: ListView.view?.width
                    icon.name: modelData.iconName
                    text: modelData.name
                    onClicked: modelData.execute();

                    contentItem: RowLayout {
                        spacing: 11
                        SearchEntryIcon {
                            entry: actionButton.modelData
                            iconSize: 16
                        }
                        WText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft
                            text: actionButton.text
                        }
                    }
                }
            }
        }
    }

    Component {
        id: searchResultComp
        LauncherSearchResult {}
    }
}
