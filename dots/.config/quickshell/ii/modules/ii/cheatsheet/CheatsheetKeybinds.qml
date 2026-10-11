pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Every described keybind, grouped and searchable. Reads the manifest the Hyprland config writes,
 * so changes made in the settings app show up right away.
 */
Item {
    id: root
    property real maxWidth: 1200
    property real maxHeight: 800
    property real columnMinWidth: 330
    property real spacing: 12
    property bool active: true

    signal closeRequested()

    implicitWidth: root.maxWidth
    implicitHeight: Math.min(root.maxHeight, header.implicitHeight + root.spacing + Math.max(columnsRow.implicitHeight, 160))

    onActiveChanged: if (active) searchField.forceActiveFocus()
    Component.onCompleted: if (active) searchField.forceActiveFocus()

    function normalize(text) {
        return (text ?? "").toString().toLowerCase().replace(/ё/g, "е");
    }

    function matches(bind, terms) {
        if (terms.length === 0) return true;
        const haystack = root.normalize([Translation.tr(bind.description), bind.description,
            KeyUtils.comboText(bind.mods, bind.key), KeyUtils.comboLabels(bind.mods, bind.key).join(" ")].join(" "));
        return terms.every(term => haystack.includes(term));
    }

    readonly property var visibleGroups: {
        const terms = root.normalize(searchField.text).split(" ").filter(term => term.length > 0);
        return HyprlandKeybinds.groups.map(group => ({
            group: group,
            binds: HyprlandKeybinds.binds.filter(bind => bind.group === group.id && !bind.disabled && root.matches(bind, terms))
        })).filter(entry => entry.binds.length > 0);
    }

    readonly property int columnCount: Math.max(1, Math.floor((flickable.width + root.spacing) / (root.columnMinWidth + root.spacing)))
    readonly property real columnWidth: (flickable.width - root.spacing * (root.columnCount - 1)) / root.columnCount

    // Masonry: each group goes into the column that is currently the shortest
    readonly property var columns: {
        let columns = Array.from({ length: root.columnCount }, () => ({ weight: 0, groups: [] }));
        for (const entry of root.visibleGroups) {
            let shortest = columns[0];
            for (const column of columns) {
                if (column.weight < shortest.weight) shortest = column;
            }
            shortest.groups.push(entry);
            shortest.weight += entry.binds.length + 2.5; // The header counts for a couple of rows
        }
        return columns.filter(column => column.groups.length > 0);
    }

    RowLayout { // Search and edit button
        id: header
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            implicitHeight: 42
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer1
            border.width: searchField.activeFocus ? 2 : 0
            border.color: Appearance.colors.colPrimary

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 14
                    rightMargin: 6
                }
                spacing: 8

                MaterialSymbol {
                    text: "search"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    padding: 0
                    placeholderText: Translation.tr("Search shortcuts, e.g. screenshot or Super+B")
                    placeholderTextColor: Appearance.colors.colSubtext
                    color: Appearance.colors.colOnLayer1
                    selectedTextColor: Appearance.colors.colOnSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    font {
                        family: Appearance.font.family.main
                        pixelSize: Appearance.font.pixelSize.small
                        variableAxes: Appearance.font.variableAxes.main
                    }
                    Keys.onEscapePressed: event => {
                        if (searchField.text.length > 0) searchField.text = "";
                        else root.closeRequested();
                        event.accepted = true;
                    }
                    onTextChanged: flickable.contentY = 0
                }
                RippleButton {
                    visible: searchField.text.length > 0
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: searchField.text = ""
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        RippleButton {
            implicitHeight: 42
            implicitWidth: editRow.implicitWidth + 32
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: {
                Quickshell.execDetached(["env", "QS_SETTINGS_PAGE=shortcuts", "qs", "-p", Quickshell.shellPath("settings.qml")]);
                root.closeRequested();
            }
            contentItem: RowLayout {
                id: editRow
                spacing: 8
                MaterialSymbol {
                    text: "edit"
                    iconSize: 18
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    text: Translation.tr("Change shortcuts")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }

    StyledFlickable {
        id: flickable
        anchors {
            top: header.bottom
            topMargin: root.spacing
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: true
        contentHeight: columnsRow.implicitHeight

        Row {
            id: columnsRow
            x: Math.round((flickable.width - width) / 2)
            spacing: root.spacing

            Repeater {
                model: root.columns
                delegate: Column {
                    id: column
                    required property var modelData
                    width: root.columnWidth
                    spacing: root.spacing

                    Repeater {
                        model: column.modelData.groups
                        delegate: GroupCard {
                            width: column.width
                        }
                    }
                }
            }
        }
    }

    ColumnLayout { // Nothing found
        anchors.centerIn: flickable
        visible: root.visibleGroups.length === 0
        spacing: 6
        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: HyprlandKeybinds.ready ? "search_off" : "hourglass_empty"
            iconSize: 40
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: HyprlandKeybinds.ready ? Translation.tr("No shortcuts match") : Translation.tr("Reading keybinds…")
            color: Appearance.colors.colSubtext
        }
    }

    component GroupCard: Rectangle {
        id: card
        required property var modelData
        implicitHeight: cardColumn.implicitHeight + 28
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: cardColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 14
            }
            spacing: 7

            RowLayout {
                Layout.bottomMargin: 3
                spacing: 10
                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 9
                    color: Appearance.colors.colPrimaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: card.modelData.group.icon
                        iconSize: 18
                        fill: 1
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr(card.modelData.group.name)
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.variableAxes: ({ "wght": 620, "wdth": 100 })
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: card.modelData.binds.length
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            Repeater {
                model: card.modelData.binds
                delegate: RowLayout {
                    id: bindRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr(bindRow.modelData.description)
                        wrapMode: Text.Wrap
                        font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                    KeyCombo {
                        Layout.alignment: Qt.AlignVCenter
                        mods: bindRow.modelData.mods
                        key: bindRow.modelData.key
                        keyColor: Appearance.colors.colLayer2
                        textColor: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }
}
