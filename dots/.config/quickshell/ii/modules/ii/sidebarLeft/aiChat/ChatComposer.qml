import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    property alias inputField: input
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal
    implicitHeight: content.implicitHeight + 16
    border.width: input.activeFocus ? 1 : 0
    border.color: Appearance.colors.colOutlineVariant
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 4
        RowLayout {
            visible: SidebarChat.busy
            Layout.fillWidth: true
            Layout.margins: 4
            spacing: 8
            MaterialSymbol {
                text: "progress_activity"; iconSize: 16; color: Appearance.colors.colSubtext
                RotationAnimation on rotation { from: 0; to: 360; duration: 1800; loops: Animation.Infinite; running: SidebarChat.busy }
            }
            StyledText {
                objectName: "sidebarChatStatus"
                Layout.fillWidth: true
                text: SidebarChat.statusText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
            StyledText { text: SidebarChat.elapsedSeconds + " " + Translation.tr("s"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
        }
        ScrollView {
            id: attachmentScroll
            visible: SidebarChat.attachments.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(116, attachmentList.implicitHeight)
            clip: true
            ChatAttachments {
                id: attachmentList
                width: attachmentScroll.availableWidth
                paths: SidebarChat.attachments; removable: true; previews: true
                onRemoved: index => SidebarChat.attachments = SidebarChat.attachments.filter((_, i) => i !== index)
            }
        }
        ScrollView {
            id: inputScroll
            objectName: "sidebarChatInputScroll"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(160, Math.max(48, input.implicitHeight))
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            StyledTextArea {
                id: input
                objectName: "sidebarChatInput"
                width: inputScroll.availableWidth
                text: SidebarChat.draft
                onTextChanged: if (SidebarChat.draft !== text) SidebarChat.draft = text
                wrapMode: TextEdit.Wrap
                font.pixelSize: Appearance.font.pixelSize.normal
                padding: 8
                background: null
                selectByMouse: true
                placeholderText: SidebarChat.busy ? Translation.tr("Write your next message…") : Translation.tr("Ask anything or describe a task…")
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier) && !input.inputMethodComposing) {
                        SidebarChat.send(); event.accepted = true;
                    } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                        const clipboard = Quickshell.clipboardText;
                        if (!(event.modifiers & Qt.ShiftModifier) && clipboard.trim().startsWith("file:///")) {
                            SidebarChat.attach(clipboard.trim().split(/\r?\n/)); event.accepted = true;
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            ChatIconButton {
                symbol: "attach_file"; tooltip: SidebarChat.attachmentLimit ? Translation.tr("Attach files") : Translation.tr("This model does not support file attachments")
                enabled: SidebarChat.attachmentLimit > 0 && SidebarChat.compatible
                onClicked: fileDialog.open()
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Shift+Enter for a new line")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
            ChatIconButton {
                objectName: "sidebarChatSend"
                visible: !SidebarChat.busy
                symbol: "arrow_upward"
                tooltip: Translation.tr("Send")
                enabled: SidebarChat.canSend
                toggled: true
                colBackgroundToggled: Appearance.m3colors.m3onSurface
                colBackgroundToggledHover: Appearance.colors.colSubtext
                foreground: enabled ? Appearance.m3colors.m3surfaceContainer : Appearance.colors.colSubtext
                onClicked: SidebarChat.send()
            }
            RippleButtonWithIcon {
                objectName: "sidebarChatStop"
                visible: SidebarChat.busy
                materialIcon: "stop"; mainText: Translation.tr("Stop")
                colBackground: Appearance.colors.colLayer3
                onClicked: SidebarChat.stop()
            }
        }
    }
    FileDialog {
        id: fileDialog
        title: Translation.tr("Attach files")
        fileMode: SidebarChat.attachmentLimit === 1 ? FileDialog.OpenFile : FileDialog.OpenFiles
        onAccepted: SidebarChat.attach(selectedFiles)
    }
}
