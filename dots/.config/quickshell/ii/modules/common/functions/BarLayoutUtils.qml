pragma Singleton
import Quickshell

/**
 * Pure helpers for bar layout objects (see BarLayoutDefaults for the format).
 */
Singleton {
    id: root

    // Splits a zone into runs: consecutive `pill` items share one pill until an item has `pillBreak`;
    // every other item stands alone.
    function segments(items) {
        let result = [];
        let current = null;
        for (const item of (items ?? [])) {
            if (item.pill) {
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
