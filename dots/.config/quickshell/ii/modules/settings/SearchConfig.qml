import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    component PrefixRow: ConfigTextRow {
        required property string prefixKey
        inline: true
        inlineFieldWidth: 120
        monospace: true
        wrapMode: TextEdit.NoWrap
        value: Config.options.search.prefix[prefixKey]
        onValueChanged: Config.options.search.prefix[prefixKey] = value
    }

    ContentSection {
        icon: "search"
        title: Translation.tr("Search")
        description: Translation.tr("The launcher in the overview")

        ConfigSwitch {
            buttonIcon: "spellcheck"
            text: Translation.tr("Use Levenshtein distance-based algorithm instead of fuzzy")
            description: Translation.tr("Could be better if you make a ton of typos, but results can be weird and might not work with acronyms (e.g. \"GIMP\" might not give you the paint program)")
            checked: Config.options.search.sloppy
            onCheckedChanged: {
                Config.options.search.sloppy = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Prefixes")
            description: Translation.tr("Type one of these first to switch the search mode")
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 560 ? 2 : 1
                columnSpacing: 0
                rowSpacing: 0
                uniformCellWidths: true
                PrefixRow { prefixKey: "action"; icon: "bolt"; label: Translation.tr("Action") }
                PrefixRow { prefixKey: "clipboard"; icon: "content_paste"; label: Translation.tr("Clipboard") }
                PrefixRow { prefixKey: "emojis"; icon: "mood"; label: Translation.tr("Emojis") }
                PrefixRow { prefixKey: "math"; icon: "calculate"; label: Translation.tr("Math") }
                PrefixRow { prefixKey: "shellCommand"; icon: "terminal"; label: Translation.tr("Shell command") }
                PrefixRow { prefixKey: "webSearch"; icon: "travel_explore"; label: Translation.tr("Web search") }
            }
        }

        ConfigTextRow {
            icon: "public"
            label: Translation.tr("Web search")
            description: Translation.tr("Base URL, the query is added to the end")
            wrapMode: TextEdit.NoWrap
            placeholderText: Translation.tr("Base URL")
            value: Config.options.search.engineBaseUrl
            onValueChanged: {
                Config.options.search.engineBaseUrl = value;
            }
        }
    }

    ContentSection {
        icon: "neurology"
        title: Translation.tr("Assistant")
        description: Translation.tr("The AI chat in the left sidebar")

        ContentSubsection {
            title: Translation.tr("AI features")
            description: Translation.tr("Off hides the AI chat in the left sidebar. Local only allows just the models running on this computer (Ollama), so nothing is sent online.")
            ConfigSelectionArray {
                currentValue: Config.options.policies.ai
                onSelected: newValue => {
                    Config.options.policies.ai = newValue;
                }
                options: [
                    { displayName: Translation.tr("Off"), icon: "block", value: 0 },
                    { displayName: Translation.tr("On"), icon: "check", value: 1 },
                    { displayName: Translation.tr("Local only"), icon: "computer", value: 2 }
                ]
            }
        }
        ConfigTextRow {
            enabled: Config.options.policies.ai !== 0
            icon: "edit_note"
            label: Translation.tr("System prompt")
            description: Translation.tr("Instructions the assistant gets before every chat")
            placeholderText: Translation.tr("System prompt")
            value: Config.options.ai.systemPrompt
            fieldMinimumHeight: 96
            onValueChanged: {
                const text = value;
                Qt.callLater(() => {
                    Config.options.ai.systemPrompt = text;
                });
            }
        }
    }

    ContentSection {
        icon: "music_cast"
        title: Translation.tr("Music recognition")
        description: Translation.tr("Identifies the song that is playing, from the right sidebar")

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "timer_off"
                text: Translation.tr("Total duration timeout (s)")
                value: Config.options.musicRecognition.timeout
                from: 10
                to: 100
                stepSize: 2
                onValueChanged: {
                    Config.options.musicRecognition.timeout = value;
                }
            }
            ConfigSpinBox {
                icon: "av_timer"
                text: Translation.tr("Polling interval (s)")
                value: Config.options.musicRecognition.interval
                from: 2
                to: 10
                stepSize: 1
                onValueChanged: {
                    Config.options.musicRecognition.interval = value;
                }
            }
        }
    }
}
