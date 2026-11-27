pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings

Rectangle {
    id: root
    objectName: "keyboardPreview"
    required property bool active
    required property var layoutOptions
    required property int configuredIndex
    required property string capsLabel
    required property KeyboardLayoutMap sourceMap
    readonly property string layout: sourceMap.layout
    readonly property string variant: sourceMap.variant
    readonly property int index: layoutOptions.findIndex(option => option.code === root.layout && option.variant === root.variant)
    readonly property var keymap: sourceMap.keys

    property var modifiers: ["Super"]
    property var pressedCodes: []
    property string pickedKey: ""
    readonly property string inspectedKey: board.hoveredKey || board.focusedKey || pickedKey
    readonly property var levels: keymap[inspectedKey]?.levels ?? []
    readonly property var assignments: keyBindings[inspectedKey] ?? []
    signal defaultRequested(int index)
    signal shortcutChosen(var bind)

    readonly property bool settingsSearchable: true
    readonly property string title: Translation.tr("Keyboard map")
    readonly property string searchText: [title, Translation.tr("Try typing here"), Translation.tr("Modifiers")].join(" ")

    enabled: active
    // The board and buttons handle navigation first. Unused keys can still reach the text field.
    Keys.forwardTo: active && !typingField.activeFocus ? [typingField] : []
    onActiveChanged: {
        if (active) Qt.callLater(root.focusOnOpen);
        else pressedCodes = [];
    }

    function focusTyping() {
        if (root.active) typingField.forceActiveFocus();
    }
    function focusOnOpen() {
        if (root.Window.window?.activeFocusItem?.cursorPosition === undefined)
            root.focusTyping();
    }
    readonly property var matchingBinds: {
        if (!root.active) return [];
        const mods = KeyUtils.sortMods(root.modifiers).join("+");
        return HyprlandKeybinds.binds.filter(bind => !bind.disabled && KeyUtils.sortMods(bind.mods).join("+") === mods);
    }
    readonly property var keyBindings: {
        const byKey = {};
        for (const bind of root.matchingBinds) {
            for (const name of board.positionsFor(bind.key)) {
                if (!byKey[name]) byKey[name] = [];
                byKey[name].push(bind);
            }
        }
        return byKey;
    }
    function toggleModifier(mod) {
        root.modifiers = root.modifiers.includes(mod) ? root.modifiers.filter(value => value !== mod) : [...root.modifiers, mod];
        root.pickedKey = "";
    }
    function selectKey(name) {
        if (!board.visualFocus) root.focusTyping();
        const bind = root.keyBindings[name]?.[0];
        if (bind) { root.shortcutChosen(bind); return; }
        const mod = KeyUtils.modOrder.find(value => board.modifierKeys[value].includes(name));
        if (mod) root.toggleModifier(mod);
        else root.pickedKey = root.pickedKey === name ? "" : name;
    }

    implicitHeight: panel.implicitHeight + 2 * panel.y
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    ColumnLayout {
        id: panel
        x: root.width < 468 ? 12 : 16
        y: 14
        width: Math.max(0, root.width - 2 * x)
        spacing: 10

        GridLayout {
            Layout.fillWidth: true
            columns: width >= 430 ? 2 : 1
            rowSpacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol { text: "keyboard"; iconSize: 22; color: Appearance.colors.colPrimary }
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnLayer2
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                }
            }
            RowLayout {
                spacing: 4
                ChoiceDropdown {
                    objectName: "keyboardPreviewLayout"
                    currentValue: root.index
                    options: root.layoutOptions
                    maximumWidth: 220
                    minimumWidth: 80
                    displayIcon: "language"
                    displayText: [currentOption?.displayName || root.layout.toUpperCase(), root.variant].filter(Boolean).join(" · ")
                    Accessible.name: Translation.tr("Layout") + " · " + displayText
                    onSelected: value => {
                        if (value !== root.index)
                            Quickshell.execDetached(["hyprctl", "switchxkblayout", HyprlandXkb.keyboardName || "current", String(value)]);
                        root.focusTyping();
                    }
                }
                SettingsAction {
                    id: defaultButton
                    visible: root.configuredIndex > 0
                    enabled: HyprlandSettings.ready
                    text: Translation.tr("Use %1 by default").arg(root.layout.toUpperCase())
                    implicitWidth: 34; implicitHeight: 34
                    buttonRadius: height / 2
                    contentItem: MaterialSymbol { text: "star"; fill: 0; iconSize: 19; horizontalAlignment: Text.AlignHCenter }
                    StyledToolTip { text: defaultButton.text }
                    onClicked: {
                        root.focusTyping();
                        root.defaultRequested(root.configuredIndex);
                    }
                }
            }
        }

        Row {
            Layout.fillWidth: true
            spacing: 3
            Repeater {
                model: KeyUtils.modOrder
                delegate: SelectionGroupButton {
                    id: modifier
                    required property string modelData
                    required property int index
                    buttonText: KeyUtils.modLabel(modelData)
                    leftmost: index === 0
                    rightmost: index === KeyUtils.modOrder.length - 1
                    toggled: root.modifiers.includes(modelData)
                    focusPolicy: Qt.StrongFocus
                    Accessible.name: modelData
                    Accessible.checkable: true
                    Accessible.checked: toggled
                    Keys.onReturnPressed: modifier.click()
                    Keys.onEnterPressed: modifier.click()
                    downAction: () => modifier.forceActiveFocus(Qt.MouseFocusReason)
                    onClicked: {
                        root.toggleModifier(modelData);
                        if (!visualFocus) root.focusTyping();
                    }
                }
            }
        }

        KeyboardVisual {
            id: board
            objectName: "keyboardMap"
            Layout.fillWidth: true
            interactive: true
            animateLayout: root.active
            showFunctionRow: true
            keys: root.keymap
            bindings: root.keyBindings
            pressedCodes: root.pressedCodes
            activeKeys: root.modifiers.reduce((keys, mod) => keys.concat(board.modifierKeys[mod]), [])
            capsLabel: root.capsLabel
            selectedKey: root.pickedKey
            onKeyClicked: name => root.selectKey(name)
        }

        TextField {
            id: typingField
            objectName: "keyboardTypingField"
            Layout.fillWidth: true
            implicitHeight: 42
            leftPadding: 40
            rightPadding: 12
            color: Appearance.colors.colOnLayer2
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            placeholderText: Translation.tr("Try typing here: the keys light up above")
            Accessible.name: placeholderText
            placeholderTextColor: Appearance.colors.colSubtext
            onTextEdited: if (!activeFocus) root.focusTyping()
            background: Rectangle {
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                border.width: typingField.activeFocus ? 2 : 1
                border.color: typingField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                MaterialSymbol {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "edit"; iconSize: 18; color: Appearance.colors.colSubtext
                }
            }
            Keys.onPressed: event => {
                if (!root.pressedCodes.includes(event.nativeScanCode)) root.pressedCodes = [...root.pressedCodes, event.nativeScanCode];
                event.accepted = false;
            }
            Keys.onReleased: event => {
                if (!event.isAutoRepeat) root.pressedCodes = root.pressedCodes.filter(code => code !== event.nativeScanCode);
                event.accepted = false;
            }
            onActiveFocusChanged: if (!activeFocus) root.pressedCodes = []
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 54
            spacing: 6
            Repeater {
                model: root.assignments
                delegate: GridLayout {
                    id: assignment
                    required property var modelData
                    Layout.fillWidth: true
                    columns: width >= chord.implicitWidth + 110 ? 2 : 1
                    columnSpacing: 10
                    rowSpacing: 4
                    KeyCombo {
                        id: chord
                        objectName: "keyboardShortcutChord"
                        mods: assignment.modelData.mods
                        key: assignment.modelData.key
                        Accessible.name: KeyUtils.comboText(mods, key)
                        pixelSize: Appearance.font.pixelSize.smaller
                        keyColor: Appearance.colors.colSecondaryContainer
                        textColor: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: Translation.tr(assignment.modelData.description)
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: !root.assignments.length
                text: root.sourceMap.unavailable ? Translation.tr("Layout preview unavailable")
                    : root.inspectedKey ? Translation.tr("No shortcut on this key")
                    : Translation.tr("Choose modifiers, then select a highlighted key to open its shortcut.")
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            Flow {
                id: symbols
                objectName: "keyboardLevels"
                readonly property var names: [Translation.tr("Unmodified"), "Shift", "AltGr", "AltGr + Shift"]
                readonly property var entries: root.levels.slice(0, names.length)
                    .map((symbol, i) => ({ symbol, name: names[i] })).filter(entry => entry.symbol?.trim())
                Layout.fillWidth: true
                visible: entries.length > 0
                spacing: 6
                Repeater {
                    model: symbols.entries
                    delegate: Rectangle {
                        id: level
                        required property var modelData
                        implicitWidth: levelText.implicitWidth + 16
                        implicitHeight: levelText.implicitHeight + 6
                        radius: Appearance.rounding.verysmall
                        color: Appearance.colors.colLayer3
                        RowLayout {
                            id: levelText
                            anchors.centerIn: parent
                            anchors.alignWhenCentered: false
                            spacing: 6
                            StyledText {
                                Layout.alignment: Qt.AlignBaseline
                                text: level.modelData.name
                                font.family: Appearance.font.family.main
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignBaseline
                                text: level.modelData.symbol
                                textFormat: Text.PlainText
                                font.family: Appearance.font.family.main
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer3
                            }
                        }
                    }
                }
            }
        }
    }
}
