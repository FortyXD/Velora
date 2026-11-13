import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "ChatMarkdown.js" as Markdown

ColumnLayout {
    id: root
    property string content: ""
    property bool completed: true
    property bool sourceView: false
    spacing: 14
    function update() {
        const values = sourceView ? [{kind:"text", body:content, language:"", complete:true}] : Markdown.parse(content);
        while (blocks.count > values.length) blocks.remove(blocks.count - 1);
        for (let i = 0; i < values.length; i++) {
            if (i < blocks.count) blocks.set(i, values[i]); else blocks.append(values[i]);
        }
    }
    onContentChanged: update()
    onSourceViewChanged: update()
    Component.onCompleted: update()
    ListModel { id: blocks }
    Repeater {
        model: blocks
        delegate: Loader {
            id: block
            required property int index
            required property string kind
            required property string body
            required property string language
            required property bool complete
            Layout.fillWidth: true
            Layout.topMargin: kind === "heading" && index > 0 ? 8 : 0
            opacity: 0
            transform: Translate { id: entrance; y: 5 }
            Component.onCompleted: appear.start()
            ParallelAnimation {
                id: appear
                NumberAnimation { target: block; property: "opacity"; to: 1; duration: Appearance.scaledDuration(200); easing.type: Easing.OutCubic }
                NumberAnimation { target: entrance; property: "y"; to: 0; duration: Appearance.scaledDuration(260); easing.type: Easing.OutCubic }
            }
            sourceComponent: kind === "code" ? codeComponent : kind === "think" ? thinkComponent : kind === "table" ? tableComponent : kind === "quote" ? quoteComponent : textComponent
            Component { id: textComponent; ChatTextBlock { content: block.body; completed: root.completed; markdown: !root.sourceView; headingLevel: block.kind === "heading" ? Number(block.language) : 0 } }
            Component { id: codeComponent; ChatCodeBlock { content: block.body; language: block.language } }
            Component {
                id: quoteComponent
                RowLayout {
                    spacing: 12
                    Rectangle { Layout.fillHeight: true; implicitWidth: 3; radius: 1.5; color: Appearance.colors.colOutlineVariant }
                    ChatTextBlock { Layout.fillWidth: true; content: block.body; completed: root.completed; color: Appearance.colors.colSubtext }
                }
            }
            Component {
                id: thinkComponent
                ColumnLayout {
                    id: reasoning
                    property bool expanded: Config.options.sidebar.ai.showThoughts ?? false
                    spacing: 8
                    RippleButton {
                        objectName: "sidebarChatReasoning"
                        Layout.fillWidth: true
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.small
                        onClicked: reasoning.expanded = !reasoning.expanded
                        contentItem: RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "neurology"; iconSize: 18; color: Appearance.colors.colSubtext }
                            StyledText {
                                Layout.fillWidth: true
                                text: block.complete || root.completed ? Translation.tr("Reasoning") : Translation.tr("Thinking…")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                text: "expand_more"; iconSize: 20; color: Appearance.colors.colSubtext
                                rotation: reasoning.expanded ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Appearance.scaledDuration(260); easing.type: Easing.InOutCubic } }
                            }
                        }
                    }
                    ChatReveal {
                        objectName: "sidebarChatReasoningBody"
                        Layout.fillWidth: true
                        expanded: reasoning.expanded
                        ChatTextBlock { Layout.fillWidth: true; content: block.body; completed: root.completed; color: Appearance.colors.colSubtext }
                    }
                }
            }
            Component {
                id: tableComponent
                Flickable {
                    id: tableFlick
                    objectName: "chatTableScroll"
                    implicitHeight: tableText.implicitHeight + (contentWidth > width ? 14 : 0)
                    contentWidth: Math.max(width, tableText.implicitWidth)
                    contentHeight: tableText.implicitHeight
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                    ChatTextBlock { id: tableText; width: Math.max(tableFlick.width, implicitWidth); wrapMode: TextEdit.NoWrap; content: block.body; completed: root.completed }
                }
            }
        }
    }
}
