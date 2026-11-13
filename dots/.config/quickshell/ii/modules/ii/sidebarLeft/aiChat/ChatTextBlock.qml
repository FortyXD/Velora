import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "ChatMarkdown.js" as Markdown

StyledTextArea {
    id: root
    objectName: "chatProse"
    property string content: ""
    property bool markdown: true
    property bool completed: true
    property int headingLevel: 0
    property var expressions: ({})
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
        let value = Markdown.safeMarkdown(content);
        for (const expression in expressions) value = value.split(expression).join("![formula](" + expressions[expression] + ")");
        rendered = value;
    }
    function renderMath() {
        if (!markdown || !completed) return;
        const regex = /\$\$[\s\S]+?\$\$|\\\[[\s\S]+?\\\]|\\\([\s\S]+?\\\)|\$(?!\s|\d+[.,]?\d*\b)[^$\n]+?\$/g;
        let match;
        while ((match = regex.exec(content)) !== null) LatexRenderer.requestRender(match[0]);
    }
    onContentChanged: { refresh(); if (completed) mathDelay.restart(); }
    onCompletedChanged: if (completed) mathDelay.restart()
    onMarkdownChanged: { refresh(); if (markdown) mathDelay.restart(); }
    Component.onCompleted: { refresh(); if (completed) mathDelay.restart(); }
    Timer { id: mathDelay; interval: 300; onTriggered: root.renderMath() }
    Connections {
        target: LatexRenderer
        function onRenderFinished(hash, path) {
            const expression = LatexRenderer.processedExpressions[hash];
            if (expression && root.content.includes(expression)) {
                root.expressions[expression] = path;
                root.refresh();
            }
        }
    }
    onLinkActivated: link => { if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link); }
    HoverHandler { cursorShape: root.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
}
