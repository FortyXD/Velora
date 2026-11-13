import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.services

SettingsDetailPage {
    id: root

    readonly property var searchEngines: [
        {
            "displayName": "Google",
            "value": "https://www.google.com/search?q="
        },
        {
            "displayName": "DuckDuckGo",
            "value": "https://duckduckgo.com/?q="
        },
        {
            "displayName": "Brave Search",
            "value": "https://search.brave.com/search?q="
        },
        {
            "displayName": "Bing",
            "value": "https://www.bing.com/search?q="
        },
        {
            "displayName": "Startpage",
            "value": "https://www.startpage.com/do/search?q="
        },
        {
            "displayName": "Ecosia",
            "value": "https://www.ecosia.org/search?q="
        },
        {
            "displayName": "Kagi",
            "value": "https://kagi.com/search?q="
        },
        {
            "displayName": "Yandex",
            "value": "https://yandex.ru/search/?text="
        }
    ].map(engine => {
        return Object.assign(engine, {
                                 "description": engine.value
                             });
    })

    fitToWindow: true
    maxContentWidth: 940
    overviewKey: "search"
    sectionTitles: ({
                        files: Translation.tr("Files and folders"),
                        indexing: Translation.tr("Indexing"),
                        behavior: Translation.tr("Search behavior"),
                        music: Translation.tr("Music recognition")
                    })

    Item {
        Layout.fillHeight: true
        Layout.fillWidth: true

        SettingsTabPage {
            anchors.fill: parent
            current: root.tab
            enabled: shown
            key: "search"

            onRevealRequested: key => root.tab = key

            SettingsScrollPane {
                anchors.fill: parent
                objectName: "searchOverviewScroll"

                Loader {
                    Layout.fillWidth: true
                    active: root.pageShown && root.tab === "search"

                    sourceComponent: SearchPreview {
                    }
                }

                ContentSection {
                    ConfigSwitch {
                        autoToggle: false
                        buttonIcon: "neurology"
                        objectName: "searchAiEnable"
                        text: Translation.tr("AI in search")
                        description: Translation.tr("Show Ask AI and Run a task in the launcher. Off by default.")
                        checked: Config.options.search.ai.enabled
                        enabled: Config.options.policies.ai !== 0
                        onClicked: {
                            Config.options.search.ai.enabled = !checked;
                            if (Config.options.search.ai.enabled) Config.options.assistant.enabled = true;
                        }
                    }
                    ConfigSwitch {
                        autoToggle: false
                        buttonIcon: "manage_search"
                        objectName: "searchLensEnable"
                        text: Translation.tr("Search across your files")
                        description: Translation.tr("Build a local index of selected folders. Off stops indexing and hides its search results.")
                        checked: Lens.enabled
                        onClicked: Config.options.search.lens.enabled = !checked
                    }
                    ConfigNavRow {
                        buttonIcon: "folder"
                        description: !Lens.enabled ? Translation.tr("Off") : Lens.status.locked
                                                     ? lens.statusTitle : Translation.tr(
                                                           "%1 folders · %2 excluded").arg(
                                                           lens.folders.length).arg(lens.excludes.length)
                        objectName: "searchFoldersSummary"
                        title: Translation.tr("Files and folders")

                        onClicked: {
                            forceActiveFocus();
                            root.tab = "files";
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        objectName: "searchIndexingGroup"
                        spacing: 0

                        ConfigNavRow {
                            buttonIcon: "manage_search"
                            description: Lens.enabled || Lens.setupRunning ? lens.statusTitle : Translation.tr(
                                                                                 "Search across your files")
                            objectName: "searchIndexingSummary"
                            title: Translation.tr("Indexing")

                            onClicked: {
                                forceActiveFocus();
                                root.tab = "indexing";
                            }
                        }

                        ColumnLayout {
                            Layout.bottomMargin: 12
                            Layout.fillWidth: true
                            Layout.leftMargin: 50
                            Layout.rightMargin: 16
                            objectName: "searchIndexSummaryProgress"
                            spacing: 6
                            visible: Lens.setupRunning || lens.showIndexProgress

                            StyledText {
                                Layout.fillWidth: true
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                objectName: "searchIndexSummaryCount"
                                text: Lens.setupRunning ? lens.setupMetric() : lens.indexTotalKnown
                                                          ? Translation.tr("%1 of %2 processed").arg(
                                                                lens.count(lens.indexCompleted)).arg(
                                                                lens.count(lens.indexTotal)) : Translation.tr(
                                                                "Found %1 items · counting…").arg(lens.count(
                                                                                                      lens.indexTotal))
                                wrapMode: Text.Wrap
                            }

                            StyledProgressBar {
                                Layout.fillWidth: true
                                value: Lens.setupRunning ? lens.ratio(lens.setupProgress.done ?? 0,
                                                                      lens.setupProgress.total) : lens.ratio(
                                                               lens.indexCompleted, lens.indexTotal)
                                visible: Lens.setupRunning ? lens.setupMeasured : lens.indexTotalKnown
                                                             && lens.indexTotal > 0
                            }

                            StyledIndeterminateProgressBar {
                                Layout.fillWidth: true
                                visible: Lens.setupRunning ? !lens.setupMeasured : !lens.indexTotalKnown
                            }
                        }
                    }

                    ConfigNavRow {
                        buttonIcon: "folder_managed"
                        description: Translation.tr(
                                         "They stay out of the index until you choose. Other folders continue indexing.")
                        objectName: "searchReviewSummary"
                        title: Translation.tr("Choose which large folders to search")
                        visible: lens.sourceReviews.length > 0

                        onClicked: {
                            root.tab = "files";
                            root.revealItem(lens.sourceReviewItem);
                        }
                    }

                    ConfigNavRow {
                        buttonIcon: "error"
                        description: Lens.problem || Lens.setupLabel()
                        objectName: "searchProblemSummary"
                        title: Translation.tr("Search needs attention")
                        visible: Lens.enabled && (lens.setupFailed || !!Lens.problem)

                        onClicked: {
                            forceActiveFocus();
                            root.tab = "indexing";
                        }
                    }

                    ConfigNavRow {
                        buttonIcon: "tune"
                        description: (root.searchEngines.find(engine => engine.value
                                                                        === Config.options.search.engineBaseUrl)
                                      ?.displayName ?? Translation.tr("Custom")) + " · " + (
                                         Config.options.search.sloppy ? Translation.tr("Typo correction on") :
                                                                        Translation.tr("Typo correction off"))
                        objectName: "searchBehaviorSummary"
                        title: Translation.tr("Search behavior")

                        onClicked: {
                            forceActiveFocus();
                            root.tab = "behavior";
                        }
                    }

                    ConfigNavRow {
                        buttonIcon: "more_horiz"
                        description: Translation.tr("Music recognition")
                        objectName: "searchMoreSummary"
                        title: Translation.tr("More options")

                        onClicked: {
                            forceActiveFocus();
                            root.tab = "music";
                        }
                    }
                }
            }
        }

        SettingsTabPage {
            anchors.fill: parent
            current: root.tab
            enabled: shown
            key: "behavior"

            onRevealRequested: key => root.tab = key

            SettingsScrollPane {
                anchors.fill: parent

                ContentSection {
                    description: Translation.tr("Changes apply to the launcher immediately.")
                    icon: "search"
                    title: Translation.tr("Search behavior")

                    ConfigSwitch {
                        buttonIcon: "spellcheck"
                        checked: Config.options.search.sloppy
                        description: Translation.tr(
                                         "Match misspelled app names. Turn off to match abbreviations more easily.")
                        text: Translation.tr("Prefer typo correction")

                        onCheckedChanged: {
                            Config.options.search.sloppy = checked;
                        }
                    }

                    ConfigExpander {
                        description: Translation.tr("Type one of these first to switch the search mode")
                        expanded: false
                        objectName: "searchPrefixes"
                        title: Translation.tr("Search shortcuts")

                        GridLayout {
                            Layout.fillWidth: true
                            columnSpacing: 0
                            columns: width >= 560 ? 2 : 1
                            rowSpacing: 0
                            uniformCellWidths: true

                            PrefixRow {
                                icon: "apps"
                                label: Translation.tr("Apps")
                                prefixKey: "app"
                            }

                            PrefixRow {
                                icon: "bolt"
                                label: Translation.tr("Action")
                                prefixKey: "action"
                            }

                            PrefixRow {
                                icon: "content_paste"
                                label: Translation.tr("Clipboard")
                                prefixKey: "clipboard"
                            }

                            PrefixRow {
                                icon: "mood"
                                label: Translation.tr("Emojis")
                                prefixKey: "emojis"
                            }

                            PrefixRow {
                                icon: "calculate"
                                label: Translation.tr("Math")
                                prefixKey: "math"
                            }

                            PrefixRow {
                                icon: "terminal"
                                label: Translation.tr("Shell command")
                                prefixKey: "shellCommand"
                            }

                            PrefixRow {
                                icon: "travel_explore"
                                label: Translation.tr("Web search")
                                prefixKey: "webSearch"
                            }
                        }
                    }

                    ConfigComboRow {
                        readonly property bool known: root.searchEngines.some(engine => {
                            return engine.value === Config.options.search.engineBaseUrl;
                        })

                        currentValue: Config.options.search.engineBaseUrl
                        customActive: !known
                        customDescription: Translation.tr("A URL the search query is added to")
                        customLabel: Translation.tr("Other site…")
                        customPlaceholder: "https://example.com/search?q="
                        customValue: known ? "" : Config.options.search.engineBaseUrl
                        description: Translation.tr("Where the web search prefix and “Search the web” go")
                        icon: "public"
                        options: root.searchEngines
                        text: Translation.tr("Web search")

                        onCustomEntered: text => {
                            return Config.options.search.engineBaseUrl = text;
                        }
                        onSelected: value => {
                            return Config.options.search.engineBaseUrl = value;
                        }
                    }
                }
            }
        }

        LensSettings {
            id: lens

            anchors.fill: parent
            currentTab: root.tab
            enabled: z === 1
            pageShown: root.pageShown
            z: root.tab === "files" || root.tab === "indexing" ? 1 : 0

            onTabRequested: key => root.tab = key
        }

        SettingsTabPage {
            anchors.fill: parent
            current: root.tab
            enabled: shown
            key: "music"

            onRevealRequested: key => {
                return root.tab = key;
            }

            SettingsScrollPane {
                anchors.fill: parent

                ContentSection {
                    description: Translation.tr("Identifies the song that is playing, from the right sidebar")
                    icon: "music_cast"
                    title: Translation.tr("Music recognition")

                    ConfigRow {
                        uniform: true

                        ConfigSpinBox {
                            from: 10
                            icon: "timer_off"
                            stepSize: 2
                            text: Translation.tr("Total duration timeout (s)")
                            to: 100
                            value: Config.options.musicRecognition.timeout

                            onValueChanged: {
                                Config.options.musicRecognition.timeout = value;
                            }
                        }

                        ConfigSpinBox {
                            from: 2
                            icon: "av_timer"
                            stepSize: 1
                            text: Translation.tr("Polling interval (s)")
                            to: 10
                            value: Config.options.musicRecognition.interval

                            onValueChanged: {
                                Config.options.musicRecognition.interval = value;
                            }
                        }
                    }
                }
            }
        }
    }

    // One or two characters, saved on Enter; an empty prefix would match every search
    component PrefixRow: ConfigTextRow {
        id: prefixRow

        required property string prefixKey

        inline: true
        inlineFieldWidth: 120
        monospace: true
        value: Config.options.search.prefix[prefixKey]
        wrapMode: TextEdit.NoWrap

        onEditingFinished: {
            const prefix = value.trim();
            if (prefix.length > 0)
                Config.options.search.prefix[prefixKey] = prefix;
            else
                value = Config.options.search.prefix[prefixKey];
        }
        onValueChanged: {
            if (value.length > 2) {
                value = value.slice(0, 2);
            }
        }
    }
}
