import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview
import qs.modules.settings.keyboard

ContentPage {
    id: root

    // Layouts, variants and options known to XKB
    property var knownLayouts: ({})   // code -> name
    property var knownVariants: ({})  // layout -> [{ code, name }]
    property var optionGroups: []     // [{ id, name, options: [{ code, name }] }]
    FileView {
        path: "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            let section = "";
            let layouts = {};
            let variants = {};
            let groups = [];
            for (const line of text().split("\n")) {
                if (line.startsWith("!")) {
                    section = line.slice(1).trim();
                    continue;
                }
                const match = line.match(/^\s+(\S+)\s+(.+)$/);
                if (!match) continue;
                const code = match[1];
                const name = match[2].trim();
                if (section === "layout") {
                    layouts[code] = name;
                } else if (section === "variant") {
                    const parts = name.match(/^(\S+):\s*(.+)$/);
                    if (!parts) continue;
                    (variants[parts[1]] = variants[parts[1]] ?? []).push({ code: code, name: parts[2] });
                } else if (section === "option") {
                    if (!code.includes(":")) groups.push({ id: code, name: name, options: [] });
                    else if (groups.length > 0) groups[groups.length - 1].options.push({ code: code, name: name });
                }
            }
            root.knownLayouts = layouts;
            root.knownVariants = variants;
            root.optionGroups = groups;
        }
    }

    // Option groups offered as dropdowns; the rest stays reachable through "Edit as text"
    readonly property var shownGroups: ["caps", "ctrl", "altwin", "compose", "lv3", "nbsp"]

    readonly property string layoutsValue: HyprlandSettings.get("input:kb_layout", "us")
    readonly property list<string> layoutCodes: root.layoutsValue.split(",").map(code => code.trim()).filter(code => code.length > 0)
    readonly property string kbOptions: HyprlandSettings.get("input:kb_options", "")
    readonly property string switchOption: root.kbOptions.split(",").find(option => option.startsWith("grp:")) ?? ""

    function invalidLayouts(text) {
        if (Object.keys(root.knownLayouts).length === 0) return [];
        return text.split(",").map(code => code.trim()).filter(code => code.length > 0 && root.knownLayouts[code] === undefined);
    }

    readonly property list<string> variantCodes: {
        const variants = HyprlandSettings.get("input:kb_variant", "").split(",").map(code => code.trim());
        return root.layoutCodes.map((_, index) => variants[index] ?? "");
    }

    // Layouts and variants are lists that must stay in step, so they are always written together
    function setLayouts(layouts, variants) {
        if (layouts.length === 0) return;
        const variantText = variants.some(code => code.length > 0) ? variants.join(",") : "";
        if (layouts.join(",") !== root.layoutsValue) HyprlandSettings.set("input:kb_layout", layouts.join(","));
        if (variantText !== HyprlandSettings.get("input:kb_variant", "")) HyprlandSettings.set("input:kb_variant", variantText);
    }
    function moveLayout(index, step) {
        let layouts = [...root.layoutCodes];
        let variants = [...root.variantCodes];
        const target = index + step;
        if (target < 0 || target >= layouts.length) return;
        [layouts[index], layouts[target]] = [layouts[target], layouts[index]];
        [variants[index], variants[target]] = [variants[target], variants[index]];
        root.setLayouts(layouts, variants);
    }
    function removeLayout(index) {
        root.setLayouts(root.layoutCodes.filter((_, i) => i !== index), root.variantCodes.filter((_, i) => i !== index));
    }
    function setVariant(index, variant) {
        let variants = [...root.variantCodes];
        variants[index] = variant;
        root.setLayouts([...root.layoutCodes], variants);
    }

    function optionInGroup(group) {
        return root.kbOptions.split(",").map(option => option.trim()).find(option => option.startsWith(`${group}:`)) ?? "";
    }
    function setGroupOption(group, option) {
        let options = root.kbOptions.split(",").map(item => item.trim()).filter(item => item.length > 0 && !item.startsWith(`${group}:`));
        if (option.length > 0) options.push(option);
        HyprlandSettings.set("input:kb_options", options.join(","));
    }

    // The drawn keyboard shows one of your layouts (click its chip); keys typed in the field below it light up
    property int previewIndex: 0
    readonly property string previewLayout: root.layoutCodes[Math.min(root.previewIndex, root.layoutCodes.length - 1)] ?? "us"
    readonly property string previewVariant: root.variantCodes[Math.min(root.previewIndex, root.variantCodes.length - 1)] ?? ""
    property var previewKeys: ({})
    property var pressedCodes: []
    property string pickedKey: ""
    readonly property string shownKey: layoutKeyboard.hoveredKey || root.pickedKey
    readonly property var shownLevels: (root.previewKeys[root.shownKey]?.levels ?? []).map(level => level ?? "")
    onPreviewLayoutChanged: keysProc.load()
    onPreviewVariantChanged: keysProc.load()
    Process {
        id: keysProc
        function load() {
            keysProc.running = false;
            keysProc.command = [Quickshell.shellPath("scripts/helper"), "layout-keys", root.previewLayout, root.previewVariant];
            keysProc.running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.previewKeys = JSON.parse(text).keys ?? {};
                } catch (e) {
                    root.previewKeys = {};
                }
            }
        }
        Component.onCompleted: keysProc.load()
    }

    // What Caps Lock does, as written on its key
    readonly property string capsOption: root.optionInGroup("caps")
    readonly property string capsLabel: root.switchOption === "grp:caps_toggle" ? Translation.tr("Layout")
        : ({ "caps:escape": "Esc", "caps:ctrl_modifier": "Ctrl", "caps:backspace": "⌫", "caps:none": "—" })[root.capsOption] ?? "Caps Lock"

    function setSwitchOption(grpOption) {
        let options = root.kbOptions.split(",").map(option => option.trim()).filter(option => option.length > 0 && !option.startsWith("grp:"));
        if (grpOption.length > 0) options.push(grpOption);
        HyprlandSettings.set("input:kb_options", options.join(","));
    }

    // A keycap drawn in a tile
    component Keycap: Rectangle {
        property string label
        property color ink: Appearance.colors.colOnLayer2
        implicitWidth: Math.max(26, keycapText.implicitWidth + 12)
        implicitHeight: 24
        radius: 6
        color: "transparent"
        border.width: 1.5
        border.color: ink
        StyledText {
            id: keycapText
            anchors.centerIn: parent
            text: parent.label
            font.pixelSize: parent.label.length === 1 ? 15 : 11
            color: parent.ink
        }
    }

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Your keyboard")
        card: false
        searchText: `${title} ${Translation.tr("Try typing here")}`

        Flow { // Your layouts: click one to see it on the keyboard
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.layoutCodes
                delegate: RippleButton {
                    id: chip
                    required property string modelData
                    required property int index
                    readonly property bool shown: chip.index === Math.min(root.previewIndex, root.layoutCodes.length - 1)
                    implicitHeight: 36
                    leftPadding: 10
                    rightPadding: 14
                    buttonRadius: Appearance.rounding.full
                    colBackground: chip.shown ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: chip.shown ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                    onClicked: root.previewIndex = chip.index
                    contentItem: Row {
                        spacing: 8
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 22
                            radius: 11
                            color: chip.shown ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                            StyledText {
                                anchors.centerIn: parent
                                text: chip.modelData.toUpperCase()
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: chip.shown ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                            }
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.knownLayouts[chip.modelData] ?? chip.modelData
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: chip.shown ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }

        KeyboardVisual {
            id: layoutKeyboard
            Layout.fillWidth: true
            interactive: true
            keys: root.previewKeys
            pressedCodes: root.pressedCodes
            capsLabel: root.capsLabel
            selectedKey: root.pickedKey
            onKeyClicked: name => root.pickedKey = root.pickedKey === name ? "" : name
        }

        // What the key under the pointer types: alone, with Shift and with AltGr
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            readonly property bool settingsSearchable: false
            StyledText {
                visible: root.shownLevels.filter(level => level.length > 0).length === 0
                Layout.fillWidth: true
                text: Translation.tr("Point at a key to see everything it types in this layout, with Shift and AltGr too")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            Repeater {
                model: root.shownLevels.length > 0 ? [
                    { "name": Translation.tr("Alone"), "level": 0 },
                    { "name": "Shift", "level": 1 },
                    { "name": "AltGr", "level": 2 },
                    { "name": "AltGr + Shift", "level": 3 },
                ].filter(entry => (root.shownLevels[entry.level] ?? "").length > 0) : []
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: levelRow.implicitWidth + 20
                    implicitHeight: 40
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    Row {
                        id: levelRow
                        anchors.centerIn: parent
                        spacing: 8
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.shownLevels[parent.parent.modelData.level]
                            font.pixelSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.parent.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
            Item {
                visible: root.shownLevels.length > 0
                Layout.fillWidth: true
            }
            DialogButton { // The shown layout becomes the one used by default
                visible: root.previewIndex > 0 && root.previewIndex < root.layoutCodes.length
                enabled: HyprlandSettings.ready
                buttonText: Translation.tr("Use %1 by default").arg(root.previewLayout.toUpperCase())
                onClicked: {
                    const index = root.previewIndex;
                    let layouts = [...root.layoutCodes];
                    let variants = [...root.variantCodes];
                    layouts.unshift(layouts.splice(index, 1)[0]);
                    variants.unshift(variants.splice(index, 1)[0]);
                    root.setLayouts(layouts, variants);
                    root.previewIndex = 0;
                }
            }
        }

        TextField { // Type here: the keys light up above
            id: tryField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Try typing here: the keys light up above")
            placeholderTextColor: Appearance.colors.colSubtext
            color: Appearance.colors.colOnLayer2
            leftPadding: 16
            topPadding: 12
            bottomPadding: 12
            font.pixelSize: Appearance.font.pixelSize.normal
            background: Rectangle {
                implicitHeight: 46
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                border.width: tryField.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
            }
            Keys.onPressed: event => {
                if (!root.pressedCodes.includes(event.nativeScanCode)) root.pressedCodes = [...root.pressedCodes, event.nativeScanCode];
            }
            Keys.onReleased: event => {
                if (event.isAutoRepeat) return;
                root.pressedCodes = root.pressedCodes.filter(code => code !== event.nativeScanCode);
            }
            onActiveFocusChanged: if (!activeFocus) root.pressedCodes = []
        }
    }

    ContentSection {
        title: Translation.tr("Layouts")
        description: Translation.tr("The first one is used by default. The switch keys go through them in this order.")

        Repeater { // Current layouts, in switching order
            model: root.layoutCodes
            delegate: RowLayout {
                id: layoutRow
                required property string modelData
                required property int index
                readonly property bool settingsSearchable: true
                property string searchText: `${root.knownLayouts[layoutRow.modelData] ?? ""} ${layoutRow.modelData}`
                readonly property var variants: root.knownVariants[layoutRow.modelData] ?? []
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 6
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                spacing: 10

                Rectangle {
                    implicitWidth: 40
                    implicitHeight: 28
                    radius: Appearance.rounding.full
                    color: layoutRow.index === 0 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                    StyledText {
                        anchors.centerIn: parent
                        text: layoutRow.modelData.toUpperCase()
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: layoutRow.index === 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        Layout.fillWidth: true
                        text: root.knownLayouts[layoutRow.modelData] ?? layoutRow.modelData
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: layoutRow.index === 0
                        text: Translation.tr("Used by default")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                ChoiceDropdown {
                    visible: layoutRow.variants.length > 0
                    enabled: HyprlandSettings.ready
                    maximumWidth: 220
                    currentValue: root.variantCodes[layoutRow.index] ?? ""
                    options: [
                        { displayName: Translation.tr("Standard"), value: "" },
                        ...layoutRow.variants.map(variant => ({ displayName: variant.name, value: variant.code, description: variant.code }))
                    ]
                    onSelected: value => root.setVariant(layoutRow.index, value)
                }
                LayoutIconButton {
                    symbol: "arrow_upward"
                    tooltip: Translation.tr("Move up")
                    enabled: layoutRow.index > 0 && HyprlandSettings.ready
                    onClicked: root.moveLayout(layoutRow.index, -1)
                }
                LayoutIconButton {
                    symbol: "close"
                    tooltip: Translation.tr("Remove")
                    enabled: root.layoutCodes.length > 1 && HyprlandSettings.ready
                    onClicked: root.removeLayout(layoutRow.index)
                }
            }
        }
        ConfigComboRow {
            enabled: HyprlandSettings.ready
            icon: "add"
            text: Translation.tr("Add a layout")
            placeholderText: Translation.tr("Choose…")
            searchable: true
            maximumWidth: 260
            options: Object.keys(root.knownLayouts)
                .filter(code => !root.layoutCodes.includes(code))
                .map(code => ({ displayName: root.knownLayouts[code], value: code, description: code }))
                .sort((a, b) => a.displayName.localeCompare(b.displayName))
            onSelected: value => root.setLayouts([...root.layoutCodes, value], [...root.variantCodes, ""])
        }
        ContentSubsection {
            enabled: HyprlandSettings.ready
            title: Translation.tr("Switch layouts with")
            description: root.switchOption === "" ? Translation.tr("Tap Alt+Shift. Shortcuts that hold Shift and Alt together still work.")
                : root.switchOption === "grp:alt_shift_toggle" ? Translation.tr("This XKB toggle blocks every shortcut with both Shift and Alt. Pick the first Alt + Shift instead.")
                : ""
            Flow {
                Layout.fillWidth: true
                spacing: 4
                // Alt + Shift is handled by the keybinds (no grp: option): an XKB toggle would
                // turn Shift or Alt into a layout switch whenever both are held
                Repeater {
                    model: [
                        { "keys": ["Alt", "Shift"], "value": "" },
                        { "keys": ["Ctrl", "Shift"], "value": "grp:ctrl_shift_toggle" },
                        { "keys": ["Super", "Space"], "value": "grp:win_space_toggle" },
                        { "keys": ["Caps Lock"], "value": "grp:caps_toggle" },
                    ]
                    delegate: SchemeTile {
                        id: switchTile
                        required property var modelData
                        label: switchTile.modelData.keys.join(" + ")
                        frameWidth: 130
                        frameHeight: 52
                        selected: root.switchOption === switchTile.modelData.value
                        onClicked: root.setSwitchOption(switchTile.modelData.value)
                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            Repeater {
                                model: switchTile.modelData.keys
                                delegate: Row {
                                    required property string modelData
                                    required property int index
                                    spacing: 4
                                    StyledText {
                                        visible: parent.index > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "+"
                                        color: switchTile.faint
                                    }
                                    Keycap { label: parent.modelData; ink: switchTile.ink }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "keyboard_capslock"
        title: Translation.tr("Keys")
        description: Translation.tr("Change what some keys do, for every layout")

        ContentSubsection {
            title: Translation.tr("Caps Lock key")
            description: root.switchOption === "grp:caps_toggle" ? Translation.tr("Caps Lock switches layouts now (see above), so this doesn't apply.") : ""
            searchText: `${title} Escape Ctrl Backspace`
            Flow {
                Layout.fillWidth: true
                spacing: 4
                enabled: root.switchOption !== "grp:caps_toggle" && HyprlandSettings.ready
                opacity: enabled ? 1 : 0.5
                Repeater {
                    model: [
                        { "key": "Caps Lock", "name": Translation.tr("Caps Lock"), "value": "" },
                        { "key": "Esc", "name": Translation.tr("Escape"), "value": "caps:escape" },
                        { "key": "Ctrl", "name": Translation.tr("Ctrl"), "value": "caps:ctrl_modifier" },
                        { "key": "⌫", "name": Translation.tr("Backspace"), "value": "caps:backspace" },
                        { "key": "—", "name": Translation.tr("Nothing"), "value": "caps:none" },
                    ]
                    delegate: SchemeTile {
                        id: capsTile
                        required property var modelData
                        label: capsTile.modelData.name
                        frameWidth: 96
                        frameHeight: 52
                        selected: root.capsOption === capsTile.modelData.value
                        onClicked: root.setGroupOption("caps", capsTile.modelData.value)
                        Keycap { anchors.centerIn: parent; label: capsTile.modelData.key; ink: capsTile.ink }
                    }
                }
            }
        }

        ConfigExpander {
            title: Translation.tr("More keys")
            description: Translation.tr("Ctrl, Alt and Super, Compose, a third level and the non-breaking space; or XKB codes as text")

        Repeater {
            model: root.optionGroups.filter(group => group.id !== "caps" && root.shownGroups.includes(group.id))
                .sort((a, b) => root.shownGroups.indexOf(a.id) - root.shownGroups.indexOf(b.id))
            delegate: ConfigComboRow {
                required property var modelData
                enabled: HyprlandSettings.ready
                icon: ({ caps: "keyboard_capslock", ctrl: "keyboard_control_key", altwin: "keyboard_option_key",
                         compose: "edit_note", lv3: "keyboard_alt", nbsp: "space_bar" })[modelData.id] ?? "keyboard"
                text: modelData.name
                maximumWidth: 300
                currentValue: root.optionInGroup(modelData.id)
                options: [
                    { displayName: Translation.tr("Default"), value: "" },
                    ...modelData.options.map(option => ({ displayName: option.name, value: option.code, description: option.code }))
                ]
                onSelected: value => root.setGroupOption(modelData.id, value)
            }
        }

        ConfigTextRow {
            id: layoutsField
            readonly property var invalid: root.invalidLayouts(value)
            enabled: HyprlandSettings.ready
            icon: "language"
            label: Translation.tr("Layout codes")
            description: invalid.length > 0 ? Translation.tr("Unknown layout: %1").arg(invalid.join(", ")) : Translation.tr("Press Enter to apply")
            inline: true
            inlineFieldWidth: 240
            monospace: true
            wrapMode: TextEdit.NoWrap
            placeholderText: "us,ru"
            value: root.layoutsValue
            onEditingFinished: {
                const text = value.split(",").map(code => code.trim()).filter(code => code.length > 0).join(",");
                if (text.length > 0 && invalid.length === 0 && text !== root.layoutsValue) HyprlandSettings.set("input:kb_layout", text);
            }
        }
        ConfigTextRow {
            enabled: HyprlandSettings.ready
            icon: "tune"
            label: Translation.tr("Variants")
            description: Translation.tr("One per layout, e.g. ,phonetic")
            inline: true
            inlineFieldWidth: 240
            monospace: true
            wrapMode: TextEdit.NoWrap
            value: HyprlandSettings.get("input:kb_variant", "")
            onEditingFinished: {
                if (value.trim() !== HyprlandSettings.get("input:kb_variant", "")) HyprlandSettings.set("input:kb_variant", value.trim());
            }
        }
        ConfigTextRow {
            enabled: HyprlandSettings.ready
            icon: "settings_applications"
            label: Translation.tr("XKB options")
            description: Translation.tr("e.g. caps:escape. Press Enter to apply")
            inline: true
            inlineFieldWidth: 240
            monospace: true
            wrapMode: TextEdit.NoWrap
            value: root.kbOptions
            onEditingFinished: {
                if (value.trim() !== root.kbOptions) HyprlandSettings.set("input:kb_options", value.trim());
            }
        }
        }
    }

    ContentSection {
        icon: "keyboard_double_arrow_right"
        title: Translation.tr("Typing")

        HyprSlider {
            option: "input:repeat_delay"
            fallback: 250
            integer: true
            from: 100
            to: 1000
            buttonIcon: "hourglass_top"
            text: Translation.tr("Delay until repeat (ms)")
        }
        HyprSlider {
            option: "input:repeat_rate"
            fallback: 35
            integer: true
            from: 5
            to: 100
            buttonIcon: "keyboard_double_arrow_right"
            text: Translation.tr("Key repeat rate (per second)")
        }
        TextField {
            id: repeatField
            readonly property bool settingsSearchable: true
            readonly property string searchText: placeholderText
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            placeholderText: Translation.tr("Hold a key here to try the delay and the speed")
            placeholderTextColor: Appearance.colors.colSubtext
            color: Appearance.colors.colOnLayer2
            leftPadding: 14
            topPadding: 10
            bottomPadding: 10
            font.pixelSize: Appearance.font.pixelSize.small
            background: Rectangle {
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                border.width: repeatField.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
            }
        }
        HyprSwitch {
            option: "input:numlock_by_default"
            fallback: true
            buttonIcon: "dialpad"
            text: Translation.tr("Num Lock on at startup")
        }
    }

    ContentSection {
        icon: "keyboard_command_key"
        title: Translation.tr("Shortcuts")

        ConfigNavRow {
            buttonIcon: "keyboard_command_key"
            title: Translation.tr("Keyboard Shortcuts")
            description: Translation.tr("See, change and add shortcuts, and style the cheat sheet")
            onClicked: ApplicationWindow.window?.openPage("shortcuts")
        }
        ConfigNavRow {
            buttonIcon: "apps"
            title: Translation.tr("Default Apps")
            description: Translation.tr("What Super+B, Super+E, Super+Return and other app keys open")
            onClicked: ApplicationWindow.window?.openPage("apps")
        }
    }

    component LayoutIconButton: RippleButton {
        id: iconButton
        property string symbol
        property string tooltip
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        opacity: enabled ? 1 : 0.35
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: iconButton.symbol
            iconSize: 20
            color: Appearance.colors.colSubtext
        }
        StyledToolTip {
            text: iconButton.tooltip
        }
    }
}
