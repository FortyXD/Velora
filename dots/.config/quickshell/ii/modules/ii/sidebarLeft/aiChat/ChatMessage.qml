import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    required property var entry
    readonly property var message: entry ?? ({role:"",text:"",model:"",status:"done",attachments:[],steps:[],error:"",source:null,hasActions:false})
    required property int messageIndex
    property bool sourceView: false
    property bool copied: false
    property bool highlighted: false
    readonly property bool user: entry?.role === "user"
    spacing: 8
    opacity: 0
    transform: Translate { id: entrance; y: 10 }
    Component.onCompleted: appear.start()
    ParallelAnimation {
        id: appear
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: Appearance.scaledDuration(220); easing.type: Easing.OutCubic }
        NumberAnimation { target: entrance; property: "y"; to: 0; duration: Appearance.scaledDuration(300); easing.type: Easing.OutCubic }
    }
    Rectangle {
        Layout.fillWidth: true
        visible: root.highlighted
        implicitHeight: 2
        color: Appearance.colors.colPrimary
    }
    StyledText {
        visible: !root.user
        Layout.fillWidth: true
        text: (root.entry?.model ?? "") ? "Velora · " + (Ai.models[(root.entry?.model ?? "")]?.name ?? (root.entry?.model ?? "")) : "Velora"
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
    Rectangle {
        Layout.alignment: root.user ? Qt.AlignRight : Qt.AlignLeft
        Layout.fillWidth: true
        Layout.maximumWidth: root.user ? root.width * 0.92 : root.width
        color: root.user ? Appearance.colors.colLayer2 : "transparent"
        radius: Appearance.rounding.normal
        implicitHeight: body.implicitHeight + (root.user ? 24 : 0)
        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.user ? 12 : 0 }
            spacing: 10
            ChatAttachments { Layout.fillWidth: true; visible: (root.entry?.attachments?.length ?? 0) > 0; paths: root.entry?.attachments ?? [] }
            ChatMarkdown { Layout.fillWidth: true; content: (root.entry?.text ?? ""); sourceView: root.sourceView || root.user; completed: !["waiting", "streaming"].includes((root.entry?.status ?? "done")) }
            StyledText { visible: (root.entry?.status ?? "done") === "waiting" && !(root.entry?.text ?? ""); text: Translation.tr("Preparing a response…"); color: Appearance.colors.colSubtext }
            ChatActionCard { Layout.fillWidth: true; visible: !root.user; entry: root.entry; live: SidebarChat.currentReply === root.entry }
            StyledText { visible: (root.entry?.status ?? "done") === "interrupted"; text: Translation.tr("Response interrupted"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
        }
    }
    RowLayout {
        Layout.alignment: root.user ? Qt.AlignRight : Qt.AlignLeft
        spacing: 0
        ChatIconButton { symbol: root.copied ? "check" : "content_copy"; tooltip: Translation.tr("Copy"); enabled: !!(root.entry?.text ?? ""); onClicked: { Quickshell.clipboardText = (root.entry?.text ?? ""); root.copied = true; copiedTimer.restart(); } }
        ChatIconButton { visible: root.user; symbol: "edit"; tooltip: Translation.tr("Edit in a new conversation"); enabled: !SidebarChat.busy && SidebarChat.compatible; onClicked: SidebarChat.branch(root.messageIndex) }
        ChatIconButton {
            visible: !root.user && SidebarChat.mode === "chat" && !(root.entry?.hasActions ?? false)
            symbol: "refresh"; tooltip: Translation.tr("Try another response")
            enabled: !SidebarChat.busy && SidebarChat.compatible
            onClicked: SidebarChat.retry(root.messageIndex)
        }
        ChatIconButton { visible: !root.user; symbol: "code"; tooltip: Translation.tr("View Markdown source"); toggled: root.sourceView; onClicked: root.sourceView = !root.sourceView }
    }
    Timer { id: copiedTimer; interval: 1500; onTriggered: root.copied = false }
}
