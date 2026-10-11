pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * "Add shortcut" row that opens into a small form: pick an app or type a command, record keys.
 */
ColumnLayout {
    id: root
    property bool expanded: false
    property string mode: "app"
    property var app: null // DesktopEntry
    property string appFilter: ""
    property var mods: []
    property string key: ""
    readonly property bool valid: root.key.length > 0 && (root.mode === "app" ? root.app !== null : commandField.value.trim().length > 0)
    readonly property var clashes: root.key.length > 0 ? HyprlandKeybinds.conflicts(root.mods, root.key, "") : []
    readonly property bool hiddenClash: root.key.length > 0 && HyprlandKeybinds.hiddenConflict(root.mods, root.key)

    // Settings search
    readonly property bool settingsSearchable: true
    readonly property string text: Translation.tr("Add shortcut")
    property string searchText: `${root.text} ${Translation.tr("Launch an app or run a command")}`

    Layout.fillWidth: true
    spacing: 0

    readonly property var apps: {
        if (!root.expanded) return [];
        const filter = root.appFilter.trim().toLowerCase();
        return DesktopEntries.applications.values
            .filter(entry => !entry.noDisplay && (filter.length === 0
                || `${entry.name} ${entry.genericName ?? ""} ${entry.id}`.toLowerCase().includes(filter)))
            .sort((a, b) => a.name.localeCompare(b.name));
    }

    function reset() {
        root.expanded = false;
        root.mode = "app";
        root.app = null;
        root.appFilter = "";
        root.mods = [];
        root.key = "";
        commandField.value = "";
        nameField.value = "";
    }

    function add() {
        let shortcut = { mods: KeyUtils.sortMods(root.mods).join("+"), key: root.key };
        if (root.mode === "app") {
            shortcut.app = root.app.id;
            shortcut.description = root.app.name;
        } else {
            shortcut.command = commandField.value.trim();
            shortcut.description = nameField.value.trim() || shortcut.command;
        }
        HyprlandKeybinds.addCustom(shortcut);
        root.reset();
    }

    ConfigNavRow { // Collapsed
        visible: !root.expanded
        buttonIcon: "add"
        title: Translation.tr("Add shortcut")
        description: Translation.tr("Launch an app or run a command")
        trailingIcon: "expand_more"
        onClicked: root.expanded = true
    }

    ColumnLayout { // Form
        visible: root.expanded
        Layout.fillWidth: true
        Layout.margins: 8
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            spacing: 10
            ConfigIconTile {
                icon: "add"
                active: true
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("New shortcut")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
            Rectangle { // What it will open
                visible: root.mode === "app" && root.app !== null
                implicitHeight: 30
                implicitWidth: chosenRow.implicitWidth + 20
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer
                RowLayout {
                    id: chosenRow
                    anchors.centerIn: parent
                    spacing: 6
                    IconImage {
                        implicitSize: 18
                        source: root.app ? Quickshell.iconPath(root.app.icon, "application-x-executable") : ""
                    }
                    StyledText {
                        text: root.app?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
            KeyCombo {
                visible: root.key.length > 0
                mods: root.mods
                key: root.key
            }
        }

        ConfigSelectionArray {
            Layout.leftMargin: 4
            currentValue: root.mode
            onSelected: newValue => root.mode = newValue
            options: [
                { displayName: Translation.tr("Open an app"), icon: "apps", value: "app" },
                { displayName: Translation.tr("Run a command"), icon: "terminal", value: "command" }
            ]
        }

        ColumnLayout { // App picker
            visible: root.mode === "app"
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                border.width: appSearch.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8
                    MaterialSymbol {
                        text: "search"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                    TextField {
                        id: appSearch
                        Layout.fillWidth: true
                        background: null
                        padding: 0
                        placeholderText: Translation.tr("Find an app")
                        placeholderTextColor: Appearance.colors.colSubtext
                        color: Appearance.colors.colOnLayer3
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        onTextChanged: root.appFilter = text
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 220
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                clip: true

                StyledListView {
                    id: appList
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 2
                    model: root.apps
                    delegate: RippleButton {
                        id: appButton
                        required property var modelData
                        readonly property bool selected: root.app?.id === appButton.modelData.id
                        width: appList.width
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.small
                        colBackground: appButton.selected ? Appearance.colors.colSecondaryContainer : "transparent"
                        colBackgroundHover: appButton.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
                        onClicked: {
                            root.app = appButton.modelData;
                            // Next step right away: listen for the keys
                            if (root.key.length === 0) keyRecorder.start();
                        }
                        contentItem: RowLayout {
                            spacing: 10
                            IconImage {
                                Layout.leftMargin: 6
                                implicitSize: 24
                                source: Quickshell.iconPath(appButton.modelData.icon, "application-x-executable")
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: appButton.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: appButton.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.maximumWidth: 200
                                text: appButton.modelData.genericName ?? ""
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                Layout.rightMargin: 6
                                visible: appButton.selected
                                text: "check"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }
        }

        ConfigTextRow {
            id: commandField
            visible: root.mode === "command"
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            icon: "terminal"
            label: Translation.tr("Command")
            monospace: true
            wrapMode: TextEdit.NoWrap
            placeholderText: "notify-send Hello"
        }
        ConfigTextRow {
            id: nameField
            visible: root.mode === "command"
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            icon: "label"
            label: Translation.tr("Name in the cheat sheet")
            wrapMode: TextEdit.NoWrap
            placeholderText: Translation.tr("Optional")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 4
            spacing: 10
            ConfigIconTile {
                icon: "keyboard"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Keys")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: keyRecorder.recording ? Appearance.colors.colPrimary : Appearance.colors.colError
                    text: keyRecorder.recording ? (keyRecorder.hint || Translation.tr("Press the keys · Esc cancels"))
                        : root.clashes.length > 0 ? Translation.tr("Also used by %1").arg(root.clashes.map(bind => `“${Translation.tr(bind.description)}”`).join(", "))
                        : root.hiddenClash ? Translation.tr("Also used by a built-in shortcut") : ""
                }
            }
            ShortcutRecorder {
                id: keyRecorder
                mods: root.mods
                key: root.key
                allowTurnOff: false
                emptyText: Translation.tr("Record keys")
                onRecorded: (mods, key) => {
                    root.mods = mods;
                    root.key = key;
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 4
            spacing: 6
            StyledText { // What's still missing
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: root.valid ? "" : root.mode === "app" && root.app === null ? Translation.tr("Pick an app from the list")
                    : root.mode === "command" && commandField.value.trim().length === 0 ? Translation.tr("Type a command")
                    : Translation.tr("Record the keys")
            }
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: root.reset()
            }
            DialogButton {
                buttonText: Translation.tr("Add")
                enabled: root.valid
                colBackground: root.valid ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colText: root.valid ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                onClicked: root.add()
            }
        }
    }
}
