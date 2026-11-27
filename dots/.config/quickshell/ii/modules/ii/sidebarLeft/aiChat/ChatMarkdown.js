.pragma library

function proseLines(text) {
    if (!text.includes("\n")) return [text];
    const spans = mathSpans(text);
    if (!spans.length) return text.split("\n");
    const lines = [];
    let start = 0, span = 0;
    for (let newline = text.indexOf("\n"); newline !== -1; newline = text.indexOf("\n", newline + 1)) {
        while (span < spans.length && spans[span].end <= newline) span++;
        if (span < spans.length && spans[span].start < newline) continue;
        lines.push(text.slice(start, newline));
        start = newline + 1;
    }
    lines.push(text.slice(start));
    return lines;
}

function textBlocks(text) {
    const lines = proseLines(text);
    const blocks = [];
    let prose = [];
    function flush() {
        const body = prose.join("\n").trim();
        const quote = body && prose.every(line => !line.trim() || /^>\s?/.test(line));
        if (body) blocks.push({kind:quote ? "quote" : "text", body:quote ? body.replace(/^>\s?/gm, "") : body, language:"", complete:true});
        prose = [];
    }
    for (let i = 0; i < lines.length; i++) {
        const heading = /^(#{1,6})[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$/.exec(lines[i]);
        if (heading) {
            flush();
            blocks.push({kind:"heading", body:heading[2], language:String(heading[1].length), complete:true});
        } else if (lines[i].includes("|") && i + 1 < lines.length && /^\s*\|?\s*:?-{3,}:?\s*\|[\s|:\-]*$/.test(lines[i + 1])) {
            flush();
            const table = [lines[i], lines[++i]];
            while (i + 1 < lines.length && lines[i + 1].trim() && lines[i + 1].includes("|")) table.push(lines[++i]);
            blocks.push({kind:"table", body:table.join("\n"), language:"", complete:true});
        } else if (!lines[i].trim() && prose.length) {
            // Keep loose/nested list items in one native Markdown document.
            const next = lines.slice(i + 1).find(line => line.trim()) ?? "";
            const inList = prose.some(line => /^\s*(?:[-+*]|\d+[.)])\s/.test(line));
            if (inList && /^(?:\s+|[-+*]\s|\d+[.)]\s)/.test(next)) prose.push(lines[i]);
            else flush();
        } else prose.push(lines[i]);
    }
    flush();
    return blocks;
}

function parse(value) {
    const text = String(value || "");
    const blocks = [];
    const start = /^[ \t]{0,3}(`{3,}|~{3,})([^\n]*)\n?|<think>/gm;
    let position = 0;
    while (position < text.length) {
        start.lastIndex = position;
        const match = start.exec(text);
        if (!match) { blocks.push(...textBlocks(text.slice(position))); break; }
        blocks.push(...textBlocks(text.slice(position, match.index)));
        const contentStart = start.lastIndex;
        if (match[0] === "<think>") {
            const end = text.indexOf("</think>", contentStart);
            blocks.push({kind:"think", body:text.slice(contentStart, end < 0 ? text.length : end), language:"", complete:end >= 0});
            position = end < 0 ? text.length : end + 8;
        } else {
            const fence = match[1];
            const closing = new RegExp("^[ \\t]{0,3}" + fence[0] + "{" + fence.length + ",}[ \\t]*(?:\\n|$)", "gm");
            closing.lastIndex = contentStart;
            const end = closing.exec(text);
            blocks.push({kind:"code", body:text.slice(contentStart, end ? end.index : text.length).replace(/\n$/, ""), language:match[2].trim().split(/\s/)[0], complete:!!end});
            position = end ? closing.lastIndex : text.length;
        }
    }
    return blocks;
}

function safeMarkdown(text) {
    // Model images are links; only our own math renderer inserts inline images.
    return text.replace(/!+(?=\[)/g, "")
        .replace(/<(?!https?:\/\/|\/?(?:b|strong|i|em|u|s|sub|sup|code|br)\s*\/?>)(?=[a-z/!?])/gi, "&lt;");
}

// Only closed math can be handed to MicroTeX. A stream can split either delimiter.
function mathSpans(text) {
    const spans = [];
    const tokens = /`+|\\[\\`$()[\]]|\$\$?|\n/g;
    let code = "", closing = "", start = 0;
    let match;
    while ((match = tokens.exec(text)) !== null) {
        const token = match[0];
        if (code) {
            if (token === code) code = "";
            continue;
        }
        if (closing) {
            if (closing === "$") {
                if (token[0] === "$" && match.index > start + 1 && !/\s/.test(text[match.index - 1])
                        && !/\d/.test(text.charAt(match.index + 1))) {
                    tokens.lastIndex = match.index + 1;
                } else if (token === "\n" || token[0] === "$" || token[0] === "`" || token === "\\(" || token === "\\[") {
                    closing = "";
                } else continue;
            } else if (token !== closing) continue;
            if (closing) {
                if (text.slice(start + closing.length, match.index).trim())
                    spans.push({start, end:tokens.lastIndex, expression:text.slice(start, tokens.lastIndex)});
                closing = "";
                continue;
            }
        }
        start = match.index;
        if (token[0] === "`") code = token;
        else if (token === "$$" || (token === "$" && /\S/.test(text.charAt(tokens.lastIndex)))) closing = token;
        else if (token === "\\[") closing = "\\]";
        else if (token === "\\(") closing = "\\)";
    }
    return spans;
}
