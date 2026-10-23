import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * A drawn keyboard with what each key types in a layout (keys from scripts/keyboard/layout_keys.py).
 * Keys whose keycode is in `pressedCodes` light up; `keyColors` tints keys by name (e.g. those with a
 * shortcut) and `keyHints` puts a small word on them. Keys can be hovered and clicked (keyClicked).
 */
Item {
    id: root
    property var keys: ({}) // { "AD01": { code, levels: ["q", "Q"] }, ... }
    property var pressedCodes: [] // XKB keycodes held right now
    property string capsLabel: "Caps Lock"
    property bool showFunctionRow: false // Esc, F1–F12, Print and Delete
    property var keyColors: ({}) // key name -> color
    property var keyHints: ({}) // key name -> a short word shown on the key
    property var activeKeys: [] // Key names drawn as held, e.g. the modifiers being looked at
    property string selectedKey: ""
    property bool interactive: false
    property string hoveredKey: ""
    signal keyClicked(string name)
    readonly property real unit: Math.floor((root.width - 14 * root.gap) / 15)
    readonly property real gap: Math.max(3, Math.round(root.width / 180))
    readonly property real keyHeight: Math.round(root.unit * 0.92)

    readonly property var functionRow: [["ESC", 1, "Esc"], ["FK01", 1, "F1"], ["FK02", 1, "F2"], ["FK03", 1, "F3"], ["FK04", 1, "F4"], ["FK05", 1, "F5"], ["FK06", 1, "F6"],
        ["FK07", 1, "F7"], ["FK08", 1, "F8"], ["FK09", 1, "F9"], ["FK10", 1, "F10"], ["FK11", 1, "F11"], ["FK12", 1, "F12"], ["PRSC", 1, "Print"], ["DELE", 1, "Del"]]
    readonly property var rows: root.showFunctionRow ? [root.functionRow, ...root.mainRows] : root.mainRows
    // Rows of [key name, width in key units, label for keys that don't type a character]
    readonly property var mainRows: [
        [["TLDE", 1], ["AE01", 1], ["AE02", 1], ["AE03", 1], ["AE04", 1], ["AE05", 1], ["AE06", 1], ["AE07", 1], ["AE08", 1], ["AE09", 1], ["AE10", 1], ["AE11", 1], ["AE12", 1], ["BKSP", 2, "⌫"]],
        [["TAB", 1.5, "Tab"], ["AD01", 1], ["AD02", 1], ["AD03", 1], ["AD04", 1], ["AD05", 1], ["AD06", 1], ["AD07", 1], ["AD08", 1], ["AD09", 1], ["AD10", 1], ["AD11", 1], ["AD12", 1], ["BKSL", 1.5]],
        [["CAPS", 1.75, "caps"], ["AC01", 1], ["AC02", 1], ["AC03", 1], ["AC04", 1], ["AC05", 1], ["AC06", 1], ["AC07", 1], ["AC08", 1], ["AC09", 1], ["AC10", 1], ["AC11", 1], ["RTRN", 2.25, "Enter"]],
        [["LFSH", 2.25, "Shift"], ["AB01", 1], ["AB02", 1], ["AB03", 1], ["AB04", 1], ["AB05", 1], ["AB06", 1], ["AB07", 1], ["AB08", 1], ["AB09", 1], ["AB10", 1], ["RTSH", 2.75, "Shift"]],
        [["LCTL", 1.5, "Ctrl"], ["LWIN", 1.25, "Super"], ["LALT", 1.25, "Alt"], ["SPCE", 7, ""], ["RALT", 1.25, "AltGr"], ["MENU", 1.25, "☰"], ["RCTL", 1.5, "Ctrl"]],
    ]

    implicitHeight: root.rows.length * root.keyHeight + (root.rows.length - 1) * root.gap + 24

    Rectangle { // The keyboard's body
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
    }

    Column {
        anchors.centerIn: parent
        spacing: root.gap

        Repeater {
            model: root.rows
            delegate: Row {
                id: keyRow
                required property var modelData
                spacing: root.gap

                Repeater {
                    model: keyRow.modelData
                    delegate: Rectangle {
                        id: key
                        required property var modelData
                        readonly property string keyName: key.modelData[0]
                        readonly property var info: root.keys[key.keyName] ?? null
                        readonly property bool special: key.modelData.length > 2
                        readonly property string lower: key.info?.levels?.[0] ?? ""
                        readonly property string upper: key.info?.levels?.[1] ?? ""
                        // Letters show one capital, like on real keycaps; other keys show both levels
                        readonly property bool letter: key.lower.length > 0 && key.upper === key.lower.toUpperCase() && key.upper !== key.lower
                        readonly property bool pressed: (!!key.info && (root.pressedCodes ?? []).includes(key.info.code))
                            || (root.activeKeys ?? []).includes(key.keyName) || root.selectedKey === key.keyName
                        readonly property color tint: root.keyColors[key.keyName] ?? "transparent"
                        readonly property bool tinted: root.keyColors[key.keyName] !== undefined
                        readonly property string hint: root.keyHints[key.keyName] ?? ""

                        width: Math.round(root.unit * key.modelData[1] + root.gap * (key.modelData[1] - 1))
                        height: root.keyHeight
                        radius: Math.max(4, root.unit * 0.16)
                        color: key.pressed ? Appearance.colors.colPrimary
                            : key.tinted ? key.tint
                            : keyMouse.containsMouse ? Appearance.colors.colLayer3Active
                            : key.special ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                        readonly property color ink: key.pressed ? Appearance.colors.colOnPrimary
                            : key.tinted ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3

                        MouseArea {
                            id: keyMouse
                            anchors.fill: parent
                            enabled: root.interactive
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: {
                                if (containsMouse) root.hoveredKey = key.keyName;
                                else if (root.hoveredKey === key.keyName) root.hoveredKey = "";
                            }
                            onClicked: root.keyClicked(key.keyName)
                        }
                        StyledText { // A word about what the key does, bottom right
                            visible: key.hint.length > 0
                            anchors {
                                right: parent.right
                                bottom: parent.bottom
                                margins: Math.max(2, root.unit * 0.08)
                            }
                            width: Math.min(implicitWidth, parent.width - 6)
                            elide: Text.ElideRight
                            text: key.hint
                            font.pixelSize: Math.max(7, root.unit * 0.17)
                            color: key.ink
                            opacity: 0.85
                        }

                        StyledText { // Keys that don't type: their name
                            visible: key.special
                            anchors {
                                left: parent.left
                                bottom: parent.bottom
                                margins: Math.max(3, root.unit * 0.14)
                            }
                            text: key.modelData[2] === "caps" ? root.capsLabel : (key.modelData[2] ?? "")
                            font.pixelSize: Math.max(8, root.unit * (text.length === 1 ? 0.36 : 0.24)) // Symbols like ⌫ need to be bigger than words
                            color: key.ink
                            opacity: key.pressed ? 1 : 0.75
                        }
                        StyledText { // A letter
                            visible: !key.special && key.letter
                            anchors.centerIn: parent
                            text: key.upper
                            font.pixelSize: Math.max(9, root.unit * 0.4)
                            color: key.ink
                        }
                        StyledText { // Shifted character, top left
                            visible: !key.special && !key.letter && key.upper.length > 0 && key.upper !== key.lower
                            anchors {
                                left: parent.left
                                top: parent.top
                                leftMargin: Math.max(3, root.unit * 0.16)
                                topMargin: Math.max(2, root.unit * 0.08)
                            }
                            text: key.upper
                            font.pixelSize: Math.max(8, root.unit * 0.3)
                            color: key.ink
                            opacity: 0.75
                        }
                        StyledText { // Unshifted character, bottom left
                            visible: !key.special && !key.letter && key.lower.length > 0
                            anchors {
                                left: parent.left
                                bottom: parent.bottom
                                leftMargin: Math.max(3, root.unit * 0.16)
                                bottomMargin: Math.max(2, root.unit * 0.08)
                            }
                            text: key.lower
                            font.pixelSize: Math.max(8, root.unit * 0.34)
                            color: key.ink
                        }
                    }
                }
            }
        }
    }
}
