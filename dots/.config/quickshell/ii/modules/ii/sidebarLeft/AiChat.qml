import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.aiChat

Item {
    id: root
    property alias inputField: composer.inputField
    property bool showModelPicker: false
    property bool showHistory: false
    property bool showFind: false
    readonly property bool optionsOpen: settings.visible
    property string query: ""
    property int matchIndex: -1
    readonly property var matches: {
        const needle = query.trim().toLowerCase();
        return needle ? SidebarChat.messages.map((m, i) => m.text.toLowerCase().includes(needle) ? i : -1).filter(i => i >= 0) : [];
    }
    function findNext(direction) {
        if (!matches.length) { matchIndex = -1; return; }
        const current = matches.indexOf(matchIndex);
        matchIndex = matches[(current + direction + matches.length) % matches.length];
        timeline.followTail = false;
        timeline.positionViewAtIndex(matchIndex, ListView.Center);
    }
    onQueryChanged: { matchIndex = -1; findNext(1); }
    onFocusChanged: if (focus) composer.inputField.forceActiveFocus()
    Component.onCompleted: Ai.refreshLists()
    Keys.onPressed: event => {
        if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_F) {
            root.showFind = true; findInput.forceActiveFocus(); event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            SidebarChat.newConversation(); event.accepted = true;
        } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_M && !SidebarChat.busy) {
            root.showModelPicker = !root.showModelPicker; root.showHistory = false; event.accepted = true;
        } else if (event.key === Qt.Key_Escape && (root.showFind || root.showHistory || root.showModelPicker)) {
            root.showFind = false; root.showHistory = false; root.showModelPicker = false; root.query = ""; event.accepted = true;
        }
    }
    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 2
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 48
                enabled: !SidebarChat.busy
                buttonRadius: Appearance.rounding.small
                onClicked: { root.showModelPicker = !root.showModelPicker; root.showHistory = false; Ai.refreshLists(); }
                contentItem: RowLayout {
                    spacing: 6
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        StyledText { Layout.fillWidth: true; text: SidebarChat.modelName; elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold }
                        StyledText { Layout.fillWidth: true; text: (SidebarChat.localModel ? Translation.tr("Local") : Translation.tr("Cloud")) + " · " + (SidebarChat.mode === "assistant" ? Translation.tr("Desktop assistant") : Translation.tr("Chat")); elide: Text.ElideRight; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
                    }
                    MaterialSymbol { text: "expand_more"; iconSize: 18; color: Appearance.colors.colSubtext }
                }
            }
            ChatIconButton { symbol: "history"; tooltip: Translation.tr("Conversations"); toggled: root.showHistory; onClicked: { SidebarChat.save(); root.showHistory = !root.showHistory; root.showModelPicker = false; } }
            ChatIconButton { symbol: "add_comment"; tooltip: Translation.tr("New conversation"); enabled: !SidebarChat.busy; onClicked: { SidebarChat.newConversation(); composer.inputField.forceActiveFocus(); } }
            ChatIconButton {
                id: menuButton
                objectName: "sidebarChatMenu"
                symbol: "more_horiz"
                tooltip: Translation.tr("Chat options")
                toggled: settings.visible
                onClicked: settings.visible ? settings.close() : settings.open()
            }
        }
        RowLayout {
            visible: root.showFind
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 40
            ToolbarTextField { id: findInput; Layout.fillWidth: true; placeholderText: Translation.tr("Find in conversation"); onTextChanged: root.query = text; onAccepted: root.findNext(1) }
            StyledText { text: root.matches.length ? (root.matches.indexOf(root.matchIndex) + 1) + "/" + root.matches.length : "0"; color: Appearance.colors.colSubtext }
            ChatIconButton { symbol: "expand_less"; tooltip: Translation.tr("Previous match"); onClicked: root.findNext(-1) }
            ChatIconButton { symbol: "expand_more"; tooltip: Translation.tr("Next match"); onClicked: root.findNext(1) }
        }
        Item {
            id: area
            Layout.fillWidth: true
            Layout.fillHeight: true
            StyledListView {
                id: timeline
                objectName: "sidebarChatTimeline"
                property bool followTail: true
                anchors.fill: parent
                clip: true
                spacing: 24
                topMargin: 8
                popin: false; animateAppearance: false
                add: null; remove: null; displaced: null; removeDisplaced: null; addDisplaced: null
                model: ScriptModel { values: SidebarChat.messages }
                onMovementStarted: followTail = false
                onMovementEnded: if (atYEnd) followTail = true
                onContentYChanged: { if (moving || wheelArea.gliding) followTail = atYEnd; }
                onContentHeightChanged: if (followTail) Qt.callLater(() => { if (timeline.followTail) timeline.positionViewAtEnd(); })
                onHeightChanged: if (followTail) Qt.callLater(() => { if (timeline.followTail) timeline.positionViewAtEnd(); })
                Connections { target: timeline.wheelArea; function onUserScrolled() { timeline.followTail = timeline.atYEnd; } }
                delegate: Item {
                    required property var modelData
                    required property int index
                    visible: index >= 0
                    width: ListView.view.width
                    implicitHeight: message.implicitHeight
                    ChatMessage {
                        id: message
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, 760)
                        entry: parent.modelData
                        messageIndex: parent.index
                        highlighted: parent.index === root.matchIndex
                    }
                }
            }
            Connections {
                target: SidebarChat
                function onSubmitted() { timeline.followTail = true; Qt.callLater(() => timeline.positionViewAtEnd()); }
                function onInputRequested() { composer.inputField.forceActiveFocus(); composer.inputField.cursorPosition = composer.inputField.length; }
                function onConversationIdChanged() { timeline.followTail = true; root.query = ""; findInput.clear(); }
            }
            ScrollView {
                id: emptyScroll
                anchors.fill: parent
                visible: SidebarChat.messages.length === 0
                clip: true
                ColumnLayout {
                    width: emptyScroll.availableWidth
                    spacing: 12
                    Item { Layout.preferredHeight: Math.max(0, area.height * 0.32) }
                    MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "neurology"; iconSize: 36; color: Appearance.colors.colPrimary }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("What shall we work on?"); font.pixelSize: Appearance.font.pixelSize.larger; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Ask a question, bring a file, or describe a task."); color: Appearance.colors.colSubtext; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }

                }
            }
            RippleButtonWithIcon {
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 8 }
                visible: !timeline.atYEnd && SidebarChat.messages.length > 0
                materialIcon: "arrow_downward"; mainText: Translation.tr("Latest messages")
                colBackground: Appearance.colors.colLayer2Base
                colBackgroundHover: Appearance.colors.colLayer3
                onClicked: { timeline.followTail = true; timeline.positionViewAtEnd(); }
            }
            FadeLoader {
                anchors.fill: parent; shown: root.showHistory
                sourceComponent: ChatHistory { onClosed: { root.showHistory = false; composer.inputField.forceActiveFocus(); } }
            }
            FadeLoader {
                anchors.fill: parent; shown: root.showModelPicker
                sourceComponent: ModelPicker { assistantMode: SidebarChat.mode === "assistant"; Component.onCompleted: focusSearch(); onClosed: { root.showModelPicker = false; composer.inputField.forceActiveFocus(); } }
            }
        }
        StyledText {
            visible: !SidebarChat.compatible
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: Translation.tr("This conversation uses a different mode. Change the assistant setting to continue, or start a new chat.")
            color: Appearance.colors.colSubtext
        }
        StyledText {
            visible: !!text
            Layout.fillWidth: true; wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: SidebarChat.problem || ChatStore.problem
            color: Appearance.colors.colError
        }
        ChatComposer { id: composer; Layout.fillWidth: true; Layout.maximumWidth: 760; Layout.alignment: Qt.AlignHCenter }
    }
    ChatSettings {
        id: settings
        parent: menuButton
        maximumMenuHeight: root.height - 84
        width: Math.min(340, root.width - 32)
        x: menuButton.width - width
        y: menuButton.height + 8
        onSearchRequested: { root.showFind = true; findInput.forceActiveFocus(); }
    }
    DropArea {
        anchors.fill: parent
        onEntered: drag => { drag.accepted = drag.hasUrls; }
        onDropped: drop => { if (drop.hasUrls) { SidebarChat.attach(drop.urls); drop.acceptProposedAction(); } }
        Rectangle {
            anchors.fill: parent
            visible: parent.containsDrag
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSecondaryContainer
            opacity: 0.9
            StyledText { anchors.centerIn: parent; text: Translation.tr("Drop files to attach"); font.pixelSize: Appearance.font.pixelSize.larger }
        }
    }
}
