import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** An on/off setting of the profile being edited. */
ConfigSwitch {
    id: root
    required property string fieldKey
    property bool defaultValue: false
    autoToggle: false
    checked: ProfileEditor.value(root.fieldKey, root.defaultValue) === true
    onClicked: ProfileEditor.set(root.fieldKey, !root.checked)
}
