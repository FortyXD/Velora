import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings row: icon tile, title with optional description, and a dropdown on the right.
 * `options` and `currentValue` work like ChoiceDropdown. With `customLabel` set the list ends with
 * an item that shows a text field under the row; Enter there emits customEntered(text).
 */
ColumnLayout {
    id: root
    property string icon: ""
    property string text: ""
    property string description: ""
    property alias options: dropdown.options
    property alias currentValue: dropdown.currentValue
    property alias dropdown: dropdown
    property alias searchable: dropdown.searchable
    property alias placeholderText: dropdown.placeholderText
    property alias maximumWidth: dropdown.maximumWidth
    property string customLabel: ""
    property string customDescription: ""
    property string customPlaceholder: ""
    property string customValue: ""          // Shown in the field and on the button while customActive
    property bool customActive: false        // The current value isn't one of the options
    property string customDisplayName: Translation.tr("Custom")
    property bool customMonospace: true
    property bool editingCustom: false

    signal selected(var value)
    signal customEntered(string text)

    readonly property bool settingsSearchable: true
    property string searchText: `${root.text} ${root.description} ${dropdown.displayText}`

    Layout.fillWidth: true
    spacing: 0
    opacity: root.enabled ? 1 : 0.4

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 6
        Layout.topMargin: 5
        Layout.bottomMargin: 5
        spacing: 12

        ConfigIconTile {
            icon: root.icon
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: root.text
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                visible: root.description.length > 0
                Layout.fillWidth: true
                text: root.description
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        ChoiceDropdown {
            id: dropdown
            customLabel: root.customLabel
            customDescription: root.customDescription
            customSelected: root.customActive
            displayText: root.customActive ? (root.customValue.length > 0 ? root.customValue : root.customDisplayName)
                : (dropdown.currentOption?.displayName ?? dropdown.placeholderText)
            displayIcon: root.customActive ? "edit" : (dropdown.currentOption?.icon ?? "")
            onSelected: value => {
                root.editingCustom = false;
                root.selected(value);
            }
            onCustomRequested: {
                root.editingCustom = true;
                customField.value = root.customValue;
                customField.textField.forceActiveFocus();
            }
        }
    }

    ConfigTextRow {
        id: customField
        visible: root.customLabel.length > 0 && root.editingCustom
        Layout.leftMargin: 50
        icon: ""
        label: ""
        monospace: root.customMonospace
        wrapMode: TextEdit.NoWrap
        placeholderText: root.customPlaceholder
        value: root.customValue
        onEditingFinished: {
            const text = customField.value.trim();
            if (text.length === 0) return;
            root.editingCustom = false;
            if (text !== root.customValue || !root.customActive) root.customEntered(text);
        }
    }
}
