import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

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

    function setSwitchOption(grpOption) {
        let options = root.kbOptions.split(",").map(option => option.trim()).filter(option => option.length > 0 && !option.startsWith("grp:"));
        if (grpOption.length > 0) options.push(grpOption);
        HyprlandSettings.set("input:kb_options", options.join(","));
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
            ConfigSelectionArray {
                currentValue: root.switchOption
                onSelected: newValue => root.setSwitchOption(newValue)
                // Alt + Shift is handled by the keybinds (no grp: option): an XKB toggle would
                // turn Shift or Alt into a layout switch whenever both are held
                options: [
                    { displayName: "Alt + Shift", value: "" },
                    { displayName: "Ctrl + Shift", value: "grp:ctrl_shift_toggle" },
                    { displayName: "Super + Space", value: "grp:win_space_toggle" },
                    { displayName: "Caps Lock", value: "grp:caps_toggle" }
                ]
            }
        }
    }

    ContentSection {
        title: Translation.tr("Keys")
        description: Translation.tr("Change what some keys do, for every layout")

        Repeater {
            model: root.optionGroups.filter(group => root.shownGroups.includes(group.id))
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

        ConfigNavRow {
            id: rawToggle
            property bool open: false
            buttonIcon: "code"
            title: Translation.tr("Edit as text")
            description: Translation.tr("Layouts, variants and options as XKB codes")
            trailingIcon: rawToggle.open ? "expand_less" : "expand_more"
            onClicked: rawToggle.open = !rawToggle.open
        }
        ConfigTextRow {
            id: layoutsField
            visible: rawToggle.open
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
            visible: rawToggle.open
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
            visible: rawToggle.open
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

    ContentSection {
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
        HyprSwitch {
            option: "input:numlock_by_default"
            fallback: true
            buttonIcon: "dialpad"
            text: Translation.tr("Num Lock on at startup")
        }
    }

    ContentSection {
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
