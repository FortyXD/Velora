pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Pomodoro, stopwatch and a plain countdown timer. States live in Persistent, so they survive restarts.
 */
Singleton {
    id: root

    property int focusTime: Config.options.time.pomodoro.focus
    property int breakTime: Config.options.time.pomodoro.breakTime
    property int longBreakTime: Config.options.time.pomodoro.longBreak
    property int cyclesBeforeLongBreak: Config.options.time.pomodoro.cyclesBeforeLongBreak

    property bool pomodoroRunning: Persistent.states.timer.pomodoro.running
    property bool pomodoroBreak: Persistent.states.timer.pomodoro.isBreak
    property bool pomodoroLongBreak: Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak);
    property int pomodoroLapDuration: pomodoroLongBreak ? longBreakTime : pomodoroBreak ? breakTime : focusTime // This is a binding that's to be kept
    property int pomodoroSecondsLeft: pomodoroLapDuration // Reasonable init value, to be changed
    property int pomodoroCycle: Persistent.states.timer.pomodoro.cycle
    // A lap that hasn't been started yet follows duration changes from the settings
    readonly property bool pomodoroLapFresh: !pomodoroRunning && pomodoroSecondsLeft === lastLapDuration
    property int lastLapDuration: 0
    onPomodoroLapDurationChanged: {
        if (!pomodoroRunning && pomodoroSecondsLeft === lastLapDuration)
            pomodoroSecondsLeft = pomodoroLapDuration;
        lastLapDuration = pomodoroLapDuration;
    }

    property bool stopwatchRunning: Persistent.states.timer.stopwatch.running
    property int stopwatchTime: 0
    property int stopwatchStart: Persistent.states.timer.stopwatch.start
    property var stopwatchLaps: Persistent.states.timer.stopwatch.laps

    readonly property var countdown: Persistent.states.timer.countdown
    readonly property bool countdownRunning: root.countdown.running
    readonly property int countdownDuration: root.countdown.duration
    property int countdownSecondsLeft: root.countdown.left
    // Set but not started, or reset: nothing to show in the bar
    readonly property bool countdownFresh: !root.countdownRunning && root.countdownSecondsLeft === root.countdownDuration
    property bool countdownDone: false // Rang and waits for a reset or a new time

    function load() {} // For starting it with the shell, so the timer IPC is there

    // General
    Component.onCompleted: {
        lastLapDuration = pomodoroLapDuration;
        if (!stopwatchRunning)
            stopwatchReset();
    }

    function getCurrentTimeInSeconds() {  // Pomodoro uses Seconds
        return Math.floor(Date.now() / 1000);
    }

    function getCurrentTimeIn10ms() {  // Stopwatch uses 10ms
        return Math.floor(Date.now() / 10);
    }

    // Pomodoro
    function refreshPomodoro() {
        // Work <-> break ?
        if (getCurrentTimeInSeconds() >= Persistent.states.timer.pomodoro.start + pomodoroLapDuration) {
            // Reset counts
            Persistent.states.timer.pomodoro.isBreak = !Persistent.states.timer.pomodoro.isBreak;
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();

            // Send notification
            let notificationMessage;
            if (Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak)) {
                notificationMessage = Translation.tr(`🌿 Long break: %1 minutes`).arg(Math.floor(longBreakTime / 60));
            } else if (Persistent.states.timer.pomodoro.isBreak) {
                notificationMessage = Translation.tr(`☕ Break: %1 minutes`).arg(Math.floor(breakTime / 60));
            } else {
                notificationMessage = Translation.tr(`🔴 Focus: %1 minutes`).arg(Math.floor(focusTime / 60));
            }

            Quickshell.execDetached(["notify-send", "Pomodoro", notificationMessage, "-a", "Shell"]);
            if (Config.options.sounds.pomodoro) {
                Audio.playSystemSound("alarm-clock-elapsed")
            }

            if (!pomodoroBreak) {
                Persistent.states.timer.pomodoro.cycle = (Persistent.states.timer.pomodoro.cycle + 1) % root.cyclesBeforeLongBreak;
            }
        }

        pomodoroSecondsLeft = pomodoroLapDuration - (getCurrentTimeInSeconds() - Persistent.states.timer.pomodoro.start);
    }

    Timer {
        id: pomodoroTimer
        interval: 200
        running: root.pomodoroRunning
        repeat: true
        onTriggered: refreshPomodoro()
    }

    function togglePomodoro() {
        Persistent.states.timer.pomodoro.running = !pomodoroRunning;
        if (Persistent.states.timer.pomodoro.running) {
            // Start/Resume
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds() + pomodoroSecondsLeft - pomodoroLapDuration;
        }
    }

    // A typed time for the current period. While it runs, only this period changes; otherwise the period's
    // length in the settings does, so the next focus or break is that long too.
    function setPomodoroTime(seconds) {
        if (seconds <= 0) return;
        if (root.pomodoroRunning) {
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds() - (pomodoroLapDuration - seconds);
            refreshPomodoro();
            return;
        }
        const options = Config.options.time.pomodoro;
        if (root.pomodoroLongBreak) options.longBreak = seconds;
        else if (root.pomodoroBreak) options.breakTime = seconds;
        else options.focus = seconds;
        pomodoroSecondsLeft = seconds;
    }

    // Ends the current focus or break period right away and moves to the next one
    function skipPomodoro() {
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds() - pomodoroLapDuration;
        refreshPomodoro();
    }

    function resetPomodoro() {
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.isBreak = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        Persistent.states.timer.pomodoro.cycle = 0;
        refreshPomodoro();
    }

    // Countdown
    function refreshCountdown() {
        if (!root.countdownRunning) {
            root.countdownSecondsLeft = root.countdown.left;
            return;
        }
        root.countdownSecondsLeft = Math.max(0, root.countdown.end - getCurrentTimeInSeconds());
        if (root.countdownSecondsLeft > 0) return;
        Persistent.states.timer.countdown.running = false;
        Persistent.states.timer.countdown.left = 0;
        root.countdownDone = true;
        Quickshell.execDetached(["notify-send", "-a", "Shell", "-u", "critical", "-i", "alarm-symbolic",
            Translation.tr("Time's up"), Translation.tr("The %1 timer has finished").arg(DateUtils.formatDuration(root.countdownDuration))]);
        if (Config.options.sounds.pomodoro) Audio.playSystemSound("alarm-clock-elapsed");
    }

    Timer {
        interval: 200
        running: root.countdownRunning
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshCountdown()
    }

    function setCountdown(seconds, start = false) {
        if (seconds <= 0) return;
        root.countdownDone = false;
        Persistent.states.timer.countdown.duration = seconds;
        Persistent.states.timer.countdown.left = seconds;
        Persistent.states.timer.countdown.running = false;
        root.countdownSecondsLeft = seconds;
        if (start) root.toggleCountdown();
    }

    function toggleCountdown() {
        if (root.countdownRunning) {
            Persistent.states.timer.countdown.left = Math.max(0, root.countdown.end - getCurrentTimeInSeconds());
            Persistent.states.timer.countdown.running = false;
            root.refreshCountdown();
            return;
        }
        if (root.countdownSecondsLeft <= 0) root.resetCountdown(); // Rang already: start over
        root.countdownDone = false;
        Persistent.states.timer.countdown.end = getCurrentTimeInSeconds() + root.countdownSecondsLeft;
        Persistent.states.timer.countdown.running = true;
    }

    function resetCountdown() {
        root.countdownDone = false;
        Persistent.states.timer.countdown.running = false;
        Persistent.states.timer.countdown.left = root.countdownDuration;
        root.countdownSecondsLeft = root.countdownDuration;
    }

    // qs -c ii ipc call timer start 10m | toggle | reset | left
    IpcHandler {
        target: "timer"
        function start(duration: string): string {
            const seconds = DateUtils.parseDuration(duration);
            if (seconds <= 0) return "Can't read that time";
            root.setCountdown(seconds, true);
            return DateUtils.formatDuration(seconds);
        }
        function toggle(): void { root.toggleCountdown() }
        function reset(): void { root.resetCountdown() }
        function left(): string { return DateUtils.formatDuration(root.countdownSecondsLeft) }
    }

    // Stopwatch
    function refreshStopwatch() {  // Stopwatch stores time in 10ms
        stopwatchTime = getCurrentTimeIn10ms() - stopwatchStart;
    }

    Timer {
        id: stopwatchTimer
        interval: 10
        running: root.stopwatchRunning
        repeat: true
        onTriggered: refreshStopwatch()
    }

    function toggleStopwatch() {
        if (root.stopwatchRunning)
            stopwatchPause();
        else
            stopwatchResume();
    }

    function stopwatchPause() {
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchResume() {
        if (stopwatchTime === 0) Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = true;
        Persistent.states.timer.stopwatch.start = getCurrentTimeIn10ms() - stopwatchTime;
    }

    function stopwatchReset() {
        stopwatchTime = 0;
        Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchRecordLap() {
        Persistent.states.timer.stopwatch.laps.push(stopwatchTime);
    }
}
