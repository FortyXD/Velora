import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    signal closed()
    property string editingId: ""
    property string deletingId: ""
    property string menuId: ""
    property string exportId: ""
    color: Appearance.colors.colLayer1Base
    radius: Appearance.rounding.normal
    Component.onCompleted: { ChatStore.refresh(); search.forceActiveFocus(); }
    Keys.onEscapePressed: closed()
    ColumnLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            StyledText { Layout.fillWidth: true; text: Translation.tr("Conversations"); font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold }
            StyledText { text: ChatStore.chats.length; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
            ChatIconButton { symbol: "close"; tooltip: Translation.tr("Close"); onClicked: root.closed() }
        }
        ToolbarTextField {
            id: search
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 40
            Layout.maximumHeight: 40
            implicitHeight: 40
            placeholderText: Translation.tr("Search conversations…")
            text: ChatStore.query
            onTextChanged: ChatStore.query = text
        }
        StyledListView {
            id: list
            Layout.fillWidth: true; Layout.fillHeight: true
            model: ChatStore.chats
            clip: true; spacing: 2; popin: false; animateAppearance: false
            add: null; remove: null
            delegate: ColumnLayout {
                id: row
                required property var modelData
                required property int index
                width: list.width
                spacing: 4
                opacity: 0
                transform: Translate { id: entrance; y: 10 }
                Component.onCompleted: appear.start()
                SequentialAnimation {
                    id: appear
                    PauseAnimation { duration: Appearance.scaledDuration(Math.min(row.index, 6) * 30) }
                    ParallelAnimation {
                        NumberAnimation { target: row; property: "opacity"; to: 1; duration: Appearance.scaledDuration(220); easing.type: Easing.OutCubic }
                        NumberAnimation { target: entrance; property: "y"; to: 0; duration: Appearance.scaledDuration(300); easing.type: Easing.OutCubic }
                    }
                }
                RippleButton {
                    id: openButton
                    Layout.fillWidth: true
                    implicitHeight: 68
                    buttonRadius: Appearance.rounding.small
                    colBackground: row.modelData.id === SidebarChat.conversationId ? Appearance.colors.colLayer2 : "transparent"
                    enabled: !SidebarChat.busy
                    onClicked: { SidebarChat.openConversation(row.modelData.id); root.closed(); }
                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol { text: row.modelData.mode === "assistant" ? "task_alt" : "chat_bubble_outline"; iconSize: 19; color: Appearance.colors.colSubtext }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                Layout.fillWidth: true; text: row.modelData.title || Translation.tr("New conversation")
                                elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: row.modelData.id === SidebarChat.conversationId ? Font.DemiBold : Font.Normal
                                color: Appearance.m3colors.m3onSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: new Date(row.modelData.updatedAt).toLocaleString(Qt.locale(Config.options.language.ui === "auto" ? "" : Config.options.language.ui), "dd MMM · hh:mm")
                                color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        ChatIconButton {
                            symbol: "more_horiz"; tooltip: Translation.tr("Conversation actions")
                            opacity: openButton.hovered || root.menuId === row.modelData.id || activeFocus ? 1 : 0.35
                            Behavior on opacity { NumberAnimation { duration: Appearance.scaledDuration(140) } }
                            onClicked: { root.menuId = root.menuId === row.modelData.id ? "" : row.modelData.id; root.editingId = ""; root.deletingId = ""; }
                        }
                    }
                }
                Flow {
                    visible: root.menuId === row.modelData.id
                    Layout.fillWidth: true
                    spacing: 6
                    RippleButtonWithIcon { materialIcon: "edit"; mainText: Translation.tr("Rename"); onClicked: { root.editingId = row.modelData.id; rename.text = row.modelData.title; rename.forceActiveFocus(); } }
                    RippleButtonWithIcon { materialIcon: "download"; mainText: Translation.tr("Export"); onClicked: { SidebarChat.save(); root.exportId = row.modelData.id; exportDialog.open(); } }
                    RippleButtonWithIcon { materialIcon: "delete"; mainText: Translation.tr("Delete"); onClicked: root.deletingId = row.modelData.id }
                }
                RowLayout {
                    visible: root.editingId === row.modelData.id
                    Layout.fillWidth: true
                    ToolbarTextField { id: rename; Layout.fillWidth: true; onAccepted: { SidebarChat.rename(row.modelData.id, text); root.editingId = ""; root.menuId = ""; } }
                    ChatIconButton { symbol: "check"; tooltip: Translation.tr("Save"); onClicked: { SidebarChat.rename(row.modelData.id, rename.text); root.editingId = ""; root.menuId = ""; } }
                    ChatIconButton { symbol: "close"; tooltip: Translation.tr("Cancel"); onClicked: root.editingId = "" }
                }
                ColumnLayout {
                    visible: root.deletingId === row.modelData.id
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Delete this saved conversation?"); wrapMode: Text.Wrap }
                    RowLayout {
                        RippleButtonWithIcon { materialIcon: "delete"; mainText: Translation.tr("Delete"); onClicked: { SidebarChat.remove(row.modelData.id); root.deletingId = ""; root.menuId = ""; } }
                        RippleButtonWithIcon { materialIcon: "close"; mainText: Translation.tr("Cancel"); onClicked: root.deletingId = "" }
                    }
                }
            }
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 24
                visible: !ChatStore.chats.length
                spacing: 12
                MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "forum"; iconSize: 28; color: Appearance.colors.colSubtext }
                StyledText { Layout.fillWidth: true; text: Translation.tr("No conversations found"); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; color: Appearance.colors.colSubtext }
            }
        }
    }
    FileDialog {
        id: exportDialog
        fileMode: FileDialog.SaveFile
        title: Translation.tr("Export as Markdown")
        nameFilters: ["Markdown (*.md)"]
        defaultSuffix: "md"
        onAccepted: ChatStore.call("export", {id:root.exportId, path:decodeURIComponent(String(selectedFile).replace(/^file:\/\//, ""))})
    }
}
