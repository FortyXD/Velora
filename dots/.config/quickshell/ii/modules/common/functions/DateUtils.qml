pragma Singleton
import Quickshell

Singleton {
    id: root

    function getFirstDayOfWeek(date, firstDay = 1) {
        const d = new Date(date); // Copy
        const day = d.getDay();   // 0 = Sunday, 1 = Monday, ..., 6 = Saturday

        // Calculate difference to firstDay
        const diff = (day - firstDay + 7) % 7;
        d.setDate(d.getDate() - diff);
        return d;
    }

    function sameDate(d1, d2) {
        return (d1.getFullYear() === d2.getFullYear() && d1.getMonth() === d2.getMonth() && d1.getDate() === d2.getDate());
    }

    // Seconds in a typed duration, or -1: "10" (minutes), "10:30" (minutes and seconds), "1:05:00",
    // "90s", "1h 20m", "1.5h", "25 min", and the Russian "1ч 20м", "30с", "5 мин"
    function parseDuration(text) {
        const input = (text ?? "").trim().toLowerCase().replace(",", ".");
        if (input.length === 0) return -1;
        if (/^\d+(\.\d+)?$/.test(input)) return Math.round(parseFloat(input) * 60);
        if (/^\d+(:\d{1,2}){1,2}$/.test(input)) {
            const parts = input.split(":").map(Number);
            if (parts.slice(1).some(part => part >= 60)) return -1;
            return parts.reduce((total, part) => total * 60 + part, 0);
        }
        const units = [
            { "pattern": "h|hr|hrs|hour|hours|ч|час|часа|часов", "seconds": 3600 },
            { "pattern": "m|min|mins|minute|minutes|м|мин|минута|минуты|минут", "seconds": 60 },
            { "pattern": "s|sec|secs|second|seconds|с|сек|секунда|секунды|секунд", "seconds": 1 },
        ];
        const tokens = input.match(/\d+(\.\d+)?\s*[a-zа-яё]+/g);
        if (!tokens || tokens.join("").replace(/\s/g, "") !== input.replace(/\s/g, "")) return -1;
        let total = 0;
        for (const token of tokens) {
            const [, number, , unit] = token.match(/^(\d+(\.\d+)?)\s*([a-zа-яё]+)$/);
            const match = units.find(u => new RegExp(`^(${u.pattern})$`).test(unit));
            if (!match) return -1;
            total += parseFloat(number) * match.seconds;
        }
        return Math.round(total);
    }

    // 75 → "01:15", 3725 → "1:02:05"
    function formatDuration(totalSeconds) {
        const seconds = Math.max(0, Math.floor(totalSeconds));
        const h = Math.floor(seconds / 3600);
        const m = Math.floor(seconds / 60) % 60;
        const s = seconds % 60;
        const pad = n => n.toString().padStart(2, "0");
        return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
    }

    function getIthDayDateOfSameWeek(date, i, firstDay = 1) {
        const firstDayDate = root.getFirstDayOfWeek(date, firstDay);
        const targetDate = new Date(firstDayDate);
        targetDate.setDate(firstDayDate.getDate() + i);
        return targetDate;
    }
}
