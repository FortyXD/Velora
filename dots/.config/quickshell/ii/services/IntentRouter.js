.pragma library

// Presentation only. No result from this module grants execution authority.
// Keep classification synchronous, bounded and independent of any model/service.
var imperative = /^(?:открой|откройте|запусти|запустите|создай|создайте|сделай|сделайте|удали|удалите|перемести|переместите|переименуй|переименуйте|скопируй|скопируйте|измени|измените|установи|установите|сохрани|сохраните|закрой|закройте|перейди|переключись|очисти|исправь|упакуй|архивируй|open|launch|run|create|make|delete|remove|move|rename|copy|change|set|install|save|close|switch|clear|fix|archive|zip|execute)(?:\s|$)/i;
var infinitive = /^(?:открыть|запустить|создать|сделать|удалить|переместить|переименовать|скопировать|изменить|установить|сохранить|закрыть|очистить|исправить|упаковать)(?:\s|$)/i;
var question = /^(?:как|почему|зачем|что\s+(?:такое|значит|делает|будет)|объясни|расскажи|посоветуй|помоги\s+(?:понять|разобраться)|how|why|what\s+(?:is|are|does|happens)|explain|tell\s+me|help\s+me\s+understand)(?:\s|[?!.]|$)/i;
var search = /^(?:найди|найти|ищи|поиск|покажи|где|find|search|show|where|look\s+for)(?:\s|$)/i;
var conversational = /^(?:привет|здравствуй(?:те)?|спасибо|добрый\s+(?:день|вечер)|hello|hi|thanks|thank\s+you)(?:\s|[!,.?]|$)/i;

function normalize(text) {
    text = String(text ?? "").slice(0, 4096);
    if (text.normalize) text = text.normalize("NFKC");
    return text.replace(/\s+/g, " ").trim();
}

function unquoted(text) {
    // Quoted commands, filenames and code are data, including an unfinished quote.
    return text.replace(/```[\s\S]*?(?:```|$)|`[^`]*(?:`|$)|"[^"]*(?:"|$)|«[^»]*(?:»|$)|“[^”]*(?:”|$)|(?:^|\s)'[^']*(?:'|$)/g, " ");
}

function result(kind, confidence, reason, hint) {
    return {kind: kind, confidence: confidence, reason: reason, actionHint: hint || ""};
}

function isActionQuery(input, prefix, actions) {
    if (!prefix || !input.startsWith(prefix)) return false;
    return actions.some(name => {
        const command = prefix + name;
        return command.startsWith(input) || input === command || input.startsWith(command + " ");
    });
}

function isMathExpression(text) {
    text = String(text).trim();
    return (/\d/.test(text) && /^[\d\s.,eE()+\-*/^%=<>!]+$/.test(text))
        || /^(?:sqrt|sin|cos|tan|log|ln|abs)\s*\(/i.test(text)
        || /^(?:pi|π)$/i.test(text);
}

function hint(text) {
    if (/\b(?:command|shell|terminal|bash|script)\b|команд|терминал|скрипт/i.test(text)) return "terminal";
    if (/\b(?:workspace|window|app)\b|рабочий стол|окно|приложени/i.test(text)) return "desktop";
    return "files";
}

function classify(input, mode) {
    const original = normalize(input);
    if (!original) return result("search", 1, "empty");
    if (["search", "chat", "action"].indexOf(mode) >= 0)
        return result(mode, 1, "explicit", mode === "action" ? hint(original) : "");
    let text = normalize(unquoted(original)).toLowerCase();
    if (!text) return result("search", 1, "quoted");
    text = text.replace(/^(?:(?:пожалуйста|please)[,\s]+)+/, "");
    if (question.test(text)) return result("chat", .95, "question");
    if (conversational.test(text)) return result("chat", .95, "conversation");
    // Polite requests remain requests; a question mark alone is not an action.
    const polite = /^(?:можешь(?:\s+ли)?(?:\s+ты)?|можете(?:\s+ли)?(?:\s+вы)?|сможешь|can\s+you|could\s+you|would\s+you|please)\s+/i;
    const requested = polite.test(text);
    text = text.replace(polite, "").replace(/^пожалуйста[,\s]+/, "");
    if (question.test(text)) return result("chat", .95, "question");
    if (/^open\s+source(?:\s|$)/.test(text)) return result("search", .95, "description");
    const segments = text.split(/\s*(?:[,;]|\b(?:and\s+then|then|and|but)\b|\s+(?:и\s+затем|затем|и|но)\s+)\s*/);
    let negated = false;
    let uncertain = false;
    for (let segment of segments.slice(0, 32)) {
        segment = segment.trim().replace(/^(?:please|пожалуйста)\s+/, "");
        if (/^(?:не\s+|никогда\s+не\s+|do\s+not\s+|don't\s+|never\s+)/.test(segment)) {
            negated = true;
            continue;
        }
        if (negated && imperative.test(segment) && !/[,;]|\bbut\b|\sно\s/.test(text))
            return result("ambiguous", .5, "needs_choice");
        if (imperative.test(segment) || (requested && infinitive.test(segment)))
            return result("action", .95, "request", hint(text));
        if (infinitive.test(segment)) uncertain = true;
    }
    if (negated) return result("chat", .9, "negation");
    if (search.test(text)) return result("search", .95, "lookup");
    if (uncertain || requested) return result("ambiguous", .5, "needs_choice");
    if (/\?$/.test(original)) return result("chat", .8, "question");
    return result("search", .8, "description");
}
