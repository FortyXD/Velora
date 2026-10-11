pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    property string filter: ""

    // Repeaters get plain id lists that only change when the set of binds does, so a
    // config reload after each change doesn't rebuild (and re-animate) the whole page
    property var groupIds: []
    property var groupUids: ({})
    function refreshModels() {
        const ids = HyprlandKeybinds.groups.map(group => group.id);
        if (JSON.stringify(ids) !== JSON.stringify(root.groupIds)) root.groupIds = ids;
        let uids = {};
        for (const id of ids) uids[id] = HyprlandKeybinds.bindsInGroup(id).map(bind => HyprlandKeybinds.uid(bind));
        if (JSON.stringify(uids) !== JSON.stringify(root.groupUids)) root.groupUids = uids;
    }
    Connections {
        target: HyprlandKeybinds
        function onBindsChanged() {
            root.refreshModels();
        }
    }
    Component.onCompleted: root.refreshModels()

    function normalize(text) {
        return (text ?? "").toString().toLowerCase().replace(/ё/g, "е");
    }

    function matches(uid) {
        const bind = HyprlandKeybinds.bindMap[uid];
        if (!bind) return false;
        const terms = root.normalize(root.filter).split(" ").filter(term => term.length > 0);
        if (terms.length === 0) return true;
        const haystack = root.normalize([Translation.tr(bind.description), bind.description,
            KeyUtils.comboText(bind.mods, bind.key), KeyUtils.comboLabels(bind.mods, bind.key).join(" ")].join(" "));
        return terms.every(term => haystack.includes(term));
    }

    function groupInfo(id) {
        return HyprlandKeybinds.groups.find(group => group.id === id) ?? { id: id, name: id, icon: "keyboard" };
    }

    ColumnLayout { // Search and actions
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                border.width: filterField.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 6
                    spacing: 8
                    MaterialSymbol {
                        text: "search"
                        iconSize: 20
                        color: Appearance.colors.colSubtext
                    }
                    TextField {
                        id: filterField
                        Layout.fillWidth: true
                        background: null
                        padding: 0
                        placeholderText: Translation.tr("Find a shortcut by name or keys")
                        placeholderTextColor: Appearance.colors.colSubtext
                        color: Appearance.colors.colOnLayer2
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        onTextChanged: root.filter = text
                    }
                    RippleButton {
                        visible: filterField.text.length > 0
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        onClicked: filterField.text = ""
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 18
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            PillButton {
                iconName: "visibility"
                text: Translation.tr("Cheat sheet")
                onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "cheatsheet", "open"])
            }
            PillButton {
                visible: HyprlandKeybinds.changedCount > 0
                iconName: "restart_alt"
                text: Translation.tr("Reset all")
                onClicked: HyprlandKeybinds.resetAll()
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: HyprlandKeybinds.applying ? Translation.tr("Applying…")
                : Translation.tr("Click a shortcut's keys and press new ones. Changes apply right away and show in the cheat sheet (Super+/).")
        }
    }

    Repeater {
        model: root.groupIds
        delegate: ContentSection {
            id: groupSection
            required property string modelData
            readonly property var info: root.groupInfo(modelData)
            readonly property var uids: root.groupUids[modelData] ?? []
            readonly property bool anyMatch: root.filter.length === 0 || uids.some(uid => root.matches(uid))
            readonly property bool isCustom: modelData === "custom"

            visible: anyMatch || (isCustom && root.filter.length === 0)
            icon: info.icon
            title: Translation.tr(info.name)
            description: isCustom ? Translation.tr("Shortcuts you added. Ones defined in custom/keybinds.lua show up here too.") : ""

            Repeater {
                model: groupSection.uids
                delegate: ShortcutRow {
                    required property string modelData
                    uid: modelData
                    visible: root.matches(modelData)
                }
            }

            Loader {
                Layout.fillWidth: true
                active: groupSection.isCustom
                visible: active && root.filter.length === 0
                sourceComponent: CustomShortcutEditor {}
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

    component PillButton: RippleButton {
        id: pill
        property string iconName
        implicitHeight: 42
        implicitWidth: pillRow.implicitWidth + 28
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        contentItem: RowLayout {
            id: pillRow
            spacing: 6
            MaterialSymbol {
                text: pill.iconName
                iconSize: 18
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                text: pill.text
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }
}
