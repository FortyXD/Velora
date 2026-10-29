import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Date & Time, opened from General: the system clock (time zone, set automatically) and how the
 * shell shows the time and date.
 */
ContentPage {
    id: root

    // Previews only need to change once a minute; the options list is rebuilt whenever this does
    readonly property date now: {
        const date = DateTime.clock.date;
        return new Date(date.getFullYear(), date.getMonth(), date.getDate(), date.getHours(), date.getMinutes());
    }

    // Each style sets the three date formats used around the shell together
    readonly property var dateStyles: [
        { long: "ddd, dd/MM", short: "dd/MM", withYear: "dd/MM/yyyy" },
        { long: "ddd, dd.MM", short: "dd.MM", withYear: "dd.MM.yyyy" },
        { long: "ddd, MM/dd", short: "MM/dd", withYear: "MM/dd/yyyy" },
        { long: "ddd, d MMM", short: "d MMM", withYear: "d MMM yyyy" }
    ]

    // The system clock, from systemd: Timezone, NTP, CanNTP, NTPSynchronized
    property var clockInfo: ({})
    property var timeZones: []

    function setClock(args) {
        setClockProcess.command = ["timedatectl", ...args];
        setClockProcess.running = true;
    }

    Process {
        id: readClockInfo
        running: true
        command: ["timedatectl", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const info = {};
                for (const line of text.split("\n")) {
                    const separator = line.indexOf("=");
                    if (separator > 0) info[line.slice(0, separator)] = line.slice(separator + 1);
                }
                root.clockInfo = info;
            }
        }
    }

    Process {
        running: true
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector {
            onStreamFinished: root.timeZones = text.trim().split("\n").filter(zone => zone.length > 0)
        }
    }

    // Asks for the password through the shell's polkit agent
    Process {
        id: setClockProcess
        onExited: (exitCode, exitStatus) => readClockInfo.running = true
    }

    ContentSection {
        icon: "schedule"
        title: Translation.tr("Clock")

        ConfigSwitch {
            buttonIcon: "sync"
            text: Translation.tr("Set time automatically")
            description: root.clockInfo.NTP === "yes" && root.clockInfo.NTPSynchronized !== "yes"
                ? Translation.tr("Waiting for a time server…")
                : Translation.tr("Keeps the clock right with time servers on the internet")
            checked: root.clockInfo.NTP === "yes"
            autoToggle: false
            enabled: root.clockInfo.CanNTP === "yes" && !setClockProcess.running
            onClicked: root.setClock(["set-ntp", checked ? "false" : "true"])
        }

        ConfigComboRow {
            icon: "public"
            text: Translation.tr("Time zone")
            maximumWidth: 300
            enabled: root.timeZones.length > 0 && !setClockProcess.running
            currentValue: root.clockInfo.Timezone ?? ""
            onSelected: value => {
                if (value !== root.clockInfo.Timezone) root.setClock(["set-timezone", value]);
            }
            options: root.timeZones.map(zone => ({ displayName: zone.replace(/_/g, " "), value: zone }))
        }
    }

    ContentSection {
        icon: "calendar_month"
        title: Translation.tr("Date & time")
        description: Translation.tr("How the clock and dates look in the bar, sidebars and on the lock screen")

        ContentSubsection {
            title: Translation.tr("Time format")
            ConfigSelectionArray {
                currentValue: Config.options.time.format
                onSelected: newValue => {
                    // Hyprlock has its own clock, keep it in line
                    if (newValue === "hh:mm") {
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    } else {
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    }
                    Config.options.time.format = newValue;
                }
                options: ["hh:mm", "h:mm ap", "h:mm AP"].map(format => ({
                    displayName: Qt.locale().toString(root.now, format),
                    value: format
                }))
            }
        }

        ContentSubsection {
            title: Translation.tr("Date format")
            ConfigSelectionArray {
                currentValue: Config.options.time.dateFormat
                onSelected: newValue => {
                    const style = root.dateStyles.find(style => style.long === newValue);
                    Config.options.time.dateFormat = style.long;
                    Config.options.time.shortDateFormat = style.short;
                    Config.options.time.dateWithYearFormat = style.withYear;
                }
                options: root.dateStyles.map(style => ({
                    displayName: Qt.locale().toString(root.now, style.long),
                    value: style.long
                }))
            }
        }

        ConfigSwitch {
            buttonIcon: "pace"
            text: Translation.tr("Show seconds")
            description: Translation.tr("Clocks update every second instead of every minute")
            checked: Config.options.time.secondPrecision
            onCheckedChanged: {
                Config.options.time.secondPrecision = checked;
            }
        }
    }
}
