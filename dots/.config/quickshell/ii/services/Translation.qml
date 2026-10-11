pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property var translations: ({})
    property var generatedTranslations: ({})
    property var availableLanguages: ["en_US"]
    property var availableGeneratedLanguages: []
    property var allAvailableLanguages: {
        const combined = new Set([...root.availableLanguages, ...root.availableGeneratedLanguages]);
        return Array.from(combined).sort();
    }
    // Native names, so a language can be found without knowing its code
    readonly property var languageNames: ({
        "ar_SA": "العربية", "az_AZ": "Azərbaycan", "be_BY": "Беларуская", "bg_BG": "Български",
        "cs_CZ": "Čeština", "da_DK": "Dansk", "de_DE": "Deutsch", "el_GR": "Ελληνικά",
        "en_GB": "English (UK)", "en_US": "English (US)", "es_ES": "Español (España)", "es_MX": "Español (México)",
        "et_EE": "Eesti", "fa_IR": "فارسی", "fi_FI": "Suomi", "fr_FR": "Français", "he_HE": "עברית",
        "hi_IN": "हिन्दी", "hr_HR": "Hrvatski", "hu_HU": "Magyar", "hy_AM": "Հայերեն", "id_ID": "Bahasa Indonesia",
        "it_IT": "Italiano", "ja_JP": "日本語", "ka_GE": "ქართული", "kk_KZ": "Қазақ", "ko_KR": "한국어",
        "lt_LT": "Lietuvių", "lv_LV": "Latviešu", "nb_NO": "Norsk bokmål", "nl_NL": "Nederlands",
        "pl_PL": "Polski", "pt_BR": "Português (Brasil)", "pt_PT": "Português (Portugal)", "ro_RO": "Română",
        "ru_RU": "Русский", "sk_SK": "Slovenčina", "sl_SI": "Slovenščina", "sr_RS": "Српски", "sv_SE": "Svenska",
        "th_TH": "ไทย", "tr_TR": "Türkçe", "uk_UA": "Українська", "uz_UZ": "Oʻzbek", "vi_VN": "Tiếng Việt",
        "zh_CN": "简体中文", "zh_TW": "繁體中文"
    })
    function languageName(code) {
        return root.languageNames[code] ? `${root.languageNames[code]} · ${code}` : code;
    }

    property bool isScanning: scanLanguagesProcess.running
    property bool isLoading: false
    property string translationKeepSuffix: "/*keep*/"
    property string translationsDir: Quickshell.shellPath("translations")
    property string generatedTranslationsDir: Directories.shellConfig + "/translations"

    property string languageCode: {
        var configLang = Config?.options.language.ui ?? "auto";

        if (configLang !== "auto")
            return configLang;

        return Qt.locale().name;
    }

    TranslationScanner {
        id: scanLanguagesProcess
        translationsDir: root.translationsDir
        onLanguagesScanned: (languages) => {
            root.availableLanguages = [...languages];
        }
    }

    TranslationScanner {
        id: scanGeneratedLanguagesProcess
        translationsDir: root.generatedTranslationsDir
        onLanguagesScanned: (languages) => {
            root.availableGeneratedLanguages = [...languages];
        }
    }

    onLanguageCodeChanged: {
        print("[Translation] Language changed to", root.languageCode);
        translationFileView.languageCode = root.languageCode;
        generatedTranslationFileView.languageCode = root.languageCode;
        translationFileView.reread();
        generatedTranslationFileView.reread();
    }

    TranslationReader {
        id: translationFileView
        translationsDir: root.translationsDir
        languageCode: root.languageCode
        onContentLoaded: (data) => {
            root.translations = data;
            root.isLoading = false;
        }
    }

    TranslationReader {
        id: generatedTranslationFileView
        translationsDir: root.generatedTranslationsDir
        languageCode: root.languageCode
        onContentLoaded: (data) => {
            root.generatedTranslations = data;
            root.isLoading = false;
        }
    }

    function tr(text) {
        // Special cases
        if (!text) return "";
        var key = text.toString();
        if (root.isLoading || (!root?.translations?.hasOwnProperty(key) && !root?.generatedTranslations?.hasOwnProperty(key)))
            return key;
        
        // Normal cases
        var translation = root.translations[key] || root.generatedTranslations[key] || key;
        // print(key, "-> [", root.translations[key], root.generatedTranslations[key], key, "] ->", translation);
        if (translation.endsWith(root.translationKeepSuffix)) {
            translation = translation.substring(0, translation.length - root.translationKeepSuffix.length).trim();
        }
        return translation;
    }

    component TranslationScanner: Process {
        id: translationScanner
        required property string translationsDir
        signal languagesScanned(var languages)

        command: ["find", translationScanner.translationsDir, "-name", "*.json", "-exec", "basename", "{}", ".json", ";"]
        running: true

        stdout: StdioCollector {
            id: languagesCollector
            onStreamFinished: {
                const output = languagesCollector.text;
                const files = output.trim().split('\n').map(f => f.trim());
                translationScanner.languagesScanned(files);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                translationScanner.languagesScanned(["en_US"]);
            }
        }
    }

    component TranslationReader: FileView {
        id: translationReader
        required property string translationsDir
        property string languageCode: root.languageCode
        signal contentLoaded(var data)

        function reread() { // Proper reload in case the file was incorrect before
            translationReader.path = "";
            translationReader.path = `${translationReader.translationsDir}/${translationReader.languageCode}.json`;
            translationReader.reload();
        }
        path: ""

        onLoaded: {
            var textContent = "";
            try {
                textContent = text();
                var jsonData = JSON.parse(textContent);
                translationReader.contentLoaded(jsonData);
            } catch (e) {
                console.log("[Translation] Failed to load translations:", e);
                translationReader.contentLoaded({});
            }
        }
        onLoadFailed: error => {
            translationReader.contentLoaded({});
        }
    }
}
