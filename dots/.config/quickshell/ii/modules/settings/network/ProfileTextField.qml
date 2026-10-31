import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** A text or number setting of the profile being edited. An empty field means "not set". */
ConfigTextRow {
    id: root
    required property string fieldKey
    property var defaultValue: ""
    wrapMode: TextEdit.NoWrap

    function show(): void {
        const current = ProfileEditor.value(root.fieldKey, root.defaultValue);
        const text = current === null || current === undefined ? "" : `${current}`;
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
            if (root.textField.activeFocus) ProfileEditor.set(root.fieldKey, root.textField.text);
        }
    }
}
