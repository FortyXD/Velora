import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.translator
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Translator: offline English <-> Russian (OfflineTranslator service) by default,
 * or online through the `trans` command line tool. Offline results can be refined by a local LLM.
 */
Item {
    id: root

    // Sizes
    property real padding: 4

    // Widgets
    property var inputField: inputCanvas.inputTextArea

    // "offline" or "online"; "auto" means offline once the models are installed
    property string engine: {
        const configured = Config.options.language.translator.mode;
        if (configured === "online" || configured === "offline") return configured;
        return (OfflineTranslator.checked && !OfflineTranslator.installed) ? "online" : "offline";
    }
    readonly property bool offline: root.engine === "offline"

    // Results
    property string translatedText: ""
    property string unrefinedText: "" // To undo a refinement
    property string lastTranslatedInput: ""
    property string lastTranslatedKey: ""
    property int pendingRequestId: -1
    property bool translating: false
    property string errorText: ""
    property var abortRefine: null
    readonly property bool refining: root.abortRefine !== null

    // Offline languages: source "auto", "en" or "ru"; the target is always the other one
    property string offlineSource: "auto"
    readonly property string detectedSource: OfflineTranslator.detectLanguage(root.inputField?.text ?? "")
    readonly property string effectiveSource: root.offlineSource === "auto" ? root.detectedSource : root.offlineSource
    readonly property string effectiveTarget: OfflineTranslator.otherLanguage(root.effectiveSource)

    // Online languages (trans)
    property list<string> languages: []
    property string targetLanguage: Config.options.language.translator.targetLanguage
    property string sourceLanguage: Config.options.language.translator.sourceLanguage

    // States
    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target language, false for source language

    function languageName(code) {
        return OfflineTranslator.languages[code] ?? code;
    }

    function setEngine(newEngine) {
        Config.options.language.translator.mode = newEngine;
        root.lastTranslatedKey = "";
        if (newEngine === "online" && root.languages.length === 0) getLanguagesProc.running = true;
        root.translateNow();
    }

    function showLanguageSelectorDialog(isTargetLang: bool) {
        root.languageSelectorTarget = isTargetLang;
        root.showLanguageSelector = true;
    }

    function swapLanguages() {
        if (root.offline) {
            root.offlineSource = root.effectiveTarget;
        } else {
            if (root.sourceLanguage === "auto") return;
            const source = root.sourceLanguage;
            Config.options.language.translator.sourceLanguage = root.targetLanguage;
            Config.options.language.translator.targetLanguage = source;
        }
        // Continue from the translation: it becomes the new input
        if (root.translatedText.trim().length > 0) root.inputField.text = root.translatedText;
        else root.translateNow();
    }

    function cancelRefine() {
        if (root.abortRefine) root.abortRefine();
        root.abortRefine = null;
    }

    function translateNow() {
        translateTimer.stop();
        const text = root.inputField.text.trim();
        if (text.length === 0) {
            root.translatedText = "";
            root.unrefinedText = "";
            root.errorText = "";
            root.lastTranslatedKey = "";
            return;
        }
        const key = root.offline ? `offline|${root.effectiveSource}|${text}` : `online|${root.sourceLanguage}|${root.targetLanguage}|${text}`;
        if (key === root.lastTranslatedKey) return; // Nothing changed, don't spend CPU
        root.lastTranslatedKey = key;
        root.cancelRefine();
        root.unrefinedText = "";
        root.errorText = "";

        if (root.offline) {
            if (!OfflineTranslator.installed) return;
            root.translating = true;
            const id = OfflineTranslator.translate(text, root.effectiveSource, root.effectiveTarget, (result, error) => {
                if (id !== root.pendingRequestId) return; // A newer request is on its way
                root.translating = false;
                root.errorText = error;
                if (!error) {
                    root.translatedText = result;
                    root.lastTranslatedInput = text;
                }
            });
            root.pendingRequestId = id;
        } else {
            root.translating = true;
            translateProc.running = false;
            translateProc.buffer = "";
            translateProc.running = true;
        }
    }

    // Local Ollama model for refinement: configured one, otherwise the smallest installed
    function refineModel() {
        const configured = Config.options.language.translator.llmModel;
        if (configured.length > 0) return configured;
        const local = Object.values(Ai.models).filter(model => model.local).sort((a, b) => a.size - b.size);
        return local[0]?.model ?? "";
    }

    function refine() {
        const model = root.refineModel();
        if (model.length === 0) {
            root.errorText = Translation.tr("No local Ollama model found");
            return;
        }
        const text = root.lastTranslatedInput;
        const draft = root.translatedText;
        root.errorText = "";
        root.abortRefine = OfflineTranslator.refine(text, draft, root.effectiveSource, root.effectiveTarget, model, (result, error) => {
            root.abortRefine = null;
            if (error) {
                root.errorText = error;
                return;
            }
            if (result.length === 0) return; // Canceled
            root.unrefinedText = draft;
            root.translatedText = result;
        });
    }

    Component.onCompleted: {
        OfflineTranslator.checkInstalled();
        if (!root.offline) getLanguagesProc.running = true;
        if (!Object.values(Ai.models).some(model => model.local)) Ai.refreshLists(); // For refinement
    }

    onFocusChanged: (focus) => {
        if (focus) {
            root.inputField.forceActiveFocus()
        }
    }

    Timer {
        id: translateTimer
        // Offline translation runs on this machine: wait for a real pause in typing
        interval: root.offline ? Math.max(Config.options.sidebar.translator.delay, 700) : Config.options.sidebar.translator.delay
        repeat: false
        onTriggered: root.translateNow()
    }

    Connections {
        target: OfflineTranslator
        function onInstalledChanged() {
            if (OfflineTranslator.installed) root.translateNow();
        }
    }

    Process {
        id: translateProc
        command: ["bash", "-c", `trans -brief -no-bidi`
            + (["auto", ""].includes(Config.options.language.translator.engine) ? ""
                : ` -e '${StringUtils.shellSingleQuoteEscape(Config.options.language.translator.engine)}'`)
            + ` -source '${StringUtils.shellSingleQuoteEscape(root.sourceLanguage)}'`
            + ` -target '${StringUtils.shellSingleQuoteEscape(root.targetLanguage)}'`
            + ` '${StringUtils.shellSingleQuoteEscape(root.inputField.text.trim())}'`]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                translateProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            // With -brief mode, we get output with no metadata
            root.translating = false;
            root.translatedText = translateProc.buffer.trim();
            root.lastTranslatedInput = root.inputField.text.trim();
            if (exitCode !== 0 || root.translatedText.length === 0)
                root.errorText = Translation.tr("Online translation failed. Check your connection.");
        }
    }

    Process {
        id: getLanguagesProc
        command: ["trans", "-list-languages", "-no-bidi"]
        property list<string> bufferList: ["auto"]
        stdout: SplitParser {
            onRead: data => {
                getLanguagesProc.bufferList.push(data.trim());
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Ensure "auto" is always the first language
            let langs = getLanguagesProc.bufferList
                .filter(lang => lang.trim().length > 0 && lang !== "auto")
                .sort((a, b) => a.localeCompare(b));
            langs.unshift("auto");
            root.languages = langs;
            getLanguagesProc.bufferList = []; // Clear the buffer
        }
    }

    component EngineButton: RippleButton {
        id: engineButton
        required property string label
        Layout.fillWidth: true
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        contentItem: StyledText {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.small
            color: engineButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            text: engineButton.label
        }
    }

    component IconAction: GroupButton {
        id: iconAction
        property string symbol
        property string tooltip
        baseWidth: baseHeight // Square; not "height", which is 0 before the first layout pass
        buttonRadius: Appearance.rounding.small
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            iconSize: Appearance.font.pixelSize.larger
            text: iconAction.symbol
            color: iconAction.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
        }
        StyledToolTip {
            text: iconAction.tooltip
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 8

        RowLayout { // Engine
            Layout.fillWidth: true
            Layout.fillHeight: false // Nested layouts fill height by default
            spacing: 4
            EngineButton {
                label: Translation.tr("Offline")
                toggled: root.engine === "offline"
                onClicked: root.setEngine("offline")
            }
            EngineButton {
                label: Translation.tr("Online")
                toggled: root.engine === "online"
                onClicked: root.setEngine("online")
            }
        }

        RowLayout { // Languages
            Layout.fillWidth: true
            Layout.fillHeight: false // Nested layouts fill height by default
            spacing: 4

            LanguageSelectorButton {
                Layout.fillWidth: true
                displayText: root.offline
                    ? (root.offlineSource === "auto"
                        ? Translation.tr("Auto (%1)").arg(root.languageName(root.detectedSource))
                        : root.languageName(root.offlineSource))
                    : root.sourceLanguage
                onClicked: {
                    if (root.offline) { // Cycle auto -> English -> Russian
                        root.offlineSource = root.offlineSource === "auto" ? "en" : (root.offlineSource === "en" ? "ru" : "auto");
                        root.translateNow();
                    } else {
                        root.showLanguageSelectorDialog(false);
                    }
                }
            }

            RippleButton { // Swap
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                enabled: root.offline || root.sourceLanguage !== "auto"
                onClicked: root.swapLanguages()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "swap_horiz"
                    color: parent.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: Translation.tr("Swap languages")
                }
            }

            LanguageSelectorButton {
                Layout.fillWidth: true
                enabled: !root.offline
                displayText: root.offline ? root.languageName(root.effectiveTarget) : root.targetLanguage
                onClicked: root.showLanguageSelectorDialog(true)
            }
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: contentColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: contentColumn
                width: parent.width
                spacing: 8

                TextCanvas { // Input
                    id: inputCanvas
                    isInput: true
                    placeholderText: Translation.tr("Enter text to translate...")
                    onInputTextChanged: translateTimer.restart()
                    onAccepted: { // Enter: translate right away
                        root.lastTranslatedKey = "";
                        root.translateNow();
                    }
                    IconAction {
                        symbol: "content_paste"
                        tooltip: Translation.tr("Paste")
                        onClicked: root.inputField.text = Quickshell.clipboardText
                    }
                    IconAction {
                        symbol: "close"
                        tooltip: Translation.tr("Clear")
                        enabled: inputCanvas.inputTextArea.text.length > 0
                        onClicked: root.inputField.text = ""
                    }
                }

                Rectangle { // Not installed / installing
                    visible: root.offline && OfflineTranslator.checked && !OfflineTranslator.installed
                    Layout.fillWidth: true
                    implicitHeight: installColumn.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        id: installColumn
                        anchors {
                            fill: parent
                            margins: 12
                        }
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: OfflineTranslator.installing
                                ? OfflineTranslator.installStatus
                                : Translation.tr("Offline English ↔ Russian needs a one-time download (about 350 MB). Translation then runs on this computer, without internet.")
                        }
                        StyledProgressBar {
                            visible: OfflineTranslator.installing
                            Layout.fillWidth: true
                            value: OfflineTranslator.installProgress / 100
                        }
                        StyledText {
                            visible: OfflineTranslator.installError.length > 0
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Appearance.m3colors.m3error
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: OfflineTranslator.installError
                        }
                        RippleButtonWithIcon {
                            visible: !OfflineTranslator.installing
                            Layout.alignment: Qt.AlignRight
                            materialIcon: "download"
                            mainText: OfflineTranslator.installError.length > 0 ? Translation.tr("Try again") : Translation.tr("Install")
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: OfflineTranslator.install()
                        }
                    }
                }

                TextCanvas { // Output
                    id: outputCanvas
                    isInput: false
                    opacity: (root.translating || root.refining) ? 0.6 : 1
                    placeholderText: root.refining ? Translation.tr("Refining with %1…").arg(root.refineModel())
                        : root.translating ? Translation.tr("Translating…")
                        : Translation.tr("Translation goes here...")
                    text: root.translatedText

                    IconAction {
                        symbol: "undo"
                        tooltip: Translation.tr("Undo refinement")
                        visible: root.unrefinedText.length > 0
                        onClicked: {
                            root.translatedText = root.unrefinedText;
                            root.unrefinedText = "";
                        }
                    }
                    IconAction {
                        symbol: root.refining ? "stop" : "auto_awesome"
                        tooltip: root.refining ? Translation.tr("Stop refining")
                            : Translation.tr("Refine with a local LLM (%1). Slower, uses more power").arg(root.refineModel() || Translation.tr("none installed"))
                        visible: root.offline
                        enabled: root.refining || (root.translatedText.length > 0 && !root.translating && root.unrefinedText.length === 0)
                        onClicked: root.refining ? root.cancelRefine() : root.refine()
                    }
                    IconAction {
                        symbol: "content_copy"
                        tooltip: Translation.tr("Copy")
                        enabled: root.translatedText.trim().length > 0
                        onClicked: Quickshell.clipboardText = root.translatedText
                    }
                    IconAction {
                        symbol: "travel_explore"
                        tooltip: Translation.tr("Search the web")
                        enabled: root.translatedText.trim().length > 0
                        onClicked: {
                            let url = Config.options.search.engineBaseUrl + root.translatedText;
                            for (let site of Config.options.search.excludedSites) {
                                url += ` -site:${site}`;
                            }
                            Qt.openUrlExternally(url);
                        }
                    }
                }

                StyledText { // Errors
                    visible: root.errorText.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    wrapMode: Text.Wrap
                    color: Appearance.m3colors.m3error
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: root.errorText
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.showLanguageSelector
        visible: root.showLanguageSelector
        z: 9999
        sourceComponent: SelectionDialog {
            id: languageSelectorDialog
            titleText: Translation.tr("Select Language")
            items: root.languages
            defaultChoice: root.languageSelectorTarget ? root.targetLanguage : root.sourceLanguage
            onCanceled: () => {
                root.showLanguageSelector = false;
            }
            onSelected: (result) => {
                root.showLanguageSelector = false;
                if (!result || result.length === 0) return; // No selection made

                if (root.languageSelectorTarget) {
                    Config.options.language.translator.targetLanguage = result; // Save to config
                } else {
                    Config.options.language.translator.sourceLanguage = result; // Save to config
                }

                root.translateNow(); // Translate again after language change
            }
        }
    }
}
