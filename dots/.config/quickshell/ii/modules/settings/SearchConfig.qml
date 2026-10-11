import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    // One or two characters, saved on Enter; an empty prefix would match every search
    component PrefixRow: ConfigTextRow {
        id: prefixRow
        required property string prefixKey
        inline: true
        inlineFieldWidth: 120
        monospace: true
        wrapMode: TextEdit.NoWrap
        value: Config.options.search.prefix[prefixKey]
        onValueChanged: if (value.length > 2) value = value.slice(0, 2)
        onEditingFinished: {
            const prefix = value.trim();
            if (prefix.length > 0) Config.options.search.prefix[prefixKey] = prefix;
            else value = Config.options.search.prefix[prefixKey];
        }
    }

    readonly property var searchEngines: [
        { displayName: "Google", value: "https://www.google.com/search?q=" },
        { displayName: "DuckDuckGo", value: "https://duckduckgo.com/?q=" },
        { displayName: "Brave Search", value: "https://search.brave.com/search?q=" },
        { displayName: "Bing", value: "https://www.bing.com/search?q=" },
        { displayName: "Startpage", value: "https://www.startpage.com/do/search?q=" },
        { displayName: "Ecosia", value: "https://www.ecosia.org/search?q=" },
        { displayName: "Kagi", value: "https://kagi.com/search?q=" },
        { displayName: "Yandex", value: "https://yandex.ru/search/?text=" }
    ].map(engine => Object.assign(engine, { description: engine.value }))

    // Ready-made system prompts: the shell's own and ones in ~/.config/illogical-impulse/ai/prompts
    property var promptFiles: []
    Process {
        running: true
        command: ["bash", "-c", `for dir in '${Directories.defaultAiPrompts}' '${Directories.userAiPrompts}'; do ls -1 "$dir"/*.md "$dir"/*.txt 2>/dev/null; done`]
        stdout: StdioCollector {
            onStreamFinished: root.promptFiles = text.split("\n").filter(line => line.length > 0)
        }
    }
    FileView {
        id: promptFile
        onLoaded: {
            Config.options.ai.systemPrompt = promptFile.text();
            promptField.value = Config.options.ai.systemPrompt;
        }
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
                PrefixRow { prefixKey: "app"; icon: "apps"; label: Translation.tr("Apps") }
                PrefixRow { prefixKey: "action"; icon: "bolt"; label: Translation.tr("Action") }
                PrefixRow { prefixKey: "clipboard"; icon: "content_paste"; label: Translation.tr("Clipboard") }
                PrefixRow { prefixKey: "emojis"; icon: "mood"; label: Translation.tr("Emojis") }
                PrefixRow { prefixKey: "math"; icon: "calculate"; label: Translation.tr("Math") }
                PrefixRow { prefixKey: "shellCommand"; icon: "terminal"; label: Translation.tr("Shell command") }
                PrefixRow { prefixKey: "webSearch"; icon: "travel_explore"; label: Translation.tr("Web search") }
            }
        }

        ConfigComboRow {
            readonly property bool known: root.searchEngines.some(engine => engine.value === Config.options.search.engineBaseUrl)
            icon: "public"
            text: Translation.tr("Web search")
            description: Translation.tr("Where the web search prefix and “Search the web” go")
            options: root.searchEngines
            currentValue: Config.options.search.engineBaseUrl
            customLabel: Translation.tr("Other site…")
            customDescription: Translation.tr("A URL the search query is added to")
            customPlaceholder: "https://example.com/search?q="
            customActive: !known
            customValue: known ? "" : Config.options.search.engineBaseUrl
            onSelected: value => Config.options.search.engineBaseUrl = value
            onCustomEntered: text => Config.options.search.engineBaseUrl = text
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
        ConfigComboRow {
            visible: root.promptFiles.length > 0
            enabled: Config.options.policies.ai !== 0
            icon: "library_books"
            text: Translation.tr("Prompt presets")
            description: Translation.tr("Replaces the system prompt below")
            placeholderText: Translation.tr("Load a preset…")
            options: root.promptFiles.map(path => ({
                displayName: path.split("/").pop().replace(/\.(md|txt)$/, "").replace(/[-_]/g, " "),
                value: path,
                description: path.startsWith(Directories.userAiPrompts) ? Translation.tr("Yours") : ""
            }))
            onSelected: value => {
                promptFile.path = "";
                promptFile.path = value;
            }
        }
        ConfigTextRow {
            id: promptField
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
