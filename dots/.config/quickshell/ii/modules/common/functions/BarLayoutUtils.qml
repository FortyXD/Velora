pragma Singleton
import Quickshell

/**
 * Pure helpers for bar layout objects (see BarLayoutDefaults for the format).
 */
Singleton {
    id: root

    // Splits a zone into runs: consecutive `pill` items share one pill until an item has `pillBreak`;
    // every other item stands alone. With `islands`, every run of widgets becomes one card, split
    // only by flexible spaces and `pillBreak`.
    function segments(items, islands = false) {
        let result = [];
        let current = null;
        for (const item of (items ?? [])) {
            if (islands && item.type !== "spacer") {
                if (current && !item.pillBreak) {
                    current.items.push(item);
                } else {
                    current = { "pill": true, "items": [item] };
                    result.push(current);
                }
            } else if (item.pill && !islands) {
                if (current && !item.pillBreak) {
                    current.items.push(item);
                } else {
                    current = { "pill": true, "items": [item] };
                    result.push(current);
                }
            } else {
                current = null;
                result.push({ "pill": false, "items": [item] });
            }
        }
        return result;
    }
}
