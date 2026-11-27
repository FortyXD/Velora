import QtQuick
import QtTest
import "ChatMarkdown.js" as Markdown

TestCase {
    id: suite
    name: "ChatMarkdown"
    Component { id: prose; ChatTextBlock { completed: false } }

    function test_formula_appears_before_the_answer_finishes() {
        const item = createTemporaryObject(prose, suite, {content:"First $$x$"});
        wait(0);
        compare(LatexRenderer.requests.length, 0);
        item.content += "$";
        tryCompare(LatexRenderer, "requests", ["$$x$$"]);
        item.content += " and `$$x$$`";
        LatexRenderer.finish("$$x$$");
        tryVerify(() => item.rendered.includes("![formula]"));
        item.content += " and $$x$$ again";
        tryVerify(() => item.rendered.endsWith(" again"));
        compare(item.rendered.split("![formula]").length - 1, 2);
        verify(item.rendered.includes("`$$x$$`"));
        compare(LatexRenderer.requests.length, 1);
        verify(!item.completed);
        item.markdown = false;
        tryCompare(item, "text", item.content);
    }

    function test_math_delimiters_in_streaming_text() {
        const text = "Pay $5 or $10. `$code$` Then $2+2$ and \\(x\\), \\[a\nb\\], \\$5 and $$x < y$$";
        compare(Markdown.mathSpans(text).map(span => span.expression), ["$2+2$", "\\(x\\)", "\\[a\nb\\]", "$$x < y$$"]);
        compare(Markdown.mathSpans("Start $$x$").length, 0);
        compare(Markdown.mathSpans("$$$$ and \\(\\) and $$ \n $$").length, 0);
        compare(Markdown.mathSpans("Start \\(x\\").length, 0);
        const display = "$$\na + b\n\n= c\n$$";
        const blocks = Markdown.parse("Before\n\n" + display + "\n\nAfter");
        compare(blocks.map(block => block.body), ["Before", display, "After"]);
    }
    function test_partial_fences_keep_code_and_language() {
        const message = "A paragraph\n\n```c++\nint main() { return 0; }\n```\n\nAfter";
        for (let end = 23; end <= message.length; end++) {
            const blocks = Markdown.parse(message.slice(0, end));
            const code = blocks.find(b => b.kind === "code");
            verify(!!code); compare(code.language, "c++");
            verify(!code.body.includes("After"));
        }
        compare(Markdown.parse(message).map(b => b.kind).join(","), "text,code,text");
    }
    function test_thoughts_and_code_are_separate() {
        let blocks = Markdown.parse("<think>Reasoning is arriving");
        compare(blocks[0].kind, "think"); verify(!blocks[0].complete);
        blocks = Markdown.parse("<think>Ready</think>\n\nFinal **answer**");
        compare(blocks.length, 2); verify(blocks[0].complete);compare(blocks[1].kind,"text");
        blocks = Markdown.parse("````text\n<think>literal</think>\n```\n````");
        compare(blocks.length, 1);compare(blocks[0].kind,"code");verify(blocks[0].body.includes("<think>"));
    }
    function test_table_and_nested_lists_preserve_structure() {
        const blocks = Markdown.parse("- First\n  - Nested\n\n| A | B |\n| --- | :---: |\n| one | two |\n\n> Quote\n\n$\\alpha$");
        compare(blocks.map(b => b.kind).join(","),"text,table,quote,text");
        verify(blocks[0].body.includes("  - Nested"));verify(blocks[3].body.includes("$\\alpha$"));
    }
    function test_images_are_links_not_automatic_requests() {
        compare(Markdown.safeMarkdown("![preview](https://example.com/image.png)"),"[preview](https://example.com/image.png)");
        compare(Markdown.safeMarkdown("![cover][album] and <b>artist</b>"), "[cover][album] and <b>artist</b>");
        compare(Markdown.safeMarkdown("<https://example.org/album>"), "<https://example.org/album>");
        verify(!Markdown.safeMarkdown('<img src="file:///private">').includes("<img"));
    }
    function test_headings_keep_inline_formatting_and_code_literals() {
        const blocks=Markdown.parse("## A **clear** title\n\nParagraph\n\n```md\n## Literal\n```\n\n### Next ###");
        compare(blocks.map(b=>b.kind).join(","),"heading,text,code,heading");
        compare(blocks[0].body,"A **clear** title");compare(blocks[0].language,"2");
        compare(blocks[2].body,"## Literal");compare(blocks[3].body,"Next");
        compare(Markdown.parse("### C#")[0].body,"C#");
    }
}
