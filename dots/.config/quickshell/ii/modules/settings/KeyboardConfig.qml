pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.desktop
import qs.modules.settings.keyboard

SettingsDetailPage {
    id: root
    readonly property Item popupPane: root
    onActiveFocusChanged: if (activeFocus && preview?.active && root.Window.window?.activeFocusItem === root) preview.focusTyping()
    sectionTitles: ({
        layouts: Translation.tr("Layouts"),
        shortcuts: Translation.tr("Keyboard Shortcuts"),
        typing: Translation.tr("Keys and repeat"),
        cheatsheet: Translation.tr("Cheat sheet look")
    })

    function layoutName(code) {
        return Translation.tr(root.knownLayouts[code] ?? code);
    }
    function clearShortcutFilters() {
        catalog.clearFilters();
    }

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
    readonly property var layoutBind: HyprlandKeybinds.binds.find(bind => bind.id === "keyboard.layout") ?? null
    readonly property bool defaultLayoutShortcut: !root.layoutBind || (!root.layoutBind.disabled
        && KeyUtils.comboKey(root.layoutBind.mods, root.layoutBind.key) === KeyUtils.comboKey(["Alt"], "Shift"))

    readonly property var layoutOptions: {
        const hasDevice = HyprlandXkb.layoutCodes.length > 0;
        const codes = hasDevice ? HyprlandXkb.layoutCodes : root.layoutCodes;
        const variants = hasDevice ? HyprlandXkb.variantCodes : root.variantCodes;
        return codes.map((code, i) => ({
            code, variant: variants[i] ?? "", displayName: root.layoutName(code),
            description: [code, variants[i]].filter(Boolean).join(" · "), value: i
        }));
    }

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
        if (layouts.join(",") !== root.layoutsValue || variantText !== HyprlandSettings.get("input:kb_variant", ""))
            HyprlandSettings.setMany({ "input:kb_layout": layouts.join(","), "input:kb_variant": variantText });
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

    // What Caps Lock does, as written on its key
    readonly property string capsOption: root.optionInGroup("caps")
    readonly property string capsLabel: root.switchOption === "grp:caps_toggle" ? Translation.tr("Layout")
        : ({ "caps:escape": "Esc", "caps:ctrl_modifier": "Ctrl", "caps:backspace": "⌫", "caps:none": "—" })[root.capsOption] ?? "Caps Lock"

    function setSwitchOption(grpOption) {
        if (grpOption === "") HyprlandKeybinds.reset("keyboard.layout");
        let options = root.kbOptions.split(",").map(option => option.trim()).filter(option => option.length > 0 && !option.startsWith("grp:"));
        if (grpOption.length > 0) options.push(grpOption);
        HyprlandSettings.set("input:kb_options", options.join(","));
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        KeyboardLayoutMap {
            id: layoutMap
            needed: root.pageShown && (overview.shown || catalog.shown)
            layout: HyprlandXkb.currentLayoutCode || root.layoutOptions[0]?.code || "us"
            variant: HyprlandXkb.currentLayoutCode ? HyprlandXkb.currentLayoutVariant : root.layoutOptions[0]?.variant ?? ""
        }
        SettingsBranch {
            id: overview
            page: root
            key: "overview"

            KeyboardPreview {
                id: preview
                Layout.fillWidth: true
                active: root.pageShown && overview.shown
                sourceMap: layoutMap
                layoutOptions: root.layoutOptions
                configuredIndex: root.layoutCodes.findIndex((code, i) => code === preview.layout && root.variantCodes[i] === preview.variant)
                capsLabel: root.capsLabel
                onDefaultRequested: index => {
                    const layouts = [...root.layoutCodes], variants = [...root.variantCodes];
                    layouts.unshift(layouts.splice(index, 1)[0]);
                    variants.unshift(variants.splice(index, 1)[0]);
                    root.setLayouts(layouts, variants);
                }
                onShortcutChosen: bind => {
                    catalog.showCombo(bind);
                    root.tab = catalog.key;
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 490 ? 2 : 1
                columnSpacing: 12
                rowSpacing: 8
                uniformCellWidths: true
                DesktopBranchTile {
                    branch: layoutsBranch
                    buttonIcon: "language"
                    summary: root.layoutCodes.map(code => root.layoutName(code)).join(" · ")
                    KeyCombo {
                        anchors.centerIn: parent
                        labels: [preview.layout.toUpperCase()]
                        keyColor: Appearance.colors.colPrimaryContainer
                        textColor: Appearance.colors.colOnPrimaryContainer
                        pixelSize: Appearance.font.pixelSize.small
                    }
                }
                DesktopBranchTile {
                    id: shortcutsTile
                    branch: catalog
                    buttonIcon: "keyboard_command_key"
                    accent: Appearance.colors.colTertiary
                    summary: HyprlandKeybinds.ready ? Translation.tr("%1 shortcuts").arg(HyprlandKeybinds.binds.length) : Translation.tr("Reading keybinds…")
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "keyboard_command_key"
                        iconSize: 27
                        color: shortcutsTile.accent
                        rotation: shortcutsTile.hovered || shortcutsTile.visualFocus ? -12 : 0
                        Behavior on rotation { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
                    }
                }
            }
            ContentSection {
                SettingsBranchLink {
                    branch: typingBranch
                    buttonIcon: "keyboard_double_arrow_right"
                    summary: Translation.tr("%1 ms · %2/s").arg(HyprlandSettings.get("input:repeat_delay", 250)).arg(HyprlandSettings.get("input:repeat_rate", 35))
                }
                SettingsBranchLink { branch: sheetBranch; buttonIcon: "keyboard_command_key" }
                ConfigNavRow {
                    buttonIcon: "apps"
                    title: Translation.tr("Default Apps")
                    description: Translation.tr("What Super+B, Super+E, Super+Return and other app keys open")
                    onClicked: ApplicationWindow.window?.openPage("apps")
                }
            }
        }

        SettingsBranch {
            id: layoutsBranch
            page: root
            key: "layouts"
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
                        readonly property string title: root.layoutName(modelData)
                        readonly property string searchText: [title, root.knownLayouts[modelData], modelData].join(" ")
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
                                text: layoutRow.title
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
                            maximumWidth: Math.min(220, layoutsBranch.width * 0.34)
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
                        .map(code => ({ displayName: root.layoutName(code), value: code, description: code }))
                        .sort((a, b) => a.displayName.localeCompare(b.displayName))
                    onSelected: value => root.setLayouts([...root.layoutCodes, value], [...root.variantCodes, ""])
                }
                ContentSubsection {
                    enabled: HyprlandSettings.ready
                    title: Translation.tr("Switch layouts with")
                    description: root.switchOption === "" ? (root.defaultLayoutShortcut
                        ? Translation.tr("Tap Alt+Shift. Shortcuts that hold Shift and Alt together still work.")
                        : root.layoutBind?.disabled ? Translation.tr("Turned off")
                        : Translation.tr("Current shortcut: %1").arg(KeyUtils.comboText(root.layoutBind.mods, root.layoutBind.key)))
                        : root.switchOption === "grp:alt_shift_toggle" ? Translation.tr("This XKB toggle blocks every shortcut with both Shift and Alt. Pick the first Alt + Shift instead.")
                        : ""
                    ConfigSelectionArray {
                        currentValue: root.switchOption === "" && !root.defaultLayoutShortcut ? null : root.switchOption
                        options: [
                            { displayName: "Alt + Shift", value: "" },
                            { displayName: "Ctrl + Shift", value: "grp:ctrl_shift_toggle" },
                            { displayName: "Super + Space", value: "grp:win_space_toggle" },
                            { displayName: "Caps Lock", value: "grp:caps_toggle" }
                        ]
                        onSelected: value => root.setSwitchOption(value)
                    }
                }
                ConfigExpander {
                    title: Translation.tr("Layout codes and variants")
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
                }
            }
        }

        SettingsBranch {
            id: typingBranch
            page: root
            key: "typing"
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
                icon: "keyboard_capslock"
                title: Translation.tr("Keys")
                ConfigComboRow {
                    text: Translation.tr("Caps Lock key")
                    description: root.switchOption === "grp:caps_toggle" ? Translation.tr("Caps Lock is used to switch layouts.") : ""
                    icon: "keyboard_capslock"
                    enabled: root.switchOption !== "grp:caps_toggle" && HyprlandSettings.ready
                    currentValue: root.capsOption
                    options: [
                        { displayName: Translation.tr("Caps Lock"), value: "" },
                        { displayName: Translation.tr("Escape"), value: "caps:escape" },
                        { displayName: Translation.tr("Ctrl"), value: "caps:ctrl_modifier" },
                        { displayName: Translation.tr("Backspace"), value: "caps:backspace" },
                        { displayName: Translation.tr("Nothing"), value: "caps:none" }
                    ]
                    onSelected: value => root.setGroupOption("caps", value)
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
        }

        ShortcutsConfig {
            id: catalog
            sourceMap: layoutMap
            capsLabel: root.capsLabel
            page: root
        }

        SettingsBranch {
            id: sheetBranch
            page: root
            key: "cheatsheet"
            readonly property var examples: {
                const binds = HyprlandKeybinds.binds.filter(bind => !bind.disabled && !bind.note);
                const samples = [binds.find(bind => bind.id === "shell.cheatsheet") ?? binds[0],
                    binds.find(bind => /^F\d+$/.test(KeyUtils.resolveKeycode(bind.key))),
                    binds.find(bind => KeyUtils.mouseLabels[bind.key])];
                return samples.filter((bind, i) => bind && samples.indexOf(bind) === i);
            }
            header: examples.length ? previewHeader : null
            readonly property Component previewHeader: ContentSection {
                objectName: "cheatSheetPreview"
                title: Translation.tr("Cheat sheet preview")
                icon: "visibility"
                Repeater {
                    model: sheetBranch.examples
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        Layout.topMargin: 5
                        Layout.bottomMargin: 5
                        spacing: 12
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr(parent.modelData.description)
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            font.pixelSize: Config.options.cheatsheet.fontSize.comment
                        }
                        KeyCombo { mods: parent.modelData.mods; key: parent.modelData.key }
                    }
                }
            }

            ContentSection {
                icon: "keyboard"
                title: Translation.tr("Cheat sheet look")
                description: Translation.tr("How keys are drawn in the cheat sheet and here")

                ConfigComboRow {
                    icon: "keyboard_command_key"
                    text: Translation.tr("Super key symbol")
                    currentValue: Config.options.cheatsheet.superKey
                    onSelected: value => {
                        Config.options.cheatsheet.superKey = value;
                    }
                    searchable: false
                    dropdown.displayFontFamily: Appearance.font.family.iconNerd
                    // Use a nerdfont to see the icons
                    options: [{ displayName: "Super", value: "" }].concat([
                        "󰖳", "", "󰨡", "", "󰌽", "󰣇", "", "", "",
                        "", "", "󱄛", "", "", "⌘", "󰀲", "󰟍", ""
                    ].map(icon => ({
                        displayName: icon,
                        value: icon,
                        fontFamily: Appearance.font.family.iconNerd
                    })))
                }

                ConfigSwitch {
                    buttonIcon: "keyboard_option_key"
                    text: Translation.tr("Use symbols for modifier keys")
                    description: Translation.tr("e.g. ⌃ for Ctrl, ⌥ for Alt, ⇧ for Shift, etc")
                    checked: Config.options.cheatsheet.useModifierSymbols
                    onCheckedChanged: {
                        Config.options.cheatsheet.useModifierSymbols = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "󱊶"
                    text: Translation.tr("Use symbols for function keys")
                    description: Translation.tr("e.g. 󱊫 for F1, 󱊶  for F12")
                    checked: Config.options.cheatsheet.useFnSymbol
                    onCheckedChanged: {
                        Config.options.cheatsheet.useFnSymbol = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "󰍽"
                    text: Translation.tr("Use symbols for mouse")
                    description: Translation.tr("Mouse buttons and scrolling are drawn as icons instead of LMB, RMB, Scroll")
                    checked: Config.options.cheatsheet.useMouseSymbol
                    onCheckedChanged: {
                        Config.options.cheatsheet.useMouseSymbol = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "add"
                    text: Translation.tr("Show + between keys")
                    checked: Config.options.cheatsheet.splitButtons
                    onCheckedChanged: {
                        Config.options.cheatsheet.splitButtons = checked;
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSpinBox {
                        icon: "format_size"
                        text: Translation.tr("Key size")
                        value: Config.options.cheatsheet.fontSize.key
                        from: 8
                        to: 30
                        stepSize: 1
                        onValueChanged: {
                            Config.options.cheatsheet.fontSize.key = value;
                        }
                    }
                    ConfigSpinBox {
                        icon: "text_fields"
                        text: Translation.tr("Description size")
                        value: Config.options.cheatsheet.fontSize.comment
                        from: 8
                        to: 30
                        stepSize: 1
                        onValueChanged: {
                            Config.options.cheatsheet.fontSize.comment = value;
                        }
                    }
                }
            }
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
