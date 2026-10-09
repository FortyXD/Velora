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

    readonly property date now: DateTime.clock.date

    // Native names, so a language can be found without knowing its code
    readonly property var languageNames: ({
        "de_DE": "Deutsch", "en_US": "English (US)", "es_MX": "Español (México)", "fr_FR": "Français",
        "he_HE": "עברית", "id_ID": "Bahasa Indonesia", "it_IT": "Italiano", "ja_JP": "日本語",
        "pt_BR": "Português (Brasil)", "ru_RU": "Русский", "tr_TR": "Türkçe", "uk_UA": "Українська",
        "vi_VN": "Tiếng Việt", "zh_CN": "简体中文"
    })
    function languageName(code) {
        return root.languageNames[code] ? `${root.languageNames[code]} · ${code}` : code;
    }

    // Each style sets the three date formats used around the shell together
    readonly property var dateStyles: [
        { long: "ddd, dd/MM", short: "dd/MM", withYear: "dd/MM/yyyy" },
        { long: "ddd, dd.MM", short: "dd.MM", withYear: "dd.MM.yyyy" },
        { long: "ddd, MM/dd", short: "MM/dd", withYear: "MM/dd/yyyy" },
        { long: "ddd, d MMM", short: "d MMM", withYear: "d MMM yyyy" }
    ]

    component AppCommandRow: ConfigTextRow {
        required property string appKey
        inline: true
        inlineFieldWidth: 300
        monospace: true
        wrapMode: TextEdit.NoWrap
        value: Config.options.apps[appKey]
        onEditingFinished: {
            if (value.trim().length > 0 && value.trim() !== Config.options.apps[appKey]) Config.options.apps[appKey] = value.trim();
        }
    }

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

        RowLayout {
            readonly property bool settingsSearchable: true
            property string searchText: Translation.tr("Interface Language")
            property string text: Translation.tr("Interface Language")
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 6
            Layout.bottomMargin: 6
            spacing: 12

            ConfigIconTile {
                icon: "translate"
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Interface Language")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            StyledComboBox {
                id: languageSelector
                Layout.preferredWidth: 280
                buttonIcon: "language"
                textRole: "displayName"

                model: [
                    {
                        displayName: Translation.tr("Auto (System)") + ` · ${root.languageName(Qt.locale().name)}`,
                        value: "auto"
                    },
                    ...Translation.allAvailableLanguages.map(lang => {
                        return {
                            displayName: root.languageName(lang),
                            value: lang
                        };
                    })]

                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.language.ui);
                    return index !== -1 ? index : 0;
                }

                onActivated: index => {
                    Config.options.language.ui = model[index].value;
                }
            }
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
        title: Translation.tr("Default apps")
        description: Translation.tr("Commands the shell runs from its buttons, like the volume mixer link or the network settings. Press Enter to save.")

        AppCommandRow {
            appKey: "terminal"
            icon: "terminal"
            label: Translation.tr("Terminal")
        }
        AppCommandRow {
            appKey: "taskManager"
            icon: "monitor_heart"
            label: Translation.tr("Task manager")
        }
        AppCommandRow {
            appKey: "volumeMixer"
            icon: "tune"
            label: Translation.tr("Volume mixer")
        }
        AppCommandRow {
            appKey: "network"
            icon: "wifi"
            label: Translation.tr("Network settings")
        }
        AppCommandRow {
            appKey: "bluetooth"
            icon: "bluetooth"
            label: Translation.tr("Bluetooth settings")
        }
        AppCommandRow {
            appKey: "update"
            icon: "system_update_alt"
            label: Translation.tr("System update")
        }
    }
}
