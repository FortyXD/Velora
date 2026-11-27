pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings

ColumnLayout {
    id: root
    required property string command
    property bool editing: false
    signal saved(string value)
    spacing: 6

    function submit() {
        const value = field.text.trim();
        if (!value) return;
        saved(value);
        editing = false;
        edit.forceActiveFocus(Qt.TabFocusReason);
    }
    SettingsAction {
        id: edit
        objectName: "editRoleCommand"
        visible: !root.editing
        Layout.fillWidth: true
        implicitHeight: 38
        horizontalPadding: 10
        text: Translation.tr("Custom command…")
        Accessible.description: root.command
        onClicked: {
            root.editing = true;
            field.text = root.command;
            field.forceActiveFocus();
        }
        contentItem: RowLayout {
            spacing: 8
            MaterialSymbol { text: "terminal"; iconSize: 19; color: Appearance.colors.colPrimary }
            StyledText { text: edit.text; font.pixelSize: Appearance.font.pixelSize.small }
            StyledText {
                Layout.fillWidth: true
                text: root.command
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            MaterialSymbol { text: root.command ? "edit" : "chevron_right"; iconSize: 17; color: Appearance.colors.colSubtext }
        }
    }
    RowLayout {
        visible: root.editing
        Layout.fillWidth: true
        TextField {
            id: field
            objectName: "roleCommandInput"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitHeight: 38
            leftPadding: 10
            placeholderText: Translation.tr("Command")
            Accessible.name: placeholderText
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colOnLayer3
            placeholderTextColor: Appearance.colors.colSubtext
            background: Rectangle {
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                border.color: field.activeFocus ? Appearance.colors.colPrimary : "transparent"
            }
            onAccepted: root.submit()
            Keys.onEscapePressed: { root.editing = false; edit.forceActiveFocus(); }
        }
        SettingsToolButton {
            mainText: Translation.tr("Save")
            materialIcon: "check"
            enabled: !!field.text.trim()
            onClicked: root.submit()
        }
    }
}
