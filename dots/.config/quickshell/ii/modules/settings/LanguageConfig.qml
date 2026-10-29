import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Language & Region, opened from General: the language of the shell, and the regional ways of
 * writing things it uses.
 */
ContentPage {
    id: root

    // Locales for the names of days and months: the usual English ones, then the shell's languages
    readonly property var calendarLocales: [...new Set(["en-GB", "en-US", Config.options.calendar.locale,
        ...Translation.allAvailableLanguages.map(lang => lang.replace("_", "-"))])]

    ContentSection {
        icon: "translate"
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
        icon: "public"
        title: Translation.tr("Region")

        ConfigComboRow {
            icon: "calendar_month"
            text: Translation.tr("Days and months")
            description: Translation.tr("The language of their names in the calendar")
            maximumWidth: 300
            currentValue: Config.options.calendar.locale
            onSelected: value => Config.options.calendar.locale = value
            options: root.calendarLocales.map(code => {
                const locale = Qt.locale(code);
                return { displayName: `${locale.nativeLanguageName} (${locale.nativeTerritoryName})`, value: code };
            })
        }

        ContentSubsection {
            title: Translation.tr("Units")
            ConfigSelectionArray {
                currentValue: Config.options.bar.weather.useUSCS
                onSelected: newValue => Config.options.bar.weather.useUSCS = newValue
                options: [
                    { displayName: Translation.tr("Celsius, km/h"), icon: "thermometer", value: false },
                    { displayName: Translation.tr("Fahrenheit, mph"), icon: "thermometer", value: true }
                ]
            }
        }
    }
}
