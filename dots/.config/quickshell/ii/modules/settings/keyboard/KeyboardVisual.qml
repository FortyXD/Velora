pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Control {
    id: root
    property var keys: ({})
    property var bindings: ({})
    property var pressedCodes: []
    property var activeKeys: []
    property bool interactive: false
    property bool compact: false
    property bool animateLayout: interactive
    property bool showFunctionRow: false
    property bool showNavigation: false
    property string extraLabel: ""
    property string capsLabel: "Caps Lock"
    property string selectedKey: ""
    property string hoveredKey: ""
    signal keyClicked(string name)
    property var displayedKeys: ({})
    property var outgoingKeys: null
    property real layoutProgress: 1
    readonly property bool switchingLayout: layoutMotion.running
    onKeysChanged: Qt.callLater(adoptKeymap)
    onAnimateLayoutChanged: if (!animateLayout && switchingLayout) {
        layoutMotion.stop();
        layoutProgress = 1;
        outgoingKeys = null;
    }
    Component.onCompleted: adoptKeymap()

    function adoptKeymap() {
        if (displayedKeys === keys) return;
        const previous = switchingLayout && layoutProgress < 0.5 ? outgoingKeys : displayedKeys;
        layoutMotion.stop();
        displayedKeys = keys;
        if (animateLayout && previous?.AD01 && keys?.AD01 && previous !== keys && Appearance.scaledDuration(320) > 0) {
            outgoingKeys = previous;
            layoutMotion.restart();
        } else {
            outgoingKeys = null;
            layoutProgress = 1;
        }
    }
    NumberAnimation {
        id: layoutMotion
        target: root
        property: "layoutProgress"
        from: 0; to: 1
        duration: Appearance.scaledDuration(320)
        onFinished: root.outgoingKeys = null
    }

    readonly property int inset: compact || width < 560 ? 6 : 10
    readonly property int gap: compact ? 3 : width >= 620 ? 5 : width >= 420 ? 4 : 3
    readonly property int rowWidth: Math.max(0, Math.round(width) - 2 * inset)
    readonly property real pitch: (rowWidth + gap) / (showNavigation ? 18.35 : 15)
    readonly property int keyHeight: compact ? 24 : Math.max(30, Math.min(44, Math.round((pitch - gap) * 0.9)))
    readonly property int functionHeight: Math.round(keyHeight * 0.76)
    readonly property bool shiftHeld: pressedCodes.includes(keys.LFSH?.code) || pressedCodes.includes(keys.RTSH?.code)
    readonly property color shortcutColor: ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer3Base, 0.55)

    focusPolicy: interactive ? Qt.StrongFocus : Qt.NoFocus
    property int cursorRow: 2
    property int cursorColumn: 1
    readonly property string cursorKey: rows[cursorRow][cursorColumn][0]
    readonly property string focusedKey: visualFocus ? cursorKey : ""
    Accessible.role: Accessible.Grouping
    Accessible.name: Translation.tr("Keyboard map")

    function printedSymbol(levels) {
        const lower = levels?.[0] ?? "", upper = levels?.[1] ?? "";
        return root.shiftHeld || (lower && upper === lower.toUpperCase()) ? upper || lower : lower || upper;
    }

    readonly property var modifierKeys: ({ Super: ["LWIN"], Ctrl: ["LCTL", "RCTL"], Alt: ["LALT"], Shift: ["LFSH", "RTSH"] })
    // Shortcut names and raw keycodes identify physical positions, independently of the printed layout.
    readonly property var positions: {
        const result = { CAPS_LOCK: ["CAPS"], MENU: ["MENU"], CONTROL_L: ["LCTL"], CONTROL_R: ["RCTL"],
            SHIFT_L: ["LFSH"], SHIFT_R: ["RTSH"], ALT_L: ["LALT"], ALT_R: ["RALT"], SUPER_L: ["LWIN"], SUPER_R: [] };
        for (const row of root.rows) {
            for (const [name] of row) {
                const code = root.keys[name]?.code;
                if (!code) continue;
                result["CODE:" + code] = [name];
                const symbol = KeyUtils.scanCodeNames[code];
                if (symbol) result[KeyUtils.normalizeKey(symbol)] = [name];
            }
        }
        for (const mod of KeyUtils.modOrder) result[mod.toUpperCase()] = root.modifierKeys[mod];
        result["1-0"] = ["AE01", "AE02", "AE03", "AE04", "AE05", "AE06", "AE07", "AE08", "AE09", "AE10"];
        if (root.showNavigation) {
            result.ARROWS = ["LEFT", "UP", "DOWN", "RGHT"];
            result["LEFT/RIGHT"] = ["LEFT", "RGHT"];
        }
        return result;
    }
    function positionsFor(key) {
        return positions[(key ?? "").toUpperCase()] ?? positions[KeyUtils.normalizeKey(key)] ?? [];
    }
    function moveCursor(dx, dy) {
        const row = Math.max(0, Math.min(root.rows.length - 1, root.cursorRow + dy));
        const column = Math.max(0, Math.min(root.rows[row].length - 1, root.cursorColumn + dx));
        // Clamp before moving to a shorter row so the focused key always exists.
        if (column < root.cursorColumn) root.cursorColumn = column;
        root.cursorRow = row;
        root.cursorColumn = column;
    }
    Keys.onLeftPressed: root.moveCursor(-1, 0)
    Keys.onRightPressed: root.moveCursor(1, 0)
    Keys.onUpPressed: root.moveCursor(0, -1)
    Keys.onDownPressed: root.moveCursor(0, 1)
    Keys.onReturnPressed: root.keyClicked(root.cursorKey)
    Keys.onEnterPressed: root.keyClicked(root.cursorKey)
    Keys.onSpacePressed: root.keyClicked(root.cursorKey)

    readonly property var functionRow: [["ESC", 1, "Esc"], ["FK01", 1, "F1"], ["FK02", 1, "F2"], ["FK03", 1, "F3"], ["FK04", 1, "F4"], ["FK05", 1, "F5"], ["FK06", 1, "F6"],
        ["FK07", 1, "F7"], ["FK08", 1, "F8"], ["FK09", 1, "F9"], ["FK10", 1, "F10"], ["FK11", 1, "F11"], ["FK12", 1, "F12"], ["PRSC", 1, "Print"], ["DELE", 1, "Del"]]
    // The optional fourth field places the navigation cluster after the main keys.
    readonly property var navigationRows: [
        [["extra", 3, "", 15.35]],
        [["INS", 1, "Ins", 15.35], ["HOME", 1, "Home"], ["PGUP", 1, "PgUp"]],
        [["DELE", 1, "Del", 15.35], ["END", 1, "End"], ["PGDN", 1, "PgDn"]],
        [], [["UP", 1, "↑", 16.35]],
        [["LEFT", 1, "←", 15.35], ["DOWN", 1, "↓"], ["RGHT", 1, "→"]]
    ]
    readonly property var rows: {
        const base = root.showFunctionRow ? [root.functionRow, ...root.mainRows] : root.mainRows;
        if (!root.showNavigation) return base;
        return base.map((row, i) => {
            const index = root.showFunctionRow ? i : i + 1;
            const main = index === 0 ? [...row.slice(0, -1), ["PAUS", 1, "Pause"]] : row;
            return [...main, ...root.navigationRows[index]];
        });
    }
    // Rows of [key name, width in key units, label for keys that don't type a character]
    readonly property var mainRows: [
        [["TLDE", 1], ["AE01", 1], ["AE02", 1], ["AE03", 1], ["AE04", 1], ["AE05", 1], ["AE06", 1], ["AE07", 1], ["AE08", 1], ["AE09", 1], ["AE10", 1], ["AE11", 1], ["AE12", 1], ["BKSP", 2, "⌫"]],
        [["TAB", 1.5, "Tab"], ["AD01", 1], ["AD02", 1], ["AD03", 1], ["AD04", 1], ["AD05", 1], ["AD06", 1], ["AD07", 1], ["AD08", 1], ["AD09", 1], ["AD10", 1], ["AD11", 1], ["AD12", 1], ["BKSL", 1.5]],
        [["CAPS", 1.75, "caps"], ["AC01", 1], ["AC02", 1], ["AC03", 1], ["AC04", 1], ["AC05", 1], ["AC06", 1], ["AC07", 1], ["AC08", 1], ["AC09", 1], ["AC10", 1], ["AC11", 1], ["RTRN", 2.25, "Enter"]],
        [["LFSH", 2.25, "Shift"], ["AB01", 1], ["AB02", 1], ["AB03", 1], ["AB04", 1], ["AB05", 1], ["AB06", 1], ["AB07", 1], ["AB08", 1], ["AB09", 1], ["AB10", 1], ["RTSH", 2.75, "Shift"]],
        [["LCTL", 1.5, "Ctrl"], ["LWIN", 1.25, "Super"], ["LALT", 1.25, "Alt"], ["SPCE", 7, ""], ["RALT", 1.25, "AltGr"], ["MENU", 1.25, "☰"], ["RCTL", 1.5, "Ctrl"]],
    ]

    implicitHeight: keyRows.implicitHeight + 2 * root.inset

    background: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1Base
    }
    Column {
        id: keyRows
        x: root.inset; y: root.inset
        width: root.rowWidth
        spacing: root.gap
        Repeater {
            model: root.rows
            delegate: Item {
                id: keyRow
                required property var modelData
                required property int index
                readonly property bool functionKeys: root.showFunctionRow && index === 0
                readonly property real phase: Math.max(0, Math.min(1, (root.layoutProgress - index * 0.025) / 0.875))
                // Snap the shared boundaries so wide keys and single keys finish on the same pixel.
                readonly property var keyRects: {
                    let units = 0;
                    return modelData.map(entry => {
                        const start = entry[3] ?? units;
                        units = start + entry[1];
                        const x = Math.round(start * root.pitch);
                        return { x, width: Math.max(0, Math.round(units * root.pitch) - x - root.gap) };
                    });
                }
                width: root.rowWidth
                height: functionKeys ? root.functionHeight + root.gap : root.keyHeight
                Repeater {
                    model: keyRow.modelData
                    delegate: Item {
                        id: key
                        required property var modelData
                        required property int index
                        readonly property string name: modelData[0]
                        objectName: "keyboardKey-" + name
                        readonly property var info: root.displayedKeys[name]
                        readonly property bool special: modelData.length > 2
                        readonly property string upper: info?.levels?.[1] ?? ""
                        readonly property string label: {
                            if (!special) return root.printedSymbol(info?.levels);
                            if (name === "extra") return root.extraLabel;
                            if (name === "CAPS") return root.capsLabel;
                            if (name === "LWIN") return KeyUtils.modLabel("Super");
                            return modelData[2];
                        }
                        readonly property string oldLabel: root.outgoingKeys ? root.printedSymbol(root.outgoingKeys[name]?.levels) : ""
                        readonly property bool changing: !special && root.switchingLayout && oldLabel !== label
                        readonly property string icon: ({"BKSP": "backspace", "MENU": "menu", "SPCE": "space_bar"})[name] ?? ""
                        readonly property bool held: !!info && root.pressedCodes.includes(info.code)
                        readonly property bool highlighted: root.activeKeys.includes(name)
                        readonly property bool bound: !!root.bindings[name]
                        readonly property bool selected: root.selectedKey === name || root.focusedKey === name
                        readonly property bool pressed: held || pointer.pressed
                        readonly property color ink: pressed || highlighted ? Appearance.colors.colOnPrimary
                            : bound ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3

                        visible: name !== "extra" || root.extraLabel.length > 0
                        x: keyRow.keyRects[index].x
                        width: keyRow.keyRects[index].width
                        height: keyRow.functionKeys ? root.functionHeight : root.keyHeight
                        Accessible.role: root.interactive ? Accessible.Button : Accessible.StaticText
                        Accessible.name: name === "SPCE" ? Translation.tr("Space") : name === "LWIN" ? "Super" : label || name
                        Accessible.onPressAction: if (root.interactive) root.keyClicked(name)

                        Rectangle {
                            anchors.fill: parent
                            radius: Math.min(Appearance.rounding.small, Math.round(height * 0.24))
                            color: key.pressed || key.highlighted ? Appearance.colors.colPrimary
                                : key.bound ? (pointer.containsMouse ? Appearance.colors.colSecondaryContainerHover : root.shortcutColor)
                                : pointer.containsMouse ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3Base
                            border.width: key.selected || pointer.containsMouse ? 2 : 0
                            border.color: Appearance.colors.colPrimary
                            scale: key.pressed ? 0.95 : 1
                            Behavior on scale { NumberAnimation { duration: Appearance.scaledDuration(90); easing.type: Easing.OutCubic } }
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                            StyledText {
                                visible: !key.icon
                                opacity: key.changing ? Math.abs(2 * keyRow.phase - 1) : 1
                                transform: Translate {
                                    y: key.changing ? (keyRow.phase < 0.5 ? -keyRow.phase : 1 - keyRow.phase) * key.height * 0.48 : 0
                                }
                                anchors.fill: parent
                                leftPadding: 2
                                rightPadding: 2
                                text: key.changing && keyRow.phase < 0.5 ? key.oldLabel
                                    : key.name === "CAPS" && key.label === "Caps Lock" && key.width < 58 ? "Caps" : key.label
                                textFormat: Text.PlainText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.family: Appearance.font.family.main
                                font.pixelSize: Math.round(Math.max(8, Math.min(key.special ? Appearance.font.pixelSize.smallie : Appearance.font.pixelSize.large,
                                    key.height * (key.special ? 0.44 : 0.5))))
                                font.weight: key.special ? Font.Medium : Font.DemiBold
                                fontSizeMode: Text.Fit
                                minimumPixelSize: 7
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                color: key.ink
                            }
                            Loader {
                                active: key.icon.length > 0
                                anchors.centerIn: parent
                                anchors.alignWhenCentered: false
                                sourceComponent: MaterialSymbol {
                                    text: key.icon
                                    iconSize: Math.round(Math.min(Appearance.font.pixelSize.larger, key.height * 0.54))
                                    color: key.ink
                                }
                            }
                        }
                        MouseArea {
                            id: pointer
                            anchors.fill: parent
                            enabled: root.interactive
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: {
                                if (containsMouse) root.hoveredKey = key.name;
                                else if (root.hoveredKey === key.name) root.hoveredKey = "";
                            }
                            onClicked: {
                                root.moveCursor(key.index - root.cursorColumn, keyRow.index - root.cursorRow);
                                root.forceActiveFocus(Qt.MouseFocusReason);
                                root.keyClicked(key.name);
                            }
                        }
                    }
                }
            }
        }
    }
}
