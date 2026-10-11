import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A keybind in Settings > Keyboard Shortcuts: what it does and its keys. Click the keys to
 * record new ones; turned off or changed shortcuts get a button back to the default.
 */
ColumnLayout {
    id: root
    required property string uid
    readonly property var bind: HyprlandKeybinds.bindMap[root.uid] ?? null
    readonly property string title: Translation.tr(root.bind?.description ?? "")
    readonly property bool editable: !!root.bind && (root.bind.remappable || root.bind.custom === true)
    readonly property bool turnedOff: root.bind?.disabled === true
    readonly property var customShortcut: root.bind?.custom ? HyprlandKeybinds.custom[HyprlandKeybinds.customIndex(root.bind)] : null
    readonly property var customApp: root.customShortcut?.app ? DesktopEntries.byId(root.customShortcut.app) : null
    readonly property var conflicts: (!root.bind || root.turnedOff || root.bind.note) ? [] : HyprlandKeybinds.conflicts(root.bind.mods, root.bind.key, root.bind.id)
    property var pending: null // { mods, key, others, hidden } while asking what to do about a clash

    // Settings search
    readonly property bool settingsSearchable: true
    readonly property string text: root.title
    property string searchText: `${root.title} ${root.bind?.description ?? ""} ${root.bind ? KeyUtils.comboText(root.bind.mods, root.bind.key) : ""}`

    Layout.fillWidth: true
    spacing: 0

    HoverHandler {
        id: rowHover
    }

    function namesOf(binds) {
        return binds.map(bind => `“${Translation.tr(bind.description)}”`).join(", ");
    }

    function apply(mods, key) {
        const others = HyprlandKeybinds.conflicts(mods, key, root.bind.id);
        const hidden = HyprlandKeybinds.hiddenConflict(mods, key);
        if (others.length > 0 || hidden) {
            root.pending = { mods: mods, key: key, others: others, hidden: hidden };
            return;
        }
        root.commit(mods, key);
    }

    function commit(mods, key) {
        root.pending = null;
        if (root.bind.custom) {
            HyprlandKeybinds.updateCustom(HyprlandKeybinds.customIndex(root.bind), { mods: KeyUtils.sortMods(mods).join("+"), key: key });
        } else {
            HyprlandKeybinds.rebind(root.bind.id, mods, key);
        }
    }

    function replace() {
        for (const other of root.pending.others) HyprlandKeybinds.disable(other.id);
        root.commit(root.pending.mods, root.pending.key);
    }

    readonly property string statusText: {
        if (!root.bind) return "";
        if (recorder.recording) return recorder.hint || Translation.tr("Press the new keys · Esc cancels · Backspace turns off");
        if (root.turnedOff) return Translation.tr("Turned off");
        if (root.conflicts.length > 0) return Translation.tr("Also used by %1").arg(root.namesOf(root.conflicts));
        if (root.bind.remapped) return Translation.tr("Changed · default %1").arg(KeyUtils.comboText(root.bind.default_mods, root.bind.default_key));
        if (root.customShortcut?.command) return root.customShortcut.command;
        return "";
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 8
        Layout.topMargin: 5
        Layout.bottomMargin: 5
        spacing: 10

        Item { // App or command icon for shortcuts added here
            visible: root.bind?.custom === true
            implicitWidth: 26
            implicitHeight: 26
            IconImage {
                anchors.centerIn: parent
                visible: !!root.customApp
                implicitSize: 24
                source: root.customApp ? Quickshell.iconPath(root.customApp.icon, "application-x-executable") : ""
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.customApp
                text: "terminal"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: root.title
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.turnedOff ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2
            }
            StyledText {
                visible: root.statusText.length > 0
                Layout.fillWidth: true
                text: root.statusText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: root.customShortcut?.command && root.statusText === root.customShortcut.command ? Appearance.font.family.monospace : Appearance.font.family.main
                color: root.conflicts.length > 0 && !recorder.recording ? Appearance.colors.colError
                    : recorder.recording || root.bind?.remapped ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
        }

        MaterialSymbol {
            visible: root.conflicts.length > 0
            text: "warning"
            iconSize: 18
            fill: 1
            color: Appearance.colors.colError
        }

        ShortcutRecorder {
            id: recorder
            visible: root.editable
            mods: root.bind?.mods ?? []
            key: root.bind?.key ?? ""
            turnedOff: root.turnedOff
            allowTurnOff: !root.bind?.custom
            onRecorded: (mods, key) => root.apply(mods, key)
            onTurnOffRequested: HyprlandKeybinds.disable(root.bind.id)
        }

        KeyCombo { // Built-in combos that can't be changed here
            visible: !root.editable && !!root.bind
            Layout.rightMargin: 10
            mods: root.bind?.mods ?? []
            key: root.bind?.key ?? ""
            opacity: 0.8
        }

        RowIconButton {
            visible: root.editable && !root.bind?.custom && (root.bind?.remapped || root.turnedOff)
            iconName: "restart_alt"
            tooltip: Translation.tr("Back to %1").arg(KeyUtils.comboText(root.bind?.default_mods ?? [], root.bind?.default_key ?? ""))
            onClicked: HyprlandKeybinds.reset(root.bind.id)
        }
        RowIconButton { // Shown on hover; keeps its space so the keys don't jump
            visible: root.editable && !root.bind?.custom && !root.bind?.remapped && !root.turnedOff
            opacity: rowHover.hovered ? 1 : 0
            enabled: rowHover.hovered
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            iconName: "block"
            tooltip: Translation.tr("Turn off")
            onClicked: HyprlandKeybinds.disable(root.bind.id)
        }
        RowIconButton {
            visible: root.bind?.custom === true
            iconName: "delete"
            tooltip: Translation.tr("Remove")
            onClicked: HyprlandKeybinds.removeCustom(HyprlandKeybinds.customIndex(root.bind))
        }
    }

    Rectangle { // What to do about a clash
        visible: root.pending !== null
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.bottomMargin: 8
        implicitHeight: clashColumn.implicitHeight + 20
        radius: Appearance.rounding.small
        color: Appearance.colors.colErrorContainer

        ColumnLayout {
            id: clashColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 12
            }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                KeyCombo {
                    mods: root.pending?.mods ?? []
                    key: root.pending?.key ?? ""
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnErrorContainer
                    text: !root.pending ? "" : root.pending.others.length > 0
                        ? Translation.tr("is already used by %1").arg(root.namesOf(root.pending.others))
                        : Translation.tr("is already used by a built-in shortcut")
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 6
                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.pending = null
                }
                DialogButton {
                    buttonText: Translation.tr("Keep both")
                    onClicked: root.commit(root.pending.mods, root.pending.key)
                }
                DialogButton {
                    // Only listed, changeable shortcuts can be turned off from here
                    visible: !!root.pending && !root.pending.hidden && root.pending.others.every(other => other.remappable)
                    buttonText: Translation.tr("Replace")
                    onClicked: root.replace()
                }
            }
        }
    }

    component RowIconButton: RippleButton {
        id: iconButton
        property string iconName
        property string tooltip
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: iconButton.iconName
            iconSize: 18
            color: Appearance.colors.colSubtext
        }
        StyledToolTip {
            text: iconButton.tooltip
        }
    }
}
