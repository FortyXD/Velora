pragma Singleton
import Quickshell
import qs.services

Singleton {
    id: root
    /**
     * @param { string } summary 
     * @returns { string }
     */
    function findSuitableMaterialSymbol(summary = "") {
        const defaultType = 'chat';
        if (summary.length === 0) return defaultType;

        const keywordsToTypes = {
            'reboot': 'restart_alt',
            'record': 'screen_record',
            'microphone': 'mic',
            'микрофон': 'mic',
            'battery': 'battery_std',
            'заряд': 'battery_std',
            'power': 'power',
            'screenshot': 'screenshot_monitor',
            'welcome': 'waving_hand',
            'time': 'scheduleb',
            'installed': 'download',
            'configuration reloaded': 'reset_wrench',
            'unable': 'question_mark',
            "couldn't": 'question_mark',
            'config': 'reset_wrench',
            'update': 'update',
            'ai response': 'neurology',
            'control': 'settings',
            'upsca': 'compare',
            'music': 'queue_music',
            'install': 'deployed_code_update',
            'input': 'keyboard_alt',
            'preedit': 'keyboard_alt',
            'startswith:file': 'folder_copy', // Declarative startsWith check
        };

        const lowerSummary = summary.toLowerCase();

        for (const [keyword, type] of Object.entries(keywordsToTypes)) {
            if (keyword.startsWith('startswith:')) {
                const startsWithKeyword = keyword.replace('startswith:', '');
                if (lowerSummary.startsWith(startsWithKeyword)) {
                    return type;
                }
            } else if (lowerSummary.includes(keyword)) {
                return type;
            }
        }

        return defaultType;
    }

    /**
     * @param { number | string | Date } timestamp 
     * @returns { string }
     */
    function getFriendlyNotifTimeString(timestamp, now = new Date()) {
        if (!timestamp) return '';
        const messageTime = new Date(timestamp);
        const diffMs = now.getTime() - messageTime.getTime();

        // Less than 1 minute
        if (diffMs < 60000)
            return Translation.tr("Now");

        // Same day - show relative time
        if (messageTime.toDateString() === now.toDateString()) {
            const diffMinutes = Math.floor(diffMs / 60000);
            const diffHours = Math.floor(diffMs / 3600000);

            if (diffHours > 0) {
                return Translation.tr("%1 h ago").arg(diffHours);
            } else {
                return Translation.tr("%1 min ago").arg(diffMinutes);
            }
        }

        // Yesterday
        if (messageTime.toDateString() === new Date(now.getTime() - 86400000).toDateString())
            return Translation.tr("Yesterday");

        // Older dates
        return Qt.formatDateTime(messageTime, "MMMM dd");
    }

    function decodeEntities(text) {
        const named = {amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: "\u00a0"};
        return text.replace(/&(amp|lt|gt|quot|apos|nbsp|#\d{1,7}|#x[\da-fA-F]{1,6});/g, (entity, name) => {
            if (name[0] !== "#") return named[name];
            const code = name[1] === "x" ? parseInt(name.slice(2), 16) : Number(name.slice(1));
            return code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : "\ufffd";
        });
    }

    function localImage(value) {
        const path = String(value ?? "");
        return /^(?:\/(?!\/)|file:\/\/\/(?!\/)|image:\/\/qsimage\/)/.test(path) ? path : "";
    }

    function appIcon(value) {
        const name = String(value ?? "");
        return /^[^/\\:\x00-\x1f\x7f]+$/.test(name) ? name : localImage(name);
    }

    function processNotificationBody(body, appName) {
        body = String(body ?? "");
        let processedBody = body
        
        // Clean Chromium-based browsers notifications - remove first line
        if (appName) {
            const lowerApp = appName.toLowerCase()
            const chromiumBrowsers = [
                "brave", "chrome", "chromium", "vivaldi", "opera", "microsoft edge"
            ]

            if (chromiumBrowsers.some(name => lowerApp.includes(name))) {
                const lines = body.split('\n\n')

                if (lines.length > 1 && lines[0].startsWith('<a')) {
                    processedBody = lines.slice(1).join('\n\n')
                }
            }
        }

        // Rebuild the small notification markup vocabulary before passing it to Qt's text renderer.
        const tokens = processedBody.match(/<!--[\s\S]*?(?:-->|$)|<\/?[A-Za-z][^<>]*>|[^<]+|</g) ?? [];
        let linkOpen = false;
        const html = tokens.map(token => {
            if (token === "<" || !token.startsWith("<"))
                return StringUtils.escapeHtml(root.decodeEntities(token)).replace(/\r?\n/g, "<br/>");
            if (/^<br\s*\/?\s*>$/i.test(token)) return "<br/>";
            if (/^<\/?(?:b|strong|i|em|u)>$/i.test(token))
                return token.toLowerCase().replace("strong", "b").replace("em", "i");
            if (/^<\/?a[\s>]/i.test(token)) {
                const close = linkOpen ? "</a>" : "";
                const link = /^<a\s+href\s*=\s*(?:"([^"]*)"|'([^']*)')\s*>$/i.exec(token);
                const url = link && StringUtils.parseWebUrl(root.decodeEntities(link[1] ?? link[2]));
                linkOpen = !!url;
                return close + (url ? '<a href="' + StringUtils.escapeHtml(url.href) + '">' : "");
            }
            if (/^<img\s/i.test(token)) {
                const alt = /\salt\s*=\s*(?:"([^"]*)"|'([^']*)')/i.exec(token);
                if (alt) return StringUtils.escapeHtml(root.decodeEntities(alt[1] ?? alt[2]));
            }
            return "";
        }).join("");
        return html + (linkOpen ? "</a>" : "");
    }
}
