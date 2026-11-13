pragma Singleton
import Quickshell

/**
 * The open/close decision of a bar popup, as pure state transitions.
 *
 * Kept out of StyledPopup so the rules can be tested without a compositor: the
 * popup only runs what this returns. `pointerInside` covers both the bar target
 * and the popup itself, which is why a flick that lands *inside* the popup needs
 * the latch — otherwise the popup would simply reopen under the cursor.
 */
Singleton {
    id: root

    /**
     * wanted/dismissed: current state. pointerInside: pointer over the target or the popup.
     * hideInstantly: the owner measured a flick and wants no grace time. interactive: the
     * popup can be entered and used. useOpenDelay: the owner asked for a hover delay.
     * enabled: master hover switch. keepOpen: another region may retain an already open popup.
     */
    function next(wanted, dismissed, pointerInside, hideInstantly, interactive, useOpenDelay,
                  enabled = true, keepOpen = false) {
        const result = { wanted: wanted, dismissed: dismissed, stopOpen: false, stopClose: false,
            startOpen: false, startClose: false };
        if (!enabled) {
            result.wanted = false;
            result.dismissed = false;
            result.stopOpen = true;
            result.stopClose = true;
            return result;
        }
        // The rest of the panel can retain an ALREADY open preview, never open one
        // itself or finish a hover delay after the pointer has left the workspace button.
        if (pointerInside || (keepOpen && wanted && !dismissed)) {
            result.stopClose = true;
            if (dismissed) return result; // latched by a flick: stay closed, do not even start the open timer
            if (wanted) return result;
            result.dismissed = false;
            if (useOpenDelay) result.startOpen = true;
            else result.wanted = true;
            return result;
        }
        result.stopOpen = true;
        if (!wanted) {
            result.dismissed = false;
            return result;
        }
        if (hideInstantly) { // A flick: close now and keep it closed while the pointer stays inside
            result.wanted = false;
            result.dismissed = true;
            return result;
        }
        result.dismissed = false;
        if (interactive) result.startClose = true; // Time to cross the gap between the bar and the popup
        else result.wanted = false;
        return result;
    }

    /** When the timer fires, the pointer may have moved on, and a latch still holds. */
    function timerWanted(pointerInside, dismissed) {
        return pointerInside && !dismissed;
    }
}
