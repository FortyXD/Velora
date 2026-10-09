import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    // Layout codes and names known to XKB, for checking what's typed
    property var knownLayouts: ({})
    FileView {
        path: "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            const lines = text().split("\n");
            let inLayouts = false;
            let layouts = {};
            for (const line of lines) {
                if (line.startsWith("!")) {
                    inLayouts = line.trim() === "! layout";
                    continue;
                }
                if (!inLayouts) continue;
                const match = line.match(/^\s+(\S+)\s+(.+)$/);
                if (match) layouts[match[1]] = match[2].trim();
            }
            root.knownLayouts = layouts;
        }
    }

    readonly property string layoutsValue: HyprlandSettings.get("input:kb_layout", "us")
    readonly property list<string> layoutCodes: root.layoutsValue.split(",").map(code => code.trim()).filter(code => code.length > 0)
    readonly property string kbOptions: HyprlandSettings.get("input:kb_options", "")
    readonly property string switchOption: root.kbOptions.split(",").find(option => option.startsWith("grp:")) ?? ""

    function invalidLayouts(text) {
        if (Object.keys(root.knownLayouts).length === 0) return [];
        return text.split(",").map(code => code.trim()).filter(code => code.length > 0 && root.knownLayouts[code] === undefined);
    }

    function setSwitchOption(grpOption) {
        let options = root.kbOptions.split(",").map(option => option.trim()).filter(option => option.length > 0 && !option.startsWith("grp:"));
        if (grpOption.length > 0) options.push(grpOption);
        HyprlandSettings.set("input:kb_options", options.join(","));
    }

    ContentSection {
        title: Translation.tr("Layouts")
        description: Translation.tr("Use XKB codes separated by commas, for example us,ru. The first one is used by default.")

        Flow { // Current layouts
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 6
            Repeater {
                model: root.layoutCodes
                delegate: Rectangle {
                    id: layoutChip
                    required property string modelData
                    required property int index
                    implicitHeight: 34
                    implicitWidth: chipRow.implicitWidth + 24
                    radius: Appearance.rounding.full
                    color: index === 0 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 8
                        StyledText {
                            text: layoutChip.modelData.toUpperCase()
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: layoutChip.index === 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            text: root.knownLayouts[layoutChip.modelData] ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: layoutChip.index === 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
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
            inlineFieldWidth: 200
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
            description: Translation.tr("Optional, one per layout, e.g. ,phonetic")
            inline: true
            inlineFieldWidth: 200
            monospace: true
            wrapMode: TextEdit.NoWrap
            value: HyprlandSettings.get("input:kb_variant", "")
            onEditingFinished: {
                if (value.trim() !== HyprlandSettings.get("input:kb_variant", "")) HyprlandSettings.set("input:kb_variant", value.trim());
            }
        }
        ContentSubsection {
            enabled: HyprlandSettings.ready
            title: Translation.tr("Switch layouts with")
            ConfigSelectionArray {
                currentValue: root.switchOption
                onSelected: newValue => root.setSwitchOption(newValue)
                options: [
                    { displayName: "Alt + Shift", value: "grp:alt_shift_toggle" },
                    { displayName: "Ctrl + Shift", value: "grp:ctrl_shift_toggle" },
                    { displayName: "Super + Space", value: "grp:win_space_toggle" },
                    { displayName: "Caps Lock", value: "grp:caps_toggle" },
                    { displayName: Translation.tr("None"), icon: "block", value: "" }
                ]
            }
        }
        ConfigTextRow {
            enabled: HyprlandSettings.ready
            icon: "settings_applications"
            label: Translation.tr("XKB options")
            description: Translation.tr("Advanced, e.g. caps:escape. Press Enter to apply")
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
        icon: "keyboard"
        title: Translation.tr("Shortcut cheat sheet")
        description: Translation.tr("Opens with Super+/ and lists every keybind. These options change how keys are drawn in it.")

        ContentSubsection {
            title: Translation.tr("Super key symbol")
            description: Translation.tr("You can also manually edit cheatsheet.superKey")
            ConfigSelectionArray {
                currentValue: Config.options.cheatsheet.superKey
                onSelected: newValue => {
                    Config.options.cheatsheet.superKey = newValue;
                }
                // Use a nerdfont to see the icons
                options: ([
                  "󰖳", "", "󰨡", "", "󰌽", "󰣇", "", "", "", 
                  "", "", "󱄛", "", "", "⌘", "󰀲", "󰟍", ""
                ]).map(icon => { return {
                  displayName: icon,
                  value: icon
                  }
                })
            }
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
            description: Translation.tr("Replace 󱕐   for \"Scroll ↓\", 󱕑   \"Scroll ↑\", L󰍽   \"LMB\", R󰍽   \"RMB\", 󱕒   \"Scroll ↑/↓\" and ⇞/⇟ for \"Page_↑/↓\"")
            checked: Config.options.cheatsheet.useMouseSymbol
            onCheckedChanged: {
                Config.options.cheatsheet.useMouseSymbol = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "highlight_keyboard_focus"
            text: Translation.tr("Split buttons")
            description: Translation.tr("Display modifiers and keys in multiple keycap (e.g., \"Ctrl + A\" instead of \"Ctrl A\" or \"⌃ + A\" instead of \"⌃ A\")")
            checked: Config.options.cheatsheet.splitButtons
            onCheckedChanged: {
                Config.options.cheatsheet.splitButtons = checked;
            }
        }
        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "format_size"
                text: Translation.tr("Keybind font size")
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
                text: Translation.tr("Description font size")
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
