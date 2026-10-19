pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Download and upload speed over all interfaces except loopback, from /proc/net/dev.
 * Only polls while some widget uses it (see `users`).
 */
Singleton {
    id: root

    property int users: 0
    property real downloadRate: 0 // Bytes per second
    property real uploadRate: 0
    property var previous: null

    function format(bytesPerSecond) {
        const units = ["B/s", "KB/s", "MB/s", "GB/s"];
        let value = bytesPerSecond;
        let unit = 0;
        while (value >= 1000 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return `${value < 10 && unit > 0 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
    }

    Timer {
        interval: 2000
        running: root.users > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            netDev.reload();
            let received = 0;
            let sent = 0;
            for (const line of netDev.text().split("\n").slice(2)) {
                const match = line.match(/^\s*([^:]+):\s*(\d+)(?:\s+\d+){7}\s+(\d+)/);
                if (!match || match[1] === "lo") continue;
                received += Number(match[2]);
                sent += Number(match[3]);
            }
            const now = Date.now();
            if (root.previous) {
                const seconds = (now - root.previous.time) / 1000;
                if (seconds > 0) {
                    root.downloadRate = Math.max(0, (received - root.previous.received) / seconds);
                    root.uploadRate = Math.max(0, (sent - root.previous.sent) / seconds);
                }
            }
            root.previous = { "received": received, "sent": sent, "time": now };
        }
        onRunningChanged: if (!running) root.previous = null
    }

    FileView {
        id: netDev
        path: "/proc/net/dev"
    }
}
