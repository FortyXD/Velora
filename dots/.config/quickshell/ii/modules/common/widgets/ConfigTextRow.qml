import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings row with a label and a text field.
 * With `inline` the field sits to the right of the label, otherwise below it.
 * `value` is the field's text: bind it to the config and write back in onValueChanged.
 */
GridLayout {
    id: root
    property string label: ""
    property string icon: ""
    property string description: ""
    property alias placeholderText: field.placeholderText
    property alias value: field.text
    property alias wrapMode: field.wrapMode
    property alias textField: field
    property bool inline: false
    property real inlineFieldWidth: 260
    property bool monospace: false
    property real fieldMinimumHeight: 0

    signal editingFinished()

    readonly property bool settingsSearchable: root.label.length > 0
    property string searchText: `${root.label} ${root.description} ${field.placeholderText}`

    readonly property bool fieldBeside: root.inline && root.width >= root.inlineFieldWidth * 2
    columns: root.fieldBeside ? 2 : 1
    columnSpacing: 12
    rowSpacing: 8
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    Layout.topMargin: 6
    Layout.bottomMargin: 8
    opacity: root.enabled ? 1 : 0.4

    RowLayout {
        visible: root.label.length > 0 || root.icon.length > 0
        Layout.fillWidth: true
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
                text: root.label
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
    }

    StyledTextArea {
        id: field
        Layout.fillWidth: !root.fieldBeside
        Layout.preferredWidth: root.fieldBeside ? root.inlineFieldWidth : -1
        Layout.maximumWidth: root.fieldBeside ? root.inlineFieldWidth : Number.POSITIVE_INFINITY
        implicitWidth: 120 // Long single-line text scrolls instead of widening the row
        clip: true
        Layout.alignment: Qt.AlignVCenter
        Layout.minimumHeight: root.fieldMinimumHeight
        onEditingFinished: root.editingFinished()
        // Single-line fields: Enter confirms instead of adding a line break
        Keys.onReturnPressed: event => {
            if (field.wrapMode === TextEdit.NoWrap) root.editingFinished();
            else event.accepted = false;
        }
        Keys.onEnterPressed: event => {
            if (field.wrapMode === TextEdit.NoWrap) root.editingFinished();
            else event.accepted = false;
        }
        wrapMode: TextEdit.Wrap
        leftPadding: 14
        rightPadding: 14
        topPadding: 11
        bottomPadding: 11
        color: Appearance.colors.colOnLayer3
        font.family: root.monospace ? Appearance.font.family.monospace : Appearance.font.family.main
        background: Rectangle {
            implicitHeight: 42
            radius: Appearance.rounding.small
            color: field.hovered && !field.activeFocus ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
            border.width: field.activeFocus ? 2 : 0
            border.color: Appearance.colors.colPrimary
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
