pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    required property var bind
    required property var keys
    required property string capsLabel
    readonly property var held: HyprlandKeybinds.activeRecorder?.heldMods ?? []
    readonly property var mods: held.length ? held : bind?.disabled ? [] : bind?.mods ?? []
    readonly property string key: held.length || bind?.disabled ? "" : bind?.key ?? ""

    implicitHeight: content.implicitHeight + 16
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    ColumnLayout {
        id: content
        x: 10; y: 8
        width: Math.max(0, parent.width - 20)
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 3
            Layout.rightMargin: 3
            spacing: 8
            MaterialSymbol {
                text: KeyUtils.mouseLabels[root.key] ? "mouse" : "keyboard_command_key"
                iconSize: 18
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: Translation.tr(root.bind?.description ?? "")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
            KeyCombo {
                objectName: "catalogChord"
                visible: labels.length > 0
                labels: root.key ? KeyUtils.comboLabels(root.mods, root.key) : root.mods.map(mod => KeyUtils.modLabel(mod))
                pixelSize: Appearance.font.pixelSize.smaller
                keyColor: Appearance.colors.colPrimaryContainer
                textColor: Appearance.colors.colOnPrimaryContainer
            }
            StyledText {
                visible: root.bind?.disabled === true && !root.held.length
                text: Translation.tr("Turned off")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        KeyboardVisual {
            id: board
            objectName: "shortcutKeyboardMap"
            Layout.fillWidth: true
            compact: true
            showFunctionRow: true
            showNavigation: true
            animateLayout: true
            keys: root.keys
            capsLabel: root.capsLabel
            extraLabel: root.key && !positionsFor(root.key).length ? KeyUtils.keyLabel(root.key) : ""
            activeKeys: {
                const mods = root.mods.map(mod => board.positionsFor(mod)[0]).filter(Boolean);
                if (board.extraLabel) return [...mods, "extra"];
                const main = board.positionsFor(root.key);
                const genericModifier = KeyUtils.modOrder.some(mod => mod.toUpperCase() === root.key.toUpperCase());
                return mods.concat(genericModifier ? main.slice(0, 1) : main);
            }
            Accessible.description: root.key ? KeyUtils.comboText(root.mods, root.key) : root.mods.join(" + ")
        }
    }
}
