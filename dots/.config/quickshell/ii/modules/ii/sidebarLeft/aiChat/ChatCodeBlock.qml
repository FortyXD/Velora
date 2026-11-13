import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import org.kde.syntaxhighlighting

Rectangle {
    id: root
    property string content: ""
    property string language: ""
    property bool copied: false
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.small
    implicitHeight: layout.implicitHeight + 16
    ColumnLayout {
        id: layout
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; Layout.leftMargin: 8; text: root.language || Translation.tr("Plain text"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
            ChatIconButton { symbol: root.copied ? "check" : "content_copy"; tooltip: Translation.tr("Copy code"); onClicked: { Quickshell.clipboardText = root.content; root.copied = true; copiedTimer.restart(); } }
            ChatIconButton { symbol: "save"; tooltip: Translation.tr("Save code as…"); onClicked: saveDialog.open() }
        }
        Flickable {
            id: flick
            objectName: "chatCodeScroll"
            Layout.fillWidth: true
            Layout.preferredHeight: code.implicitHeight + (contentWidth > width ? 12 : 0)
            contentWidth: Math.max(width, code.implicitWidth)
            contentHeight: code.implicitHeight
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            StyledTextArea {
                id: code
                objectName: "chatCodeText"
                width: Math.max(flick.width, implicitWidth)
                text: root.content
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                wrapMode: TextEdit.NoWrap
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
                padding: 8
                background: null
                SyntaxHighlighter { textEdit: code; repository: Repository; definition: Repository.definitionForName(root.language || "plaintext"); theme: Appearance.syntaxHighlightingTheme }
            }
        }
    }
    Timer { id: copiedTimer; interval: 1500; onTriggered: root.copied = false }
    FileDialog {
        id: saveDialog
        fileMode: FileDialog.SaveFile
        title: Translation.tr("Save code as…")
        onAccepted: ChatStore.call("write", {path:decodeURIComponent(String(selectedFile).replace(/^file:\/\//, "")), text:root.content})
    }
}
