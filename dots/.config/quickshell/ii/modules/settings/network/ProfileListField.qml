import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** A list of addresses or names of the profile being edited, typed separated by commas. */
ConfigTextRow {
    id: root
    required property string fieldKey
    wrapMode: TextEdit.NoWrap

    function show(): void {
        const text = (ProfileEditor.value(root.fieldKey, []) ?? []).join(", ");
        if (root.textField.text !== text) root.textField.text = text;
    }

    Component.onCompleted: root.show()
    Connections {
        target: ProfileEditor
        function onReloaded() {
            root.show();
        }
    }
    Connections {
        target: root.textField
        function onTextChanged() {
            if (root.textField.activeFocus) ProfileEditor.set(root.fieldKey, root.textField.text.split(/[,\s]+/).filter(item => item.length > 0));
        }
    }
}
