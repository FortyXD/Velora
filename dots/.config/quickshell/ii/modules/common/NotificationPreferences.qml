pragma Singleton
import QtQuick
import Quickshell

// Both processes can read this policy. Only the running shell changes the manual state.
Singleton {
    id: root
    readonly property var schedule: Config.options.notifications.quietHours
    readonly property var state: Persistent.states.notifications
    readonly property SystemClock clock: SystemClock { precision: SystemClock.Minutes }
    readonly property double now: clock.date.getTime()
    readonly property double scheduledEnd: schedule.enabled ? endOfWindow(now, schedule.from, schedule.to) : 0
    readonly property double activeScheduleEnd: scheduledEnd !== state.skippedScheduleEnd ? scheduledEnd : 0
    readonly property double quietEnd: Math.max(state.quietUntil > now ? state.quietUntil : 0, activeScheduleEnd)
    readonly property bool silent: state.silent || quietEnd > 0

    readonly property string corner: {
        const choice = Config.options.notifications.popupPosition;
        return ["topLeft", "topCenter", "topRight", "bottomLeft", "bottomCenter", "bottomRight"].includes(choice)
            ? choice : (Config.options.panelFamily === "waffle" ? "bottomRight" : "topRight");
    }
    readonly property bool top: corner.startsWith("top")
    readonly property bool right: corner.endsWith("Right")
    readonly property bool left: corner.endsWith("Left")
    readonly property bool centered: !left && !right

    function minutesOfDay(text) {
        if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(text)) return -1;
        return Number(text.slice(0, 2)) * 60 + Number(text.slice(3));
    }
    // Returns the end of the current local-time interval, including after midnight.
    function endOfWindow(stamp, from, to) {
        const start = minutesOfDay(from), end = minutesOfDay(to);
        if (start < 0 || end < 0 || start === end) return 0;
        const date = new Date(stamp);
        const minute = date.getHours() * 60 + date.getMinutes();
        const active = start < end ? minute >= start && minute < end : minute >= start || minute < end;
        if (!active) return 0;
        if (start > end && minute >= start) date.setDate(date.getDate() + 1);
        date.setHours(Math.floor(end / 60), end % 60, 0, 0);
        return date.getTime();
    }
    function setQuiet(on, minutes = 0) {
        const stamp = Date.now();
        state.skippedScheduleEnd = !on && schedule.enabled ? endOfWindow(stamp, schedule.from, schedule.to) : 0;
        state.quietUntil = on && minutes > 0 ? (Math.floor(stamp / 60000) + minutes) * 60000 : 0;
        state.silent = on && minutes === 0;
    }
}
