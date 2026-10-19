pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Sets a new wallpaper once a day from Bing, NASA or Wikimedia (Settings → Wallpaper).
 * Checks shortly after the shell starts, every half hour, and after the computer wakes up.
 * Uses sources that need no key, since the keyring may still be locked.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.ready && Config.options.background.daily.enable
    readonly property string source: Config.options.background.daily.source
    readonly property bool running: dailyProc.running
    property string lastError: ""

    function load() {} // For starting the service (and its IPC) with the shell

    function today() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd");
    }

    function check() {
        if (!root.enabled || dailyProc.running) return;
        const state = Persistent.states.wallpaperOfTheDay;
        if (state.lastDate === root.today() && state.lastSource === root.source) return;
        root.run();
    }

    function run() {
        if (dailyProc.running) return;
        root.lastError = "";
        const nasaKey = KeyringStorage.keyringData?.wallpaperKeys?.nasa ?? "";
        dailyProc.command = ["env", `NASA_KEY=${nasaKey.length > 0 ? nasaKey : "DEMO_KEY"}`,
            Quickshell.shellPath("scripts/colors/random/wallpaper_of_the_day.sh"), root.source, `${Config.options.background.daily.keepDays}`];
        dailyProc.running = true;
    }

    Process {
        id: dailyProc
        stdout: StdioCollector {
            id: dailyOutput
        }
        stderr: StdioCollector {
            id: dailyErrors
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                Persistent.states.wallpaperOfTheDay.lastDate = root.today();
                Persistent.states.wallpaperOfTheDay.lastSource = root.source;
            } else {
                root.lastError = dailyErrors.text.trim().split("\n").pop() ?? "";
                retryTimer.restart();
            }
        }
    }

    Timer { // Network may come up after the shell
        interval: 20000
        running: root.enabled && Persistent.ready
        onTriggered: root.check()
    }

    Timer {
        interval: 30 * 60 * 1000
        running: root.enabled
        repeat: true
        onTriggered: root.check()
    }

    Timer { // Resume shows up as a missed minute
        interval: 60 * 1000
        running: root.enabled
        repeat: true
        property real last: Date.now()
        onTriggered: {
            const now = Date.now();
            if (now - last > 3 * 60 * 1000) wakeTimer.restart();
            last = now;
        }
    }
    Timer {
        id: wakeTimer
        interval: 15000 // Give the network time after waking
        onTriggered: root.check()
    }

    Timer {
        id: retryTimer
        interval: 10 * 60 * 1000
        onTriggered: root.check()
    }

    IpcHandler {
        target: "wallpaperOfTheDay"

        function run(): void {
            root.run();
        }
        function status(): string {
            const state = Persistent.states.wallpaperOfTheDay;
            return `${root.enabled ? "on" : "off"}, ${root.source}, last ${state.lastDate || "never"}${root.lastError ? `, error: ${root.lastError}` : ""}`;
        }
    }
}
