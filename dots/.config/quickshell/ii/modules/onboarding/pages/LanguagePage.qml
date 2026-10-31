pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.onboarding
import qs.modules.settings.keyboard
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Language and keyboard, side by side and all in sight. Languages are tiles: picking one redraws the
 * assistant in it at once. The keyboard is drawn as in Settings → Keyboard, in the layout you type in
 * now: Alt+Shift (or a click on a layout) redraws it, and the keys you press light up. The field under
 * it has the keyboard from the start, so typing needs no click first. Filled in from the system.
 */
PageScaffold {
    id: root
    title: Translation.tr("Language and keyboard")
    subtitle: Translation.tr("Taken from your system. Change them if they aren't right.")
    focusTarget: tryField

    // Keyboard layouts people add most, with their own names
    readonly property var commonLayouts: [
        ["us", "English (US)"], ["gb", "English (UK)"], ["ru", "Русская"], ["ua", "Українська"], ["by", "Беларуская"],
        ["kz", "Қазақша"], ["de", "Deutsch"], ["fr", "Français"], ["es", "Español"], ["it", "Italiano"], ["pt", "Português"],
        ["br", "Português (Brasil)"], ["pl", "Polski"], ["cz", "Čeština"], ["tr", "Türkçe"], ["ge", "ქართული"],
        ["am", "Հայերեն"], ["il", "עברית"], ["ara", "العربية"], ["gr", "Ελληνικά"], ["se", "Svenska"], ["no", "Norsk"],
        ["fi", "Suomi"], ["nl", "Nederlands"], ["hu", "Magyar"], ["ro", "Română"], ["bg", "Български"], ["rs", "Српски"],
        ["jp", "日本語"], ["kr", "한국어"], ["cn", "中文"],
    ]
    function layoutName(code) {
        return root.commonLayouts.find(entry => entry[0] === code)?.[1] ?? code.toUpperCase();
    }

    // Layouts and variants are lists that must stay in step, so they are always written together
    readonly property var layouts: HyprlandSettings.get("input:kb_layout", "us").split(",").map(code => code.trim()).filter(code => code.length > 0)
    readonly property var variants: {
        const variants = HyprlandSettings.get("input:kb_variant", "").split(",").map(code => code.trim());
        return root.layouts.map((_, index) => variants[index] ?? "");
    }
    function setLayouts(layouts, variants) {
        if (layouts.length === 0) return;
        if (root.flow.dryRun) {
            console.info("[Onboarding] Would set keyboard layouts", layouts.join(","), "variants", variants.join(","));
            return;
        }
        const variantText = variants.some(code => code.length > 0) ? variants.join(",") : "";
        HyprlandSettings.setMany({ "input:kb_layout": layouts.join(","), "input:kb_variant": variantText });
    }
    function removeLayout(index) {
        root.setLayouts(root.layouts.filter((_, i) => i !== index), root.variants.filter((_, i) => i !== index));
        if (root.shownIndex >= index && root.shownIndex > 0) root.shownIndex--;
    }

    // The layout drawn: the one you type in, followed as it switches
    property int shownIndex: 0
    function followTyping() {
        const index = root.layouts.indexOf(HyprlandXkb.currentLayoutCode);
        if (index >= 0) root.shownIndex = index;
    }
    Component.onCompleted: {
        root.followTyping();
        Qt.callLater(root.preloadKeys);
    }
    Connections {
        target: HyprlandXkb
        function onCurrentLayoutCodeChanged() { root.followTyping(); }
    }
    function switchTo(index) {
        root.shownIndex = index;
        root.flow.run(["hyprctl", "switchxkblayout", "all", String(index)]);
        tryField.forceActiveFocus();
    }
    readonly property string shownLayout: root.layouts[Math.min(root.shownIndex, root.layouts.length - 1)] ?? "us"
    readonly property string shownVariant: root.variants[Math.min(root.shownIndex, root.variants.length - 1)] ?? ""

    // What each key types in it (`velora-helper layout-keys`, as in Settings → Keyboard)
    property var keys: ({})
    property var keyCache: ({})
    property var loadingKeys: ({})
    property var pressedCodes: []
    readonly property string keyId: JSON.stringify([root.shownLayout, root.shownVariant])
    onKeyIdChanged: Qt.callLater(root.showKeys)
    onLayoutsChanged: Qt.callLater(root.preloadKeys)
    onVariantsChanged: Qt.callLater(root.preloadKeys)
    function showKeys() {
        root.keys = root.keyCache[root.keyId] ?? {};
        root.loadKeys(root.shownLayout, root.shownVariant);
    }
    function preloadKeys() {
        root.layouts.forEach((layout, index) => root.loadKeys(layout, root.variants[index] ?? ""));
        root.showKeys();
    }
    function loadKeys(layout, variant) {
        const key = JSON.stringify([layout, variant]);
        if (root.keyCache[key] || root.loadingKeys[key]) return;
        root.loadingKeys[key] = true;
        keyJob.createObject(root, { "keyId": key,
            "command": [Quickshell.shellPath("scripts/helper"), "layout-keys", layout, variant] });
    }
    Component {
        id: keyJob
        Process {
            id: job
            required property string keyId
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const result = JSON.parse(text);
                        root.keyCache[job.keyId] = result.keys ?? {};
                        if (job.keyId === root.keyId) root.keys = root.keyCache[job.keyId];
                    } catch (error) {
                        console.warn("[Onboarding] Couldn't read keyboard layout:", error);
                    }
                    delete root.loadingKeys[job.keyId];
                    job.destroy();
                }
            }
        }
    }

    // Scripts this system has fonts for; without one, a name shows as boxes, so it's written in Latin letters
    readonly property var latinNames: ({ "ja": "Japanese", "zh": "Chinese", "ko": "Korean", "ar": "Arabic", "he": "Hebrew",
        "th": "Thai", "hi": "Hindi", "fa": "Persian", "ka": "Georgian", "hy": "Armenian" })
    property var scriptsWithFonts: []
    Process {
        running: true
        command: ["bash", "-c", 'for l in ja zh ko ar he th hi fa ka hy; do [ -n "$(fc-list ":lang=$l" family 2>/dev/null | head -1)" ] && echo "$l"; done']
        stdout: StdioCollector {
            onStreamFinished: root.scriptsWithFonts = text.split("\n").filter(line => line.length > 0)
        }
    }
    function nativeName(code) {
        const language = code.split("_")[0];
        if (root.latinNames[language] && !root.scriptsWithFonts.includes(language)) return root.latinNames[language];
        return Translation.languageNames[code] ?? code;
    }

    component Heading: StyledText {
        font.pixelSize: Appearance.font.pixelSize.larger
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnLayer0
    }

    Reveal {
        order: 1
        RowLayout {
            width: parent.width
            height: root.areaHeight
            spacing: 28

            // Languages: two columns of tiles, all of them in sight
            ColumnLayout {
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
                Layout.fillHeight: true
                spacing: 12
                Heading {
                    text: Translation.tr("Interface language")
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: languageGrid.implicitHeight
                    interactive: contentHeight > height
                    clip: interactive
                    boundsBehavior: Flickable.StopAtBounds
                    GridLayout {
                        id: languageGrid
                        width: parent.width
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 8
                        Repeater {
                            model: ["auto", ...Translation.allAvailableLanguages]
                            delegate: Rectangle {
                                id: language
                                required property string modelData
                                readonly property bool selected: (root.flow.choices.language ?? "auto") === language.modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                implicitHeight: 42
                                radius: Appearance.rounding.normal
                                color: language.selected ? Appearance.colors.colSecondaryContainer
                                    : languageArea.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                                border.width: language.selected ? 2 : 1
                                border.color: language.selected ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                Behavior on color {
                                    ColorAnimation { duration: Motion.ms(160) }
                                }
                                MouseArea {
                                    id: languageArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.flow.applyLanguage(language.modelData)
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: language.modelData === "auto" ? Translation.tr("Same as the system") : root.nativeName(language.modelData)
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: language.selected ? Font.DemiBold : Font.Normal
                                        color: language.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        text: "check_circle"
                                        iconSize: 18
                                        fill: 1
                                        color: Appearance.colors.colPrimary
                                        scale: language.selected ? 1 : 0
                                        Behavior on scale {
                                            NumberAnimation { duration: Motion.ms(300); easing.type: Easing.OutBack }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Keyboard: your layouts, the drawn keys, and a place to type
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Heading {
                        Layout.fillWidth: true
                        text: Translation.tr("Keyboard")
                    }
                    KeyCombo {
                        mods: ["Alt"]
                        key: "Shift"
                    }
                    StyledText {
                        text: Translation.tr("switches the layout")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                // Your layouts: the one you type in is lit; a click switches to it
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.layouts
                        delegate: Item {
                            id: chip
                            required property string modelData
                            required property int index
                            readonly property bool shown: chip.index === Math.min(root.shownIndex, root.layouts.length - 1)
                            readonly property bool removable: root.layouts.length > 1
                            width: chipButton.implicitWidth
                            height: 36
                            RippleButton {
                                id: chipButton
                                anchors.fill: parent
                                focusPolicy: Qt.NoFocus
                                leftPadding: 6
                                rightPadding: chip.removable ? 34 : 14
                                buttonRadius: Appearance.rounding.full
                                colBackground: chip.shown ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                                colBackgroundHover: chip.shown ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                                onClicked: root.switchTo(chip.index)
                                contentItem: Row {
                                    spacing: 8
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 34
                                        height: 24
                                        radius: 12
                                        color: chip.shown ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                                        Behavior on color {
                                            ColorAnimation { duration: Motion.ms(200) }
                                        }
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: chip.modelData.slice(0, 3).toUpperCase()
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: chip.shown ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                                        }
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.layoutName(chip.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: chip.shown ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                            // Going: a small cross
                            RippleButton {
                                visible: chip.removable
                                anchors.right: parent.right
                                anchors.rightMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                focusPolicy: Qt.NoFocus
                                enabled: HyprlandSettings.ready
                                implicitWidth: 26
                                implicitHeight: 26
                                buttonRadius: 13
                                onClicked: {
                                    root.removeLayout(chip.index);
                                    tryField.forceActiveFocus();
                                }
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "close"
                                    iconSize: 16
                                    color: chip.shown ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                    ChoiceDropdown {
                        focusPolicy: Qt.NoFocus
                        enabled: HyprlandSettings.ready
                        implicitHeight: 36
                        maximumWidth: 180
                        minimumWidth: 100
                        placeholderText: Translation.tr("Add")
                        displayIcon: "add"
                        searchable: true
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        options: root.commonLayouts.filter(entry => !root.layouts.includes(entry[0]))
                            .map(entry => ({ "displayName": entry[1], "value": entry[0], "description": entry[0] }))
                        onSelected: value => {
                            root.setLayouts([...root.layouts, value], [...root.variants, ""]);
                            tryField.forceActiveFocus();
                        }
                    }
                }

                KeyboardVisual {
                    Layout.fillWidth: true
                    keys: root.keys
                    pressedCodes: root.pressedCodes
                }

                // Typing goes here from the start, no click needed; the keys light up above
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 52
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: tryField.activeFocus ? 2 : 1
                    border.color: tryField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: tryField.forceActiveFocus()
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        spacing: 10
                        MaterialSymbol {
                            text: "keyboard"
                            iconSize: 22
                            color: tryField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                        TextInput {
                            id: tryField
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnLayer1
                            selectionColor: Appearance.colors.colSecondaryContainer
                            selectedTextColor: Appearance.colors.colOnSecondaryContainer
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.large
                            clip: true
                            Keys.onPressed: event => {
                                if (!root.pressedCodes.includes(event.nativeScanCode)) root.pressedCodes = [...root.pressedCodes, event.nativeScanCode];
                                event.accepted = false;
                            }
                            Keys.onReleased: event => {
                                if (!event.isAutoRepeat) root.pressedCodes = root.pressedCodes.filter(code => code !== event.nativeScanCode);
                            }
                            onActiveFocusChanged: if (!activeFocus) root.pressedCodes = []
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                visible: tryField.text.length === 0
                                text: Translation.tr("Just start typing, then press Alt+Shift and type again")
                                elide: Text.ElideRight
                                color: Appearance.colors.colSubtext
                            }
                        }
                        RippleButton {
                            visible: tryField.text.length > 0
                            focusPolicy: Qt.NoFocus
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: 16
                            colBackground: "transparent"
                            onClicked: {
                                tryField.clear();
                                tryField.forceActiveFocus();
                            }
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "backspace"
                                iconSize: 18
                                color: Appearance.colors.colSubtext
                            }
                        }
                        // The layout the letters come in
                        Rectangle {
                            implicitWidth: Math.max(40, layoutBadge.implicitWidth + 18)
                            implicitHeight: 30
                            radius: 15
                            color: Appearance.colors.colPrimary
                            StyledText {
                                id: layoutBadge
                                anchors.centerIn: parent
                                text: root.shownLayout.slice(0, 3).toUpperCase()
                                font.family: Appearance.font.family.monospace
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
