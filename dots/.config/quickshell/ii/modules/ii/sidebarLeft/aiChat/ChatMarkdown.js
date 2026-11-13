.pragma library

function textBlocks(text) {
    const lines = text.split("\n");
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
    return text.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, "[$1]($2)")
        .replace(/<\/?(?:img|iframe|object|video|audio)\b[^>]*>/gi, "");
}
