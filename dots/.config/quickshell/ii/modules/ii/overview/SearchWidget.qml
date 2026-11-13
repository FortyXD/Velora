pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Wrapper
    id: root

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    readonly property int typingResultLimit: 15 // Should be enough to cover the whole view

    property string searchingText: LauncherSearch.query
    property string selectedResultKey: ""
    property int resultsRevision: -1
    property string resultsMode: "auto"
    property bool updatingResults: false
    function updateResults(values) {
        const sameQuery = resultsRevision === LauncherSearch.queryRevision && resultsMode === LauncherSearch.intentMode;
        const key = sameQuery ? selectedResultKey : "";
        const viewportOffset = appResults.contentY - appResults.originY;
        resultsRevision = LauncherSearch.queryRevision;
        resultsMode = LauncherSearch.intentMode;
        updatingResults = true;
        resultModel.values = values;
        const index = key ? values.findIndex(entry => entry.key === key) : -1;
        appResults.currentIndex = key ? index : (values.length ? 0 : -1);
        selectedResultKey = key || values[appResults.currentIndex]?.key || "";
        appResults.forceLayout();
        if (sameQuery) {
            const first = appResults.originY - appResults.topMargin;
            const last = Math.max(first, appResults.originY + appResults.contentHeight - appResults.height + appResults.bottomMargin);
            appResults.contentY = Math.max(first, Math.min(last, appResults.originY + viewportOffset));
            // Ranking can move the retained target offscreen. Keep its identity,
            // but require explicit navigation before it can be activated again.
            if (key && appResults.height > 0 && !appResults.indexVisible(appResults.currentIndex)) appResults.currentIndex = -1;
        } else appResults.positionViewAtBeginning();
        updatingResults = false;
    }
    property bool showResults: searchingText != ""
    implicitWidth: searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: searchWidgetContent.implicitHeight + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2

    function focusFirstItem() {
        appResults.currentIndex = 0;
        appResults.positionViewAtBeginning();
    }

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }

    function cancelSearch() {
        searchBar.searchInput.selectAll();
        LauncherSearch.query = "";
        searchBar.animateWidth = true;
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    Keys.onPressed: event => {
        if (Assistant.panelOpen) return;
        // Prevent Esc and Backspace from registering
        if (event.key === Qt.Key_Escape)
            return;

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    // Delete word before cursor
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        // Find the start of the previous word
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    // Delete character before cursor if any
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                // Always move cursor to end after programmatic edit
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            // If already focused, let TextField handle it
            return;
        }

        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                // Insert the character at the cursor position
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    StyledRectangularShadow {
        target: searchWidgetContent
    }
    Rectangle { // Background
        id: searchWidgetContent
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: Appearance.sizes.elevationMargin
        }
        clip: true
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight
        radius: searchBar.height / 2 + searchBar.verticalPadding
        color: Appearance.colors.colBackgroundSurfaceContainer

        Behavior on implicitHeight {
            id: searchHeightBehavior
            enabled: GlobalStates.overviewOpen && root.showResults
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: columnLayout
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 0

            // clip: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: searchWidgetContent.width
                    height: searchWidgetContent.height
                    radius: searchWidgetContent.radius
                }
            }

            SearchBar {
                id: searchBar
                property real verticalPadding: 4
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 4
                Layout.topMargin: verticalPadding
                Layout.bottomMargin: verticalPadding
                Synchronizer on searchingText {
                    property alias source: root.searchingText
                }
            }

            Rectangle {
                // Separator
                visible: root.showResults
                Layout.fillWidth: true
                height: 1
                color: Appearance.colors.colOutlineVariant
            }

            AssistantPanel {
                id: assistantPanel
                onSearchRequested: root.focusSearchInput()
                Layout.leftMargin: 16; Layout.rightMargin: 16; Layout.bottomMargin: 12
                maximumTranscriptHeight: Math.min(350, Math.max(120, (root.Window.window?.height ?? 800) - 380))
            }

            ListView { // App results
                id: appResults
                objectName: "launcherResults"
                visible: root.showResults && !Assistant.panelOpen
                Layout.fillWidth: true
                implicitHeight: Math.min(600, appResults.contentHeight + topMargin + bottomMargin)
                clip: true
                topMargin: 10
                bottomMargin: 10
                spacing: 2
                KeyNavigation.up: searchBar
                highlightMoveDuration: 100
                highlightFollowsCurrentItem: false

                function indexVisible(index) {
                    const item = itemAtIndex(index);
                    return !!item && item.y + item.height > contentY && item.y < contentY + height;
                }
                function moveSelection(direction) {
                    if (!count) return;
                    let next = currentIndex;
                    if (next < 0 || !indexVisible(next)) {
                        next = 0;
                        for (let y = contentY + 1; y < contentY + height; y += 10) {
                            const visibleIndex = indexAt(width / 2, y);
                            if (visibleIndex >= 0) { next = visibleIndex; break; }
                        }
                    } else next = Math.max(0, Math.min(count - 1, next + direction));
                    currentIndex = next;
                    positionViewAtIndex(next, ListView.Contain);
                }
                onCurrentIndexChanged: {
                    if (!root.updatingResults) {
                        root.selectedResultKey = resultModel.values[currentIndex]?.key ?? "";
                        if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain);
                    }
                }
                Keys.onDownPressed: event => { moveSelection(1); event.accepted = true; }
                Keys.onUpPressed: event => { moveSelection(-1); event.accepted = true; }
                Timer {
                    id: debounceTimer
                    interval: root.typingDebounceInterval
                    onTriggered: {
                        root.updateResults(LauncherSearch.results ?? []);
                    }
                }

                Connections {
                    target: LauncherSearch
                    function onResultsChanged() {
                        const sameQuery = root.resultsRevision === LauncherSearch.queryRevision && root.resultsMode === LauncherSearch.intentMode;
                        const limit = sameQuery ? Math.max(root.typingResultLimit, resultModel.values.length) : root.typingResultLimit;
                        root.updateResults(LauncherSearch.results.slice(0, limit));
                        debounceTimer.restart();
                    }
                }

                model: ScriptModel {
                    id: resultModel
                    objectProp: "key"
                }

                delegate: SearchItem {
                    id: searchItem
                    // The selectable item for each search result
                    required property var modelData
                    anchors.left: parent?.left
                    anchors.right: parent?.right
                    entry: modelData
                    query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            if (LauncherSearch.results.length === 0)
                                return;
                            const tabbedText = searchItem.modelData.name;
                            LauncherSearch.query = tabbedText;
                            searchBar.searchInput.text = tabbedText;
                            event.accepted = true;
                            root.focusSearchInput();
                        }
                    }
                }
            }
        }
    }
}
