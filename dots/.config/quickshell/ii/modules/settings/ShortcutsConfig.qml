pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.keyboard

ContentPage {
    id: root

    property string filter: ""

    // ---- The keyboard: which keys do something together with the modifiers picked on it ----
    property var shortcutMods: ["Super"]
    property string pickedKey: ""
    property var layoutKeys: ({})
    Process { // Key labels of the US layout, which Hyprland matches shortcut keys against
        running: true
        command: ["python3", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/keyboard/layout_keys.py`, "us"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.layoutKeys = JSON.parse(text).keys ?? {};
                } catch (e) {}
            }
        }
    }
    readonly property var keyNameFor: {
        let map = {};
        "QWERTYUIOP".split("").forEach((c, i) => map[c] = `AD${String(i + 1).padStart(2, "0")}`);
        "ASDFGHJKL".split("").forEach((c, i) => map[c] = `AC${String(i + 1).padStart(2, "0")}`);
        "ZXCVBNM".split("").forEach((c, i) => map[c] = `AB${String(i + 1).padStart(2, "0")}`);
        "1234567890".split("").forEach((c, i) => map[c] = `AE${String(i + 1).padStart(2, "0")}`);
        for (let i = 1; i <= 12; i++) map[`F${i}`] = `FK${String(i).padStart(2, "0")}`;
        Object.assign(map, {
            "Minus": "AE11", "Equal": "AE12", "Comma": "AB08", "Period": "AB09", "Slash": "AB10", "Grave": "TLDE",
            "BracketLeft": "AD11", "BracketRight": "AD12", "Backslash": "BKSL", "Semicolon": "AC10", "Apostrophe": "AC11",
            "Tab": "TAB", "Return": "RTRN", "Space": "SPCE", "Escape": "ESC", "Delete": "DELE", "Print": "PRSC",
            "BackSpace": "BKSP", "Super": "LWIN",
        });
        return map;
    }
    readonly property var modKeys: ({ "Super": ["LWIN"], "Shift": ["LFSH", "RTSH"], "Ctrl": ["LCTL", "RCTL"], "Alt": ["LALT"] })
    function keysFor(key) {
        if (key === "1-0") return ["AE01", "AE02", "AE03", "AE04", "AE05", "AE06", "AE07", "AE08", "AE09", "AE10"];
        const name = root.keyNameFor[(key ?? "").length === 1 ? key.toUpperCase() : key];
        return name ? [name] : [];
    }
    function sameMods(a, b) {
        return [...(a ?? [])].sort().join("+") === [...(b ?? [])].sort().join("+");
    }
    function toggleMod(mod) {
        root.shortcutMods = root.shortcutMods.includes(mod) ? root.shortcutMods.filter(m => m !== mod) : [...root.shortcutMods, mod];
        root.pickedKey = "";
    }
    readonly property var modBinds: HyprlandKeybinds.binds.filter(bind => !bind.disabled && root.sameMods(bind.mods, root.shortcutMods))
    readonly property var boundKeyColors: {
        let colors = {};
        for (const bind of root.modBinds) for (const key of root.keysFor(bind.key)) colors[key] = Appearance.colors.colSecondaryContainer;
        return colors;
    }
    readonly property var offKeyboardBinds: root.modBinds.filter(bind => root.keysFor(bind.key).length === 0)
    readonly property string shownKey: shortcutKeyboard.hoveredKey || root.pickedKey
    readonly property var shownBinds: root.modBinds.filter(bind => root.keysFor(bind.key).includes(root.shownKey))

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

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("On the keyboard")
        description: Translation.tr("Pick modifier keys, then point at a key to see what it does. Colored keys have a shortcut; clicking one finds it in the list below.")

        Flow { // Modifiers to look at
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: ["Super", "Shift", "Ctrl", "Alt"]
                delegate: RippleButton {
                    id: modChip
                    required property string modelData
                    readonly property bool on: root.shortcutMods.includes(modChip.modelData)
                    implicitHeight: 34
                    leftPadding: 14
                    rightPadding: 14
                    buttonRadius: Appearance.rounding.full
                    colBackground: modChip.on ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: modChip.on ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                    onClicked: root.toggleMod(modChip.modelData)
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        text: KeyUtils.modLabel(modChip.modelData)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: modChip.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }
            StyledText {
                anchors.verticalCenter: undefined
                height: 34
                verticalAlignment: Text.AlignVCenter
                leftPadding: 8
                text: Translation.tr("%1 shortcuts").arg(root.modBinds.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        KeyboardVisual {
            id: shortcutKeyboard
            Layout.fillWidth: true
            showFunctionRow: true
            interactive: true
            keys: root.layoutKeys
            keyColors: root.boundKeyColors
            activeKeys: root.shortcutMods.reduce((keys, mod) => keys.concat(root.modKeys[mod] ?? []), [])
            selectedKey: root.pickedKey
            onKeyClicked: name => {
                const mod = Object.keys(root.modKeys).find(m => root.modKeys[m].includes(name));
                if (mod) {
                    root.toggleMod(mod);
                    return;
                }
                root.pickedKey = root.pickedKey === name ? "" : name;
                const bind = root.modBinds.find(b => root.keysFor(b.key).includes(name));
                filterField.text = root.pickedKey.length > 0 && bind ? KeyUtils.comboText(bind.mods, bind.key) : "";
            }
        }

        // What the key under the pointer (or the picked one) does
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(48, shownColumn.implicitHeight + 20)
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            ColumnLayout {
                id: shownColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 14
                    rightMargin: 14
                }
                spacing: 6
                StyledText {
                    visible: root.shownKey.length === 0
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("Point at a key")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    visible: root.shownKey.length > 0 && root.shownBinds.length === 0
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("Nothing here yet. You can add your own shortcut at the bottom of this page.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: root.shownKey.length > 0 ? root.shownBinds : []
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Row {
                            spacing: 4
                            Repeater {
                                model: KeyUtils.comboLabels(parent.parent.modelData.mods, parent.parent.modelData.key)
                                delegate: Rectangle {
                                    required property string modelData
                                    width: Math.max(26, capText.implicitWidth + 12)
                                    height: 24
                                    radius: 6
                                    color: Appearance.colors.colLayer3
                                    StyledText {
                                        id: capText
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer3
                                    }
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr(parent.modelData.description)
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }

        Flow { // Shortcuts on keys the drawing doesn't have: arrows, the mouse wheel and buttons
            visible: root.offKeyboardBinds.length > 0
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                height: 30
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Also:")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            Repeater {
                model: root.offKeyboardBinds
                delegate: RippleButton {
                    id: offChip
                    required property var modelData
                    implicitHeight: 30
                    leftPadding: 12
                    rightPadding: 12
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: filterField.text = KeyUtils.comboText(offChip.modelData.mods, offChip.modelData.key)
                    contentItem: StyledText {
                        text: `${KeyUtils.keyLabel(offChip.modelData.key)} · ${Translation.tr(offChip.modelData.description)}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }

    Repeater {
        model: root.groupIds
        delegate: ContentSection {
            id: groupSection
            required property string modelData
            required property int index
            // Hundreds of rows at once froze the settings window for 0.4 s, so each group fills in a moment
            // after the one before it; settings search needs them all right away
            property bool rowsReady: ApplicationWindow.window?.loadAllPages ?? false
            Timer {
                interval: 20 * (groupSection.index + 1)
                running: !groupSection.rowsReady
                onTriggered: groupSection.rowsReady = true
            }
            readonly property var info: root.groupInfo(modelData)
            readonly property var uids: root.groupUids[modelData] ?? []
            readonly property bool anyMatch: root.filter.length === 0 || uids.some(uid => root.matches(uid))
            readonly property bool isCustom: modelData === "custom"

            visible: anyMatch || (isCustom && root.filter.length === 0)
            icon: info.icon
            title: Translation.tr(info.name)
            description: isCustom ? Translation.tr("Shortcuts you added. Ones defined in custom/keybinds.lua show up here too.") : ""

            Repeater {
                model: groupSection.rowsReady ? groupSection.uids : []
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
