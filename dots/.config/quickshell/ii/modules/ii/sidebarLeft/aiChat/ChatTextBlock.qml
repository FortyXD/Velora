import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "ChatMarkdown.js" as Markdown

StyledTextArea {
    id: root
    objectName: "chatProse"
    property string content: ""
    property bool markdown: true
    property bool completed: true
    property int headingLevel: 0
    property var renderHashes: ({})
    property string rendered: ""
    readOnly: true
    selectByMouse: true
    persistentSelection: true
    padding: 0
    background: null
    wrapMode: TextEdit.Wrap
    font.family: headingLevel ? Appearance.font.family.title : Appearance.font.family.main
    font.pixelSize: Appearance.font.pixelSize.normal + (headingLevel === 1 ? 7 : headingLevel === 2 ? 4 : headingLevel ? 2 : 0)
    font.weight: headingLevel ? Font.DemiBold : Font.Normal
    font.variableAxes: ({"wght": headingLevel ? 580 : 400, "wdth": 100})
    font.letterSpacing: headingLevel ? -0.25 : 0.1
    font.kerning: true
    color: Appearance.m3colors.m3onSurface
    textFormat: markdown ? TextEdit.MarkdownText : TextEdit.PlainText
    text: markdown ? rendered : content
    function refresh() {
        const hashes = {};
        let value = "", start = 0;
        for (const span of markdown ? Markdown.mathSpans(content) : []) {
            const expression = span.expression;
            const hash = hashes[expression] ?? renderHashes[expression] ?? LatexRenderer.requestRender(expression)[0];
            hashes[expression] = hash;
            const path = LatexRenderer.renderedImagePaths[hash];
            if (path) {
                value += Markdown.safeMarkdown(content.slice(start, span.start)) + "![formula](<" + path + ">)";
                start = span.end;
            }
        }
        renderHashes = hashes;
        rendered = value + Markdown.safeMarkdown(content.slice(start));
    }
    onContentChanged: Qt.callLater(refresh)
    onMarkdownChanged: Qt.callLater(refresh)
    onCompletedChanged: if (completed) {
        // A renderer that was unavailable during streaming gets one more chance.
        renderHashes = {};
        Qt.callLater(refresh);
    }
    Component.onCompleted: Qt.callLater(refresh)
    Connections {
        target: LatexRenderer
        function onRenderFinished(hash, path) {
            const expression = LatexRenderer.processedExpressions[hash];
            if (root.renderHashes[expression] === hash) Qt.callLater(root.refresh);
        }
    }
    onLinkActivated: link => { if (StringUtils.parseWebUrl(link)) Qt.openUrlExternally(link); }
    HoverHandler { cursorShape: root.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
}
