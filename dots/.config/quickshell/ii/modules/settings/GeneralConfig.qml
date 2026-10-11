import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

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

    ContentSection {
        title: ""

        ConfigNavRow {
            buttonIcon: "info"
            title: Translation.tr("About")
            valueText: `${SystemInfo.distroName} · Folis`
            onClicked: ApplicationWindow.window?.openPage("about")
        }
    }

    ContentSection {
        title: Translation.tr("Language")
        description: Translation.tr("Applies to the bar, sidebars, settings and other parts of the shell")

        ConfigComboRow {
            icon: "translate"
            text: Translation.tr("Interface Language")
            maximumWidth: 300
            currentValue: Config.options.language.ui
            onSelected: value => Config.options.language.ui = value
            options: [
                { displayName: Translation.tr("Auto (System)") + ` · ${Translation.languageName(Qt.locale().name)}`, value: "auto", icon: "language" },
                ...Translation.allAvailableLanguages.map(lang => ({ displayName: Translation.languageName(lang), value: lang }))
            ]
        }
    }

    ContentSection {
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

    ContentSection {
        title: Translation.tr("Apps")

        ConfigNavRow {
            buttonIcon: "apps"
            title: Translation.tr("Default Apps")
            description: Translation.tr("Browser, terminal, file manager and the apps that open your files")
            onClicked: ApplicationWindow.window?.openPage("apps")
        }
    }
}
